#!/usr/bin/env bash
# Deploy project-4-workspace to one of the supported targets.
#
# Usage:
#   ./scripts/deploy.sh spark-d5dd     # Spark 1: dev stack + Nemotron
#   ./scripts/deploy.sh spark-06ad     # Spark 2: Coder only
#   ./scripts/deploy.sh devstack       # Legacy: OCI cloud (Tailscale)
#
# The target argument picks the env file, overlay, and COMPOSE_PROFILES.
# When the target is the current host, runs `docker compose` locally; otherwise
# uses `tailscale ssh` to drive the remote host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <spark-d5dd|spark-06ad|devstack>" >&2
  exit 1
fi

case "$TARGET" in
  spark-d5dd)
    ENV_FILE=".env.spark-d5dd"
    OVERLAY="docker-compose.spark-d5dd.yml"
    PROFILES="dev,monitoring,storage,security,infra,nemotron,webui,search,ide,status"
    SSH_TARGET=""                                          # run locally on spark-d5dd
    REMOTE_DIR="$REPO_ROOT"
    ;;
  spark-06ad)
    ENV_FILE=".env.spark-06ad"
    OVERLAY="docker-compose.spark-06ad.yml"
    PROFILES="coder"
    SSH_TARGET="spark-06ad"                                # plain ssh as $USER
    REMOTE_DIR="/home/tforrester/project-4-workspace"
    ;;
  devstack)
    ENV_FILE=".env.cloud"
    OVERLAY="docker-compose.cloud.yml"
    PROFILES="dev,monitoring,storage,security,infra"
    SSH_TARGET="tailscale_ubuntu_devstack"
    REMOTE_DIR="/opt/devstack"
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Valid targets: spark-d5dd, spark-06ad, devstack" >&2
    exit 1
    ;;
esac

COMPOSE_CMD="docker compose -f docker-compose.yml -f $OVERLAY --env-file $ENV_FILE --profile ${PROFILES//,/ --profile }"

echo "Deploying $TARGET..."
echo "  env file: $ENV_FILE"
echo "  overlay:  $OVERLAY"
echo "  profiles: $PROFILES"

if [[ -z "$SSH_TARGET" ]]; then
  cd "$REPO_ROOT"
  COMPOSE_PROFILES="$PROFILES" $COMPOSE_CMD up -d
elif [[ "$SSH_TARGET" == "tailscale_ubuntu_devstack" ]]; then
  tailscale ssh ubuntu@devstack \
    "cd $REMOTE_DIR && git pull && COMPOSE_PROFILES=$PROFILES $COMPOSE_CMD up -d"
else
  # Remote Spark via plain ssh — sync repo first, then compose up
  rsync -az --delete \
    --exclude='.git' --exclude='volumes/' --exclude='.env' --exclude='.env.*' \
    "$REPO_ROOT/" "$SSH_TARGET:$REMOTE_DIR/"
  # Copy the target env file separately so secrets aren't excluded by the rule above
  rsync -az "$REPO_ROOT/$ENV_FILE" "$SSH_TARGET:$REMOTE_DIR/$ENV_FILE"
  ssh "$SSH_TARGET" \
    "cd $REMOTE_DIR && COMPOSE_PROFILES=$PROFILES $COMPOSE_CMD up -d"
fi

echo "Deploy complete: $TARGET"
