#!/usr/bin/env bash
# Initialize GitLab on a Linux deployment:
#   - create the `developers` group
#   - create the `theo` user and add them to the group as Maintainer
#   - register an instance GitLab Runner (docker executor)
#
# Idempotent — safe to re-run. Requires the gitlab + gitlab-runner containers to
# be running and GitLab to be healthy.
#
# Usage: scripts/gitlab-setup.sh [env-file]      (default: .env.spark-d5dd)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${1:-$REPO_ROOT/.env.spark-d5dd}"

getenv() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }
GITLAB_HOST="$(getenv GITLAB_HOST)"
TAILSCALE_IP="$(getenv TAILSCALE_IP)"
GITLAB_URL="https://${GITLAB_HOST}"

DEV_USER="theo"
DEV_PASS="Th3o_Dev!2026"
DEV_EMAIL="theo@local.dev"

# Hit Caddy with correct SNI (valid cert) via the Tailscale IP, independent of
# external DNS resolution.
RESOLVE=()
[[ -n "$TAILSCALE_IP" ]] && RESOLVE=(--resolve "${GITLAB_HOST}:443:${TAILSCALE_IP}")
api() { curl -fsS "${RESOLVE[@]}" -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
field() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))"; }

echo "==> Minting a temporary root API token (rails console)..."
TOKEN="$(docker exec gitlab gitlab-rails runner "
t = User.find_by_username('root').personal_access_tokens.create!(name: 'setup-script', scopes: ['api','create_runner'], expires_at: 1.day.from_now)
puts t.token
" 2>/dev/null | tail -1 | tr -d '\r')"
[[ -n "$TOKEN" && ${#TOKEN} -ge 20 ]] || { echo "ERROR: could not mint root token" >&2; exit 1; }
echo "    token created."

echo "==> Ensuring group 'developers'..."
GID="$(api "$GITLAB_URL/api/v4/groups?search=developers" \
  | python3 -c 'import json,sys; g=[x for x in json.load(sys.stdin) if x.get("path")=="developers"]; print(g[0]["id"] if g else "")')"
if [[ -z "$GID" ]]; then
  GID="$(api -X POST "$GITLAB_URL/api/v4/groups" \
    --data-urlencode name=developers --data-urlencode path=developers \
    --data-urlencode visibility=internal | field id)"
  echo "    created (id=$GID)."
else
  echo "    already exists (id=$GID)."
fi

echo "==> Ensuring user '$DEV_USER'..."
DEV_ID="$(api "$GITLAB_URL/api/v4/users?username=$DEV_USER" \
  | python3 -c 'import json,sys; u=json.load(sys.stdin); print(u[0]["id"] if u else "")')"
if [[ -z "$DEV_ID" ]]; then
  DEV_ID="$(api -X POST "$GITLAB_URL/api/v4/users" \
    --data-urlencode "email=$DEV_EMAIL" --data-urlencode "username=$DEV_USER" \
    --data-urlencode "name=Theo" --data-urlencode "password=$DEV_PASS" \
    --data-urlencode skip_confirmation=true | field id)"
  echo "    created (id=$DEV_ID)."
else
  echo "    already exists (id=$DEV_ID)."
fi

echo "==> Ensuring '$DEV_USER' is a Maintainer of 'developers'..."
if api -X POST "$GITLAB_URL/api/v4/groups/$GID/members" \
     --data-urlencode "user_id=$DEV_ID" --data-urlencode access_level=40 >/dev/null 2>&1; then
  echo "    added."
else
  echo "    already a member (skipped)."
fi

echo "==> GitLab Runner registration..."
if docker exec gitlab-runner cat /etc/gitlab-runner/config.toml 2>/dev/null | grep -q '\[\[runners\]\]'; then
  echo "    already registered, skipping."
else
  RUNNER_TOKEN="$(api -X POST "$GITLAB_URL/api/v4/user/runners" \
    --data-urlencode runner_type=instance_type \
    --data-urlencode description=devstack-runner \
    --data-urlencode 'tag_list[]=docker' --data-urlencode 'tag_list[]=devstack' \
    --data-urlencode run_untagged=true | field token)"
  if [[ -n "$RUNNER_TOKEN" ]]; then
    docker exec gitlab-runner gitlab-runner register --non-interactive \
      --url "http://gitlab" --token "$RUNNER_TOKEN" --executor docker \
      --docker-image "alpine:latest" --docker-network-mode "devstack"
    echo "    registered."
  else
    echo "ERROR: failed to create runner token" >&2
  fi
fi

echo "==> Revoking the temporary token..."
docker exec gitlab gitlab-rails runner "PersonalAccessToken.find_by_name('setup-script')&.revoke!" >/dev/null 2>&1 || true

cat <<EOF

Setup complete!
  User:   $DEV_USER / $DEV_PASS  (change on first login)
  Group:  developers (Maintainer role)
  Runner: devstack-runner (docker executor)
  Login:  $GITLAB_URL
EOF
