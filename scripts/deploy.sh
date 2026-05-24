#!/usr/bin/env bash
# Deploy or update the devstack on the OCI instance via Tailscale SSH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STACK_ENV="$REPO_ROOT/stack.env"

# Load stack.env
if [[ -f "$STACK_ENV" ]]; then
  export $(grep -v '^\s*#' "$STACK_ENV" | xargs)
fi

# Select env file based on TLS_PROFILE
ENV_FILE="${1:-.env.cloud}"
if [[ "${TLS_PROFILE:-cloud}" == "aws" ]]; then
  ENV_FILE=".env.aws"
fi

echo "Deploying to devstack via Tailscale SSH (env: $ENV_FILE)..."
tailscale ssh ubuntu@devstack \
  "cd /opt/devstack && git pull && export \$(grep -v '^\s*#' stack.env | xargs) && docker compose -f docker-compose.yml -f docker-compose.cloud.yml --env-file $ENV_FILE up -d"

echo "Deploy complete."
