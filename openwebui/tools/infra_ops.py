"""
title: Infra Ops
author: local
version: 0.1.0
license: MIT
description: Query the self-hosted devstack — Prometheus metrics, service health, Loki logs, and Alertmanager alerts. Read-only, local network.
"""
import time
import requests
from pydantic import BaseModel, Field


class Tools:
    class Valves(BaseModel):
        prometheus_url: str = Field(default="http://prometheus:9090", description="Prometheus base URL.")
        loki_url: str = Field(default="http://loki:3100", description="Loki base URL.")
        alertmanager_url: str = Field(default="http://alertmanager:9093", description="Alertmanager base URL.")
        timeout: int = Field(default=10, description="Per-request timeout (seconds).")

    def __init__(self):
        self.valves = self.Valves()

    def prometheus_query(self, promql: str) -> str:
        """
        Run an instant PromQL query against Prometheus and return the result series.
        Use for resource/metric questions, e.g. host memory, CPU, request rates.
        Examples: 'node_memory_MemAvailable_bytes', 'rate(container_cpu_usage_seconds_total[5m])'.
        :param promql: A PromQL expression.
        :return: The matching series as 'labels = value' lines.
        """
        try:
            r = requests.get(self.valves.prometheus_url.rstrip("/") + "/api/v1/query",
                             params={"query": promql}, timeout=self.valves.timeout)
            r.raise_for_status()
            data = r.json().get("data", {})
            res = data.get("result", [])
            if not res:
                return f"No data for: {promql}"
            out = []
            for s in res[:30]:
                m = s.get("metric", {})
                label = m.get("__name__", "") + "{" + ",".join(
                    f'{k}="{v}"' for k, v in m.items() if k != "__name__") + "}"
                val = (s.get("value") or [None, "?"])[1]
                out.append(f"{label} = {val}")
            return "\n".join(out)
        except Exception as e:
            return f"Prometheus error: {str(e)[:180]}"

    def service_health(self) -> str:
        """
        Report which monitored services/targets are UP or DOWN (via Prometheus 'up').
        Use when asked whether services are healthy or what's down.
        :return: Each scrape target with UP/DOWN status.
        """
        try:
            r = requests.get(self.valves.prometheus_url.rstrip("/") + "/api/v1/query",
                             params={"query": "up"}, timeout=self.valves.timeout)
            r.raise_for_status()
            res = r.json().get("data", {}).get("result", [])
            if not res:
                return "No targets reported by Prometheus."
            lines = []
            for s in sorted(res, key=lambda x: x.get("metric", {}).get("job", "")):
                m = s.get("metric", {})
                up = (s.get("value") or [None, "0"])[1] == "1"
                name = m.get("job") or m.get("instance") or "?"
                lines.append(f"- {'UP  ' if up else 'DOWN'} {name} ({m.get('instance', '')})")
            down = sum(1 for s in res if (s.get('value') or [None, '0'])[1] != '1')
            return f"{len(res)} targets, {down} down:\n" + "\n".join(lines)
        except Exception as e:
            return f"Prometheus error: {str(e)[:180]}"

    def query_logs(self, logql: str, hours: int = 1) -> str:
        """
        Query aggregated logs from Loki over a recent time window. Use to find errors
        or events. logql is a Loki query, e.g. '{container="gitlab"} |= "error"' or
        '{container=~"nextup.*"}'.
        :param logql: A LogQL query (must include a {label} stream selector).
        :param hours: How many hours back to search (default 1).
        :return: Up to ~25 recent matching log lines with timestamps.
        """
        try:
            now = time.time()
            params = {
                "query": logql,
                "start": str(int((now - hours * 3600) * 1e9)),
                "end": str(int(now * 1e9)),
                "limit": 25, "direction": "backward",
            }
            r = requests.get(self.valves.loki_url.rstrip("/") + "/loki/api/v1/query_range",
                             params=params, timeout=self.valves.timeout)
            r.raise_for_status()
            streams = r.json().get("data", {}).get("result", [])
            rows = []
            for st in streams:
                cont = st.get("stream", {}).get("container", "")
                for ts, line in st.get("values", []):
                    rows.append((int(ts), cont, line))
            if not rows:
                return f"No log lines for: {logql} (last {hours}h)"
            rows.sort(reverse=True)
            out = []
            for ts, cont, line in rows[:25]:
                t = time.strftime("%H:%M:%S", time.localtime(ts / 1e9))
                out.append(f"[{t}] {cont}: {line.strip()[:200]}")
            return "\n".join(out)
        except Exception as e:
            return f"Loki error: {str(e)[:180]}"

    def active_alerts(self) -> str:
        """
        List currently firing/active alerts from Alertmanager.
        :return: Active alerts with name, severity, and summary.
        """
        try:
            r = requests.get(self.valves.alertmanager_url.rstrip("/") + "/api/v2/alerts",
                             params={"active": "true", "silenced": "false"}, timeout=self.valves.timeout)
            r.raise_for_status()
            alerts = r.json()
            if not alerts:
                return "No active alerts. All clear."
            out = []
            for a in alerts[:30]:
                labels = a.get("labels", {})
                ann = a.get("annotations", {})
                out.append(f"- [{labels.get('severity', '?')}] {labels.get('alertname', '?')}: "
                           f"{ann.get('summary') or ann.get('description') or ''}".strip())
            return f"{len(alerts)} active alert(s):\n" + "\n".join(out)
        except Exception as e:
            return f"Alertmanager error: {str(e)[:180]}"
