#!/usr/bin/env bash
# Back up the database and content files of a VPS deployment.
#   sudo bash deploy/backup-vps.sh [output-dir]     (default /opt/kolibri-studio-backups)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.deploy.yml"
ENV_FILE="$SCRIPT_DIR/.env"
OUT_DIR="${1:-/opt/kolibri-studio-backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
log() { echo -e "\033[1;32m[studio-backup]\033[0m $*"; }

[[ -f "$ENV_FILE" ]] || { echo "No $ENV_FILE - run install-vps.sh first." >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }
mkdir -p "$OUT_DIR"

DB_FILE="$OUT_DIR/db-$STAMP.sql.gz"
log "Dumping PostgreSQL to $DB_FILE ..."
compose exec -T postgres pg_dump -U "${POSTGRES_USER:-learningequality}" \
  -d "${POSTGRES_DB:-kolibri-studio}" | gzip > "$DB_FILE"

CONTENT_FILE="$OUT_DIR/content-$STAMP.tar.gz"
log "Archiving MinIO content to $CONTENT_FILE ..."
docker run --rm --volumes-from "$(compose ps -q minio)" alpine \
  tar -czC /data . > "$CONTENT_FILE"

cp "$ENV_FILE" "$OUT_DIR/env-$STAMP"
chmod 600 "$OUT_DIR/env-$STAMP"

log "Done:"
ls -lh "$OUT_DIR" | tail -4
log "Restore with: sudo bash deploy/restore-vps.sh $DB_FILE $CONTENT_FILE"
