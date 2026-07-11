#!/usr/bin/env bash
# Create (or promote) an admin account on a VPS deployment.
#   sudo bash deploy/create-admin-vps.sh you@example.com yourpassword
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.deploy.yml"
ENV_FILE="$SCRIPT_DIR/.env"

EMAIL="${1:?usage: create-admin-vps.sh <email> <password>}"
PASSWORD="${2:?usage: create-admin-vps.sh <email> <password>}"

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T \
  -e ADMIN_EMAIL="$EMAIL" -e ADMIN_PASSWORD="$PASSWORD" studio-app \
  python contentcuration/manage.py shell -c "
import os
from contentcuration.models import User
email = os.environ['ADMIN_EMAIL']
user, created = User.objects.get_or_create(email=email, defaults={'first_name': 'Admin', 'last_name': 'User'})
user.set_password(os.environ['ADMIN_PASSWORD'])
user.is_admin = True
user.is_staff = True
user.is_active = True
user.save()
print(('created' if created else 'updated') + ': ' + email)
"
