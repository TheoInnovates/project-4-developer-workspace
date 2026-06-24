"""
title: Web Fetch
author: local
version: 0.1.0
license: MIT
description: Fetches a specific URL and returns its readable text. Complements SearXNG search (which finds pages; this reads one).
"""
import re
import requests


class Tools:
    def __init__(self):
        pass

    def fetch_url(self, url: str) -> str:
        """
        Fetch a web page or HTTP API by URL and return its text content (HTML stripped).
        Use to read a specific page the user names or that a search surfaced. NOTE: this
        host has limited internet egress — intranet / Tailscale URLs are most reliable.
        :param url: The full http/https URL to fetch.
        :return: The page's text content (truncated to ~6000 chars), or an error message.
        """
        if not url.lower().startswith(("http://", "https://")):
            return "Error: url must start with http:// or https://"
        try:
            r = requests.get(
                url, timeout=15,
                headers={"User-Agent": "OpenWebUI-WebFetch/0.1"},
            )
            r.raise_for_status()
            text = r.text
            if "html" in r.headers.get("content-type", "").lower():
                text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", text)
                text = re.sub(r"(?s)<[^>]+>", " ", text)
                text = re.sub(r"\s+", " ", text).strip()
            return text[:6000] if text else "(empty response)"
        except Exception as e:
            return f"Error fetching {url}: {e}"
