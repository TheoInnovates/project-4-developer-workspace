# OpenWebUI customizations

Custom tools, functions, and settings layered onto the `openwebui` service. The
live source of truth is the OpenWebUI DB (in the `openwebui-data` volume); these
files are the version-controlled copies + reproduction notes.

## Custom Tools (`tools/`)
Installed via `POST /api/v1/tools/create` (admin token). Enable per-model
(Workspace → Models → Tools) and set **Function Calling = Native** on the model.

| Tool | Functions | Reaches |
|------|-----------|---------|
| `spark_model_status` | `get_spark_model_status` | both Sparks `/health` `/v1/models` `/metrics` |
| `infra_ops` | `prometheus_query`, `service_health`, `query_logs`, `active_alerts` | `prometheus:9090`, `loki:3100`, `alertmanager:9093` |
| `gitlab` | `search_projects`, `list_issues`, `list_merge_requests`, `pipeline_status` | `http://gitlab` (read_api PAT in valve, **not** in source) |
| `bc3_documentation_lookup` | `search_bc3_documentation` | BC3 KB vector collection |
| `web_fetch` | `fetch_url` | arbitrary URL (egress-limited host) |
| `calculator` | `calculate` | local (safe AST) |
| `time_date` | `get_current_datetime` | local |

The GitLab token is a **read-only** (`read_api`) PAT named `openwebui-tool` stored
in the tool's valve. Rotate/revoke in GitLab → root → Access Tokens.

## Custom Functions (`functions/`)
Installed via `POST /api/v1/functions/create` (type auto-detected by class name).

- `auto_spark_router` (**Pipe**) — model **"Auto (Spark)"**; routes coding/debug
  turns to Qwen3-Coder (spark-06ad) and reasoning turns to Nemotron (spark-d5dd),
  streams the chosen model. Shows a `> routed to …` banner (valve `show_route`).
- `cui_pii_redaction` (**Filter**) — masks secrets/tokens/keys, emails, SSNs and
  card numbers in model output (outlet; optional inlet). Per-chat toggle. Valves
  pick which categories to mask. Defense-in-depth — not a guarantee.

## Settings enabled (also seeded as env in `docker-compose.yml`)
- **RAG**: hybrid BM25 + local cross-encoder reranking
  (`cross-encoder/ms-marco-MiniLM-L-6-v2`), `RAG_TOP_K=20`, `RAG_TOP_K_RERANKER=5`.
  No reindex needed — both operate at query time. (openwebui mem limit raised 1G→2G
  to fit the reranker.)
- **Code Interpreter**: enabled, **Pyodide** engine (browser sandbox).
- **Model Arena**: "Spark Arena (Nemotron vs Coder)" for blind A/B + Elo.
- **Memory**: available (default on); each user toggles in Settings → Personalization.

### Seeded Prompts (slash commands)
`/code-review`, `/think-hard`, `/cite-bc3`

### Seeded Skills
`BC3 SME`, `Infra On-Call`, `Code Reviewer`

## Reproduce on a fresh deployment
1. `docker compose ... up -d openwebui` (env in compose seeds the RAG/code settings).
2. Re-install tools/functions: `POST /api/v1/tools/create` and
   `/functions/create` with each file's content (mint an admin token from
   `/app/backend/.webui_secret_key`). Set the GitLab tool's `token` valve.
3. Re-create the Spark Arena, Prompts, and Skills (or restore the DB volume).

## Backlog / upgrades
- **Server-side code execution**: stand up a *dedicated* Jupyter kernel-gateway
  container **with a token** and point `CODE_INTERPRETER_ENGINE=jupyter` at it.
  The interactive jupyter on `:11002` is token-less + XSRF-protected, so OpenWebUI
  cannot create kernels on it.
- Agentic self-correction loop pipe (Qwen3 → run → Nemotron fixes → retry).
- MCP servers via `mcpo` (filesystem/git/time/fetch) → Admin → Tools → Tool Servers.
- Query-rewriting RAG filter; GitLab write ops (scoped token); ComfyUI image gen
  (needs unified-memory carve-out from Nemotron).
