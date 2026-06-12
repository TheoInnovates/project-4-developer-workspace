#!/usr/bin/env bash
# Back up the stateful services to a timestamped directory.
#
#   - GitLab: application backup via `gitlab-backup create` + the secrets/config
#     files it deliberately excludes (gitlab-secrets.json, gitlab.rb)
#   - Nexus, MinIO, Vault, Grafana: tar of the bind-mounted volume directory
#
# Usage: scripts/backup.sh [-e env-file] [-d backup-dir] [-k keep]
#   -e  env file to read VOLUMES_BASE from   (default: .env.spark-d5dd)
#   -d  backup destination                   (default: $HOME/devstack/backups)
#   -k  number of timestamped backups to keep (default: 7)
#
# Intended for cron, e.g.:  0 3 * * *  bash /path/to/scripts/backup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$REPO_ROOT/.env.spark-d5dd"
BACKUP_DIR="$HOME/devstack/backups"
KEEP=7

while getopts "e:d:k:" opt; do
  case "$opt" in
    e) ENV_FILE="$OPTARG" ;;
    d) BACKUP_DIR="$OPTARG" ;;
    k) KEEP="$OPTARG" ;;
    *) echo "Usage: $0 [-e env-file] [-d backup-dir] [-k keep]" >&2; exit 1 ;;
  esac
done

getenv() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }
VOLUMES_BASE="$(getenv VOLUMES_BASE)"
[[ -n "$VOLUMES_BASE" && -d "$VOLUMES_BASE" ]] || {
  echo "ERROR: VOLUMES_BASE not set in $ENV_FILE or directory missing" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/$STAMP"
mkdir -p "$DEST"
echo "==> Backing up to $DEST"

running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]; }

# The volume dirs are owned by the containers' users (root, etc.), so all
# reads go through Docker rather than the host user.

# --- GitLab: application-level backup (consistent across db + repos) --------
if running gitlab; then
  echo "==> GitLab: gitlab-backup create (this can take a few minutes)..."
  docker exec gitlab gitlab-backup create STRATEGY=copy CRON=1
  LATEST="$(docker exec gitlab sh -c 'ls -t /var/opt/gitlab/backups/*_gitlab_backup.tar | head -1')"
  docker cp "gitlab:$LATEST" "$DEST/"
  # gitlab-backup intentionally omits these; without them the backup is useless
  docker cp gitlab:/etc/gitlab/gitlab-secrets.json "$DEST/"
  docker cp gitlab:/etc/gitlab/gitlab.rb "$DEST/"
  echo "    $(basename "$LATEST") + gitlab-secrets.json + gitlab.rb"
else
  echo "==> GitLab: container not running, skipping"
fi

# --- Volume tars for the other stateful services -----------------------------
# Live files can change mid-archive; that only makes the tar crash-consistent,
# same as a power loss — acceptable here (tolerate tar rc=1, fail otherwise).
for vol in nexus-data minio-data vault-data grafana-data; do
  if [[ -d "$VOLUMES_BASE/$vol" ]]; then
    echo "==> Archiving $vol..."
    docker run --rm -v "$VOLUMES_BASE:/vols:ro" -v "$DEST:/dest" alpine:3 \
      sh -c "tar -czf '/dest/$vol.tar.gz' -C /vols '$vol' || [ \$? -eq 1 ]; chown $(id -u):$(id -g) '/dest/$vol.tar.gz'"
  else
    echo "==> $vol: not present, skipping"
  fi
done

# --- Prune old backups --------------------------------------------------------
echo "==> Pruning to the $KEEP most recent backups..."
ls -dt "$BACKUP_DIR"/*/ 2>/dev/null | tail -n "+$((KEEP + 1))" | xargs -r rm -rf

echo "==> Done:"
du -sh "$DEST"/* | sed 's/^/    /'
