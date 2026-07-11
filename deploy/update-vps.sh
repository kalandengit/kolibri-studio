#!/usr/bin/env bash
# Update a VPS deployment to the latest code + images, migrate, and smoke test.
#   sudo bash deploy/update-vps.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.deploy.yml"
ENV_FILE="$SCRIPT_DIR/.env"
log() { echo -e "\033[1;32m[studio-update]\033[0m $*"; }

[[ -f "$ENV_FILE" ]] || { echo "No $ENV_FILE - run install-vps.sh first." >&2; exit 1; }
compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

log "Pulling latest code..."
git -C "$SCRIPT_DIR/.." pull --ff-only

log "Pulling latest images..."
compose pull studio-app studio-nginx || log "Pull failed - keeping current images."

log "Restarting stack..."
compose up -d --remove-orphans

log "Running migrations..."
compose exec -T studio-app make migrate

PORT="$(grep -E '^STUDIO_HTTP_PORT=' "$ENV_FILE" | cut -d= -f2 || true)"
PORT="${PORT:-8080}"
log "Smoke test on port $PORT..."
for i in $(seq 1 20); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:${PORT}/" || true)"
  case "$code" in 200|301|302) log "OK (HTTP $code)"; exit 0;; esac
  sleep 3
done
echo "Smoke test failed (last: ${code:-none})" >&2
compose ps
exit 1
