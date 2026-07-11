#!/usr/bin/env bash
# Restore a backup made by backup-vps.sh. DESTRUCTIVE: replaces current data.
#   sudo bash deploy/restore-vps.sh <db-XXX.sql.gz> [content-XXX.tar.gz] [--yes]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.deploy.yml"
ENV_FILE="$SCRIPT_DIR/.env"
log() { echo -e "\033[1;32m[studio-restore]\033[0m $*"; }

DB_BACKUP="${1:?usage: restore-vps.sh <db-XXX.sql.gz> [content-XXX.tar.gz] [--yes]}"
CONTENT_BACKUP="${2:-}"
CONFIRM="${3:-${2:-}}"

[[ -f "$ENV_FILE" ]] || { echo "No $ENV_FILE - run install-vps.sh first." >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

if [[ "$CONFIRM" != "--yes" ]]; then
  echo "This REPLACES the current database$( [[ -n "$CONTENT_BACKUP" && "$CONTENT_BACKUP" != "--yes" ]] && echo " and content files"). Type 'restore' to continue:"
  read -r answer
  [[ "$answer" == "restore" ]] || { echo "Aborted."; exit 1; }
fi

DB_USER="${POSTGRES_USER:-learningequality}"
DB_NAME="${POSTGRES_DB:-kolibri-studio}"

log "Stopping app services..."
compose stop studio-app celery-worker studio-nginx

log "Recreating database $DB_NAME ..."
compose exec -T postgres dropdb   -U "$DB_USER" --if-exists "$DB_NAME"
compose exec -T postgres createdb -U "$DB_USER" "$DB_NAME"
log "Importing $DB_BACKUP ..."
gunzip -c "$DB_BACKUP" | compose exec -T postgres psql -q -U "$DB_USER" -d "$DB_NAME"

if [[ -n "$CONTENT_BACKUP" && "$CONTENT_BACKUP" != "--yes" ]]; then
  log "Restoring content files from $CONTENT_BACKUP ..."
  docker run --rm -i --volumes-from "$(compose ps -q minio)" alpine \
    sh -c "rm -rf /data/* && tar -xzC /data" < "$CONTENT_BACKUP"
  compose restart minio
fi

log "Starting app services..."
compose up -d
log "Restore complete."
