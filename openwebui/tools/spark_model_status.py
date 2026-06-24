"""
title: Spark Model Status
author: local
version: 0.1.0
license: MIT
description: Live status of the self-hosted vLLM models on the two DGX Sparks (Nemotron on spark-d5dd, Qwen3-Coder on spark-06ad).
"""
import re
import requests
from pydantic import BaseModel, Field


class Tools:
    class Valves(BaseModel):
        nemotron_url: str = Field(
            default="http://100.108.158.44:8001",
            description="Nemotron vLLM base URL (spark-d5dd).",
        )
        coder_url: str = Field(
            default="http://100.102.222.96:8001",
            description="Qwen3-Coder vLLM base URL (spark-06ad).",
        )
        api_key: str = Field(default="local-vllm-key", description="vLLM API key.")
        timeout: int = Field(default=6, description="Per-request timeout (seconds).")

    def __init__(self):
        self.valves = self.Valves()

    def _probe(self, label: str, base: str) -> str:
        base = base.rstrip("/")
        # health
        try:
            h = requests.get(base + "/health", timeout=self.valves.timeout)
            health = "UP" if h.status_code == 200 else f"HTTP {h.status_code}"
        except Exception as e:
            return f"### {label}\n- status: **DOWN** ({str(e)[:70]})"

        model, max_len = "?", "?"
        try:
            data = requests.get(
                base + "/v1/models",
                headers={"Authorization": "Bearer " + self.valves.api_key},
                timeout=self.valves.timeout,
            ).json().get("data") or []
            if data:
                model = data[0].get("id", "?")
                max_len = data[0].get("max_model_len", "?")
        except Exception:
            pass

        stats = {}
        try:
            txt = requests.get(base + "/metrics", timeout=self.valves.timeout).text

            def metric(name):
                vals = re.findall(r"^" + re.escape(name) + r"(?:\{[^}]*\})?\s+([0-9.eE+-]+)$", txt, re.M)
                nums = [float(v) for v in vals]
                return sum(nums) if nums else None

            stats["running"] = metric("vllm:num_requests_running")
            stats["waiting"] = metric("vllm:num_requests_waiting")
            kv = metric("vllm:kv_cache_usage_perc")
            if kv is None:
                kv = metric("vllm:gpu_cache_usage_perc")  # older vLLM metric name
            stats["kv"] = round(kv * 100, 1) if kv is not None else None
            stats["prompt_toks"] = metric("vllm:prompt_tokens_total")
            stats["gen_toks"] = metric("vllm:generation_tokens_total")
        except Exception:
            pass

        def fmt(v):
            return "n/a" if v is None else (f"{int(v):,}" if isinstance(v, float) and v == int(v) else v)

        return (
            f"### {label}  —  **{health}**\n"
            f"- model: {model} (max context {max_len})\n"
            f"- in-flight: {fmt(stats.get('running'))} running, {fmt(stats.get('waiting'))} queued\n"
            f"- KV-cache usage: {stats.get('kv', 'n/a')}%\n"
            f"- tokens served (cumulative): {fmt(stats.get('prompt_toks'))} prompt / {fmt(stats.get('gen_toks'))} generated"
        )

    def get_spark_model_status(self) -> str:
        """
        Report the live status of the two self-hosted DGX Spark vLLM models (Nemotron on
        spark-d5dd, Qwen3-Coder on spark-06ad): up/down, served model and max context,
        running vs queued requests, KV-cache utilization, and cumulative tokens served.
        Use whenever the user asks whether the models/Sparks are up, how loaded they are,
        or about current inference capacity.
        :return: A formatted live status summary for both Sparks.
        """
        return "\n\n".join([
            self._probe("spark-d5dd · Nemotron", self.valves.nemotron_url),
            self._probe("spark-06ad · Qwen3-Coder", self.valves.coder_url),
        ])
