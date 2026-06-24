"""
title: Auto (Spark) Router
author: local
version: 0.1.0
license: MIT
description: One model that auto-routes each turn — coding/debugging to Qwen3-Coder (spark-06ad), reasoning/analysis/long-doc to Nemotron (spark-d5dd). Streams the chosen model's reply.
"""
import json
import requests
from pydantic import BaseModel, Field

OPENAI_PASSTHROUGH = (
    "temperature", "top_p", "max_tokens", "stop", "seed",
    "frequency_penalty", "presence_penalty", "tools", "tool_choice",
)


class Pipe:
    class Valves(BaseModel):
        nemotron_url: str = Field(default="http://100.108.158.44:8001/v1/chat/completions", description="Nemotron (reasoning) chat-completions URL.")
        nemotron_model: str = Field(default="nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4", description="Nemotron model id.")
        coder_url: str = Field(default="http://100.102.222.96:8001/v1/chat/completions", description="Qwen3-Coder chat-completions URL.")
        coder_model: str = Field(default="Qwen/Qwen3-Coder-Next-FP8", description="Coder model id.")
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
            url, model, label = self.valves.coder_url, self.valves.coder_model, "Qwen3-Coder"
        else:
            url, model, label = self.valves.nemotron_url, self.valves.nemotron_model, "Nemotron"

        payload = {"model": model, "messages": messages}
        for k in OPENAI_PASSTHROUGH:
            if k in body and body[k] is not None:
                payload[k] = body[k]
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
