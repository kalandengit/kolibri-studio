#!/usr/bin/env bash
# =============================================================================
# Kolibri Studio - one-shot installer for any cloud VPS (Ubuntu/Debian/RHEL/
# Fedora/CentOS/Rocky/Alma). Installs Docker, builds the production image,
# starts the full stack (PostgreSQL, Redis, MinIO, Django app, Celery) and
# runs migrations.
#
# Usage (as root, from the project root):
#   sudo bash deploy/install-vps.sh [--with-demo-data] [--port 8080]
#
# Re-running is safe: it reuses the existing deploy/.env and volumes.
# =============================================================================
set -euo pipefail

WITH_DEMO_DATA=0
STUDIO_HTTP_PORT="${STUDIO_HTTP_PORT:-8080}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-demo-data) WITH_DEMO_DATA=1; shift ;;
    --port) STUDIO_HTTP_PORT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.deploy.yml"
ENV_FILE="$SCRIPT_DIR/.env"

log()  { echo -e "\033[1;32m[studio-install]\033[0m $*"; }
fail() { echo -e "\033[1;31m[studio-install]\033[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run as root: sudo bash deploy/install-vps.sh"
[[ -f "$PROJECT_ROOT/package.json" && -d "$PROJECT_ROOT/contentcuration" ]] \
  || fail "Run from a full checkout of the studio project (deploy/ must sit next to contentcuration/)."

# --- 1. Base packages --------------------------------------------------------
log "Installing base packages..."
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates openssl >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q curl ca-certificates openssl
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q curl ca-certificates openssl
else
  fail "No supported package manager found (apt, dnf or yum required)."
fi

# --- 2. Docker ----------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine (get.docker.com)..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  log "Docker already installed: $(docker --version)"
fi
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 plugin missing; install docker-compose-plugin."

# --- 3. Environment file -------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  log "Generating $ENV_FILE with random secrets..."
  cat > "$ENV_FILE" <<EOF
DJANGO_SECRET_KEY=$(openssl rand -hex 32)
DJANGO_SETTINGS_MODULE=contentcuration.not_production_settings
STUDIO_HTTP_PORT=${STUDIO_HTTP_PORT}
POSTGRES_USER=learningequality
POSTGRES_DB=kolibri-studio
POSTGRES_PASSWORD=$(openssl rand -hex 16)
MINIO_ROOT_USER=studio
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
MINIO_BUCKET=content
CELERY_TIMEZONE=UTC
EOF
  # Single web worker on low-RAM servers
  if (( $(awk '/MemTotal/ {print $2}' /proc/meminfo) < 2500000 )); then
    echo "GUNICORN_WORKERS=1" >> "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
else
  log "Reusing existing $ENV_FILE"
fi

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

# --- 4. Build and start --------------------------------------------------------
if compose pull studio-app studio-nginx; then
  log "Using prebuilt images from GHCR."
else
  log "Prebuilt images unavailable; building locally (10-20 min, needs ~4 GB RAM+swap)..."
  compose build
fi

log "Starting services..."
compose up -d

# --- 5. Migrations + constants --------------------------------------------------
log "Waiting for PostgreSQL to be healthy..."
for i in $(seq 1 60); do
  state="$(docker inspect -f '{{.State.Health.Status}}' "$(compose ps -q postgres)" 2>/dev/null || echo starting)"
  [[ "$state" == "healthy" ]] && break
  sleep 2
done
[[ "$state" == "healthy" ]] || fail "PostgreSQL did not become healthy; check: docker compose -f $COMPOSE_FILE logs postgres"

log "Running database migrations and loading constants..."
compose exec -T studio-app make migrate
compose exec -T studio-app python contentcuration/manage.py createcachetable || true

if [[ "$WITH_DEMO_DATA" == "1" ]]; then
  log "Seeding demo data (admin a@a.com / password a)..."
  compose exec -T studio-app python contentcuration/manage.py setup
fi

# --- 6. Smoke test -----------------------------------------------------------------
log "Smoke test: waiting for the app to answer on port ${STUDIO_HTTP_PORT}..."
ok=""
for i in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:${STUDIO_HTTP_PORT}/" || true)"
  case "$code" in 200|301|302) ok=1; break;; esac
  sleep 3
done
if [[ -z "$ok" ]]; then
  log "SMOKE TEST FAILED (last status: ${code:-none}). Container states:"
  compose ps
  log "Last studio-nginx logs:"
  compose logs --tail 20 studio-nginx || true
  log "Last studio-app logs:"
  compose logs --tail 20 studio-app || true
  fail "The stack started but the app is not answering. See logs above."
fi
log "Smoke test passed (HTTP ${code})."

# --- 7. Report -------------------------------------------------------------------
IP="$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
log "=================================================================="
log "Kolibri Studio is up:  http://${IP}:${STUDIO_HTTP_PORT}/"
[[ "$WITH_DEMO_DATA" == "1" ]] && log "Admin login: a@a.com / a"
log "Secrets and settings:  $ENV_FILE"
log "Logs:    docker compose -f $COMPOSE_FILE --env-file $ENV_FILE logs -f"
log "Stop:    docker compose -f $COMPOSE_FILE --env-file $ENV_FILE down"
log "For HTTPS put a reverse proxy (caddy/nginx + certbot) in front of port ${STUDIO_HTTP_PORT}."
log "=================================================================="
