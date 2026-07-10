#!/usr/bin/env bash
# =============================================================================
# Kolibri Studio - unattended VPS quickstart. Run as root on a fresh or
# existing Ubuntu/Debian/RHEL-family server:
#
#   curl -fsSL https://raw.githubusercontent.com/kalandengit/kolibri-studio/main/deploy/quickstart-root.sh | bash
#
# Clones the repo to /opt/kolibri-studio and runs deploy/install-vps.sh
# (Docker + PostgreSQL + Redis + MinIO + Django + Celery + nginx) with demo
# data, published on port 8080 so it can coexist with anything on port 80.
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/kalandengit/kolibri-studio.git"
INSTALL_DIR="/opt/kolibri-studio"
PORT="${STUDIO_HTTP_PORT:-8080}"

log() { echo -e "\033[1;36m[studio-quickstart]\033[0m $*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

# --- base tools ---------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq git curl ca-certificates >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q git curl ca-certificates
else
  yum install -y -q git curl ca-certificates
fi

# --- memory check / swap -------------------------------------------------------
total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
swap_kb=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
log "RAM: $((total_mem_kb / 1024)) MB, swap: $((swap_kb / 1024)) MB"
if (( total_mem_kb < 3500000 && swap_kb < 1000000 )); then
  log "Low memory and no swap - creating 2 GB swapfile..."
  fallocate -l 2G /swapfile-studio || dd if=/dev/zero of=/swapfile-studio bs=1M count=2048
  chmod 600 /swapfile-studio
  mkswap /swapfile-studio && swapon /swapfile-studio
  grep -q swapfile-studio /etc/fstab || echo '/swapfile-studio none swap sw 0 0' >> /etc/fstab
fi
if (( total_mem_kb < 1800000 )); then
  log "WARNING: under 2 GB RAM. The image build may be very slow or fail;"
  log "         a 4 GB server is recommended for Kolibri Studio."
fi

# --- clone / update ------------------------------------------------------------
if [[ -d "$INSTALL_DIR/.git" ]]; then
  log "Updating existing checkout in $INSTALL_DIR..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  log "Cloning to $INSTALL_DIR..."
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# --- install --------------------------------------------------------------------
log "Handing over to install-vps.sh (builds take 10-20 min)..."
STUDIO_HTTP_PORT="$PORT" bash "$INSTALL_DIR/deploy/install-vps.sh" --with-demo-data --port "$PORT"
