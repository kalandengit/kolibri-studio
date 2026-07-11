#!/usr/bin/env bash
# Show the health of a VPS deployment at a glance.
#   sudo bash deploy/status-vps.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.deploy.yml"
ENV_FILE="$SCRIPT_DIR/.env"
compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

PORT="$(grep -E '^STUDIO_HTTP_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)"
PORT="${PORT:-8080}"

echo "=== containers ==="
compose ps
echo
echo "=== app health ==="
code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:${PORT}/" || true)"
echo "http://127.0.0.1:${PORT}/ -> HTTP ${code:-no answer}"
echo
echo "=== resources ==="
free -h | head -2
df -h / | tail -1
echo
echo "Logs: docker compose -f $COMPOSE_FILE --env-file $ENV_FILE logs -f [service]"
