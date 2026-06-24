"""
title: CUI / PII Redaction
author: local
version: 0.1.0
license: MIT
description: Masks secrets (API keys, tokens, private keys), emails, SSNs and card numbers in model output before it is shown, logged, or exported. Defense-in-depth for controlled data. Toggle per chat, or enable globally.
"""
import re
from pydantic import BaseModel, Field


class Filter:
    class Valves(BaseModel):
        redact_secrets: bool = Field(default=True, description="Mask API keys, tokens, and private keys.")
        redact_emails: bool = Field(default=True, description="Mask email addresses.")
        redact_ssn_cards: bool = Field(default=True, description="Mask SSNs and credit-card-like numbers.")
        redact_ipv4: bool = Field(default=False, description="Mask IPv4 addresses (noisy — off by default).")
        also_redact_input: bool = Field(default=False, description="Also redact the user's input (inlet), not just output.")

    def __init__(self):
        self.valves = self.Valves()
        self.toggle = True  # expose a per-chat on/off toggle in the UI

    def _patterns(self):
        v = self.valves
        pats = []
        if v.redact_secrets:
            pats += [
                (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"), "[REDACTED:private-key]"),
                (re.compile(r"\bglpat-[A-Za-z0-9._-]{20,}"), "[REDACTED:gitlab-token]"),
                (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), "[REDACTED:github-token]"),
                (re.compile(r"\bsk-[A-Za-z0-9]{20,}"), "[REDACTED:api-key]"),
                (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"), "[REDACTED:slack-token]"),
                (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED:aws-key]"),
                (re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"), "[REDACTED:jwt]"),
            ]
        if v.redact_emails:
            pats.append((re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "[REDACTED:email]"))
        if v.redact_ssn_cards:
            pats.append((re.compile(r"\b\d{3}-\d{2}-\d{4}\b"), "[REDACTED:ssn]"))
            pats.append((re.compile(r"\b(?:\d{4}[ -]?){3}\d{4}\b"), "[REDACTED:card]"))
        if v.redact_ipv4:
            pats.append((re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "[REDACTED:ip]"))
        return pats

    def _scrub(self, text):
        if not isinstance(text, str):
            return text
        for pat, repl in self._patterns():
            text = pat.sub(repl, text)
        return text

    def _scrub_messages(self, body, roles):
        for msg in (body or {}).get("messages", []):
            if msg.get("role") not in roles:
                continue
            content = msg.get("content")
            if isinstance(content, str):
                msg["content"] = self._scrub(content)
            elif isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and isinstance(part.get("text"), str):
                        part["text"] = self._scrub(part["text"])
        return body

    def inlet(self, body: dict) -> dict:
        if self.valves.also_redact_input:
            return self._scrub_messages(body, {"user"})
        return body

    def outlet(self, body: dict) -> dict:
        return self._scrub_messages(body, {"assistant"})
