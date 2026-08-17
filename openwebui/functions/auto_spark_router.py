"""
title: Auto (Spark) Router
author: local
version: 0.2.0
license: MIT
description: One model that auto-routes each turn between the two Spark vLLM endpoints. Streams the chosen model's reply.

The split is fast-lane vs smart-lane, not coding vs reasoning. Both models code
well; they differ by an order of magnitude in decode speed, because decode on a
GB10 is bandwidth-bound and these two sit at opposite ends of bytes-read-per-token:

  fast  (spark-06ad) Qwen3-Coder-Next-FP8  80B MoE, ~3B active  -> ~3GB/token
  smart (spark-d5dd) Qwen3.8-27B-FP8       27B dense            -> ~28GB/token

So short/mechanical turns go to fast, and anything wanting real deliberation
(or an image) goes to smart. Note the keyword heuristic below still sends
coding keywords to fast — that is a *speed* choice, not a quality one:
Qwen3.8-27B is the stronger coder (SWE-bench Pro 61.7 vs 44.3).
"""
import json
import requests
from pydantic import BaseModel, Field

OPENAI_PASSTHROUGH = (
    "temperature", "top_p", "max_tokens", "stop", "seed",
    "frequency_penalty", "presence_penalty", "tools", "tool_choice",
    # Without these two the smart lane's thinking controls are unreachable:
    # reasoning_effort would always fall through to the valve default, and
    # OpenWebUI's thinking toggle would silently no-op.
    "reasoning_effort", "chat_template_kwargs",
)


class Pipe:
    class Valves(BaseModel):
        smart_url: str = Field(default="http://100.108.158.44:8001/v1/chat/completions", description="Smart lane (spark-d5dd) chat-completions URL.")
        smart_model: str = Field(default="Qwen/Qwen3.8-27B-FP8", description="Smart lane model id.")
        smart_reasoning_effort: str = Field(default="low", description="reasoning_effort for the smart lane. Only 'low' and 'medium' can be sent on the wire; any other value (e.g. 'xhigh', 'default') omits the field, which is how the model's own xhigh default is selected. The model defaults to xhigh, which is expensive at ~8 tok/s — 'low' keeps interactive latency sane. Callers may override per request.")
        coder_url: str = Field(default="http://100.102.222.96:8001/v1/chat/completions", description="Fast lane (spark-06ad) chat-completions URL.")
        coder_model: str = Field(default="Qwen/Qwen3-Coder-Next-FP8", description="Fast lane model id.")
        api_key: str = Field(default="local-vllm-key", description="vLLM API key.")
        show_route: bool = Field(default=True, description="Prefix replies with a small banner showing which model was chosen.")
        timeout: int = Field(default=600, description="Upstream timeout (seconds).")

    def __init__(self):
        self.valves = self.Valves()

    def pipes(self):
        return [{"id": "auto-spark", "name": "Auto (Spark)"}]

    def _is_coding(self, text: str) -> bool:
        if "```" in text:
            return True
        t = text.lower()
        kws = (
            "code", "debug", "bug ", "error", "traceback", "exception", "stack trace",
            "compile", "refactor", "function", "def ", "class ", "import ", "regex",
            "sql", "docker", "kubernetes", "yaml", "json schema", "unit test", "pytest",
            "python", "javascript", "typescript", "rust", "golang", " git ", "endpoint",
            "implement", "syntax", "script", "snippet", "stacktrace",
        )
        return any(k in t for k in kws)

    def _last_user(self, messages):
        for m in reversed(messages or []):
            if m.get("role") == "user":
                c = m.get("content")
                if isinstance(c, list):
                    return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
                return c or ""
        return ""

    def pipe(self, body: dict):
        messages = body.get("messages", [])
        coding = self._is_coding(self._last_user(messages))
        if coding:
            url, model, label = self.valves.coder_url, self.valves.coder_model, "Qwen3-Coder (fast)"
        else:
            url, model, label = self.valves.smart_url, self.valves.smart_model, "Qwen3.8-27B (smart)"

        payload = {"model": model, "messages": messages}
        for k in OPENAI_PASSTHROUGH:
            if k in body and body[k] is not None:
                payload[k] = body[k]
        # Qwen3.8 thinks at reasoning_effort=xhigh unless told otherwise, and
        # that thinking is invisible latency: measured on spark-d5dd, "is 91
        # prime?" spends ~140 reasoning tokens at ~8.3 tok/s. Apply the valve
        # default only when the caller hasn't asked for something specific.
        #
        # 'xhigh' is requested by OMITTING the field, never by naming it. Two
        # validation layers disagree: vLLM's request schema checks against
        # OpenAI's enum (none|low|medium|high) and rejects 'xhigh', while the
        # model's chat template accepts (xhigh|medium|low) and rejects 'high'.
        # Only 'low' and 'medium' pass both; the template defaults to xhigh
        # when the field is absent. So anything else here means "send nothing".
        if not coding and "reasoning_effort" not in payload:
            effort = (self.valves.smart_reasoning_effort or "").strip().lower()
            if effort in ("low", "medium"):
                payload["reasoning_effort"] = effort
        stream = bool(body.get("stream", False))
        payload["stream"] = stream
        headers = {"Authorization": "Bearer " + self.valves.api_key, "Content-Type": "application/json"}
        banner = f"> *routed to {label}*\n\n" if self.valves.show_route else ""

        if not stream:
            try:
                r = requests.post(url, json=payload, headers=headers, timeout=self.valves.timeout)
                r.raise_for_status()
                content = r.json()["choices"][0]["message"]["content"]
                return banner + (content or "")
            except Exception as e:
                return f"Auto (Spark) routing error to {label}: {str(e)[:200]}"

        def gen():
            if banner:
                yield banner
            try:
                with requests.post(url, json=payload, headers=headers, stream=True, timeout=self.valves.timeout) as r:
                    r.raise_for_status()
                    for raw in r.iter_lines():
                        if not raw:
                            continue
                        line = raw.decode("utf-8", "ignore")
                        if not line.startswith("data: "):
                            continue
                        data = line[6:]
                        if data.strip() == "[DONE]":
                            break
                        try:
                            delta = json.loads(data)["choices"][0]["delta"].get("content")
                        except Exception:
                            continue
                        if delta:
                            yield delta
            except Exception as e:
                yield f"\n\n[Auto (Spark) routing error to {label}: {str(e)[:200]}]"

        return gen()
