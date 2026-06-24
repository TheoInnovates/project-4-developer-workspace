"""
title: GitLab
author: local
version: 0.1.0
license: MIT
description: Query the self-hosted GitLab (projects, issues, merge requests, CI pipelines) over the local network. Read-only.
"""
import urllib.parse
import requests
from pydantic import BaseModel, Field


class Tools:
    class Valves(BaseModel):
        base_url: str = Field(
            default="http://gitlab",
            description="GitLab base URL reachable from the OpenWebUI container.",
        )
        token: str = Field(
            default="",
            description="GitLab personal access token (read_api scope).",
        )
        timeout: int = Field(default=10, description="Per-request timeout (seconds).")

    def __init__(self):
        self.valves = self.Valves()

    def _api(self, path: str, params=None):
        if not self.valves.token:
            raise RuntimeError("No GitLab token configured (set the 'token' valve).")
        url = self.valves.base_url.rstrip("/") + "/api/v4/" + path.lstrip("/")
        r = requests.get(
            url,
            headers={"PRIVATE-TOKEN": self.valves.token},
            params=params or {},
            timeout=self.valves.timeout,
        )
        r.raise_for_status()
        return r.json()

    def _pid(self, project: str) -> str:
        return urllib.parse.quote(str(project), safe="")

    def search_projects(self, query: str) -> str:
        """
        Search GitLab projects by name or path. Call this FIRST to find the project
        path/id that the other GitLab functions need.
        :param query: Text to match against project names/paths.
        :return: Matching projects with full path, numeric id, and last activity date.
        """
        try:
            ps = self._api("projects", {
                "search": query, "simple": "true", "per_page": 10,
                "order_by": "last_activity_at", "membership": "false",
            })
            if not ps:
                return f"No projects match '{query}'."
            return "\n".join(
                f"- {p.get('path_with_namespace')} (id {p.get('id')}) — last activity {str(p.get('last_activity_at'))[:10]}"
                for p in ps
            )
        except Exception as e:
            return f"GitLab error: {str(e)[:180]}"

    def list_issues(self, project: str, state: str = "opened") -> str:
        """
        List issues for a GitLab project.
        :param project: Project numeric id or full path (e.g. "developers/myrepo").
        :param state: One of "opened", "closed", or "all".
        :return: Issues with their number, state, title, and author.
        """
        try:
            items = self._api(f"projects/{self._pid(project)}/issues",
                              {"state": state, "per_page": 20, "order_by": "updated_at"})
            if not items:
                return f"No {state} issues in {project}."
            return "\n".join(
                f"- #{i.get('iid')} [{i.get('state')}] {i.get('title')} — {i.get('author', {}).get('username')}"
                for i in items
            )
        except Exception as e:
            return f"GitLab error: {str(e)[:180]}"

    def list_merge_requests(self, project: str, state: str = "opened") -> str:
        """
        List merge requests for a GitLab project.
        :param project: Project numeric id or full path.
        :param state: One of "opened", "merged", "closed", or "all".
        :return: Merge requests with number, state, title, and source->target branches.
        """
        try:
            items = self._api(f"projects/{self._pid(project)}/merge_requests",
                              {"state": state, "per_page": 20, "order_by": "updated_at"})
            if not items:
                return f"No {state} merge requests in {project}."
            return "\n".join(
                f"- !{m.get('iid')} [{m.get('state')}] {m.get('title')} ({m.get('source_branch')} -> {m.get('target_branch')})"
                for m in items
            )
        except Exception as e:
            return f"GitLab error: {str(e)[:180]}"

    def pipeline_status(self, project: str) -> str:
        """
        Show the most recent CI/CD pipelines for a GitLab project and their status.
        :param project: Project numeric id or full path.
        :return: Recent pipelines with status, branch/ref, id, and update time.
        """
        try:
            items = self._api(f"projects/{self._pid(project)}/pipelines",
                              {"per_page": 10, "order_by": "updated_at"})
            if not items:
                return f"No pipelines found for {project}."
            return "\n".join(
                f"- #{p.get('id')} [{p.get('status')}] ref={p.get('ref')} — {str(p.get('updated_at'))[:19]}"
                for p in items
            )
        except Exception as e:
            return f"GitLab error: {str(e)[:180]}"
