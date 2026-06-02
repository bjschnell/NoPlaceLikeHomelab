#!/usr/bin/env bash
# hosts/heimdall/backup-critical.sh
# Critical tier: nightly, pushes to archy + allfather.
set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
# shellcheck source=../../lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=../../lib/quiesce.sh
source "${REPO_DIR}/lib/quiesce.sh"
# shellcheck source=../../lib/restic-wrapper.sh
source "${REPO_DIR}/lib/restic-wrapper.sh"

LOG_FILE="/var/log/homelab-backup/heimdall-critical.log"
LOCK_FILE="/var/lock/homelab-backup-heimdall-critical.lock"
DUMP_DIR="/var/backups/homelab/critical"

export HOMELAB_HOST="heimdall"
export HOMELAB_TIER="critical"
export HOMELAB_SOURCES_FILE="${REPO_DIR}/hosts/heimdall/sources-critical.txt"
export HOMELAB_EXCLUDES_FILE="${REPO_DIR}/hosts/heimdall/excludes.txt"
export HOMELAB_PASSWORD_FILE="/root/.restic/heimdall.pwd"

export HOMELAB_TARGETS=(
  "archy=rest:http://archy.home:8000/heimdall-critical/"
  "allfather=rest:http://allfather.home:8000/heimdall-critical/"
)

export HOMELAB_KEEP_DAILY=7
export HOMELAB_KEEP_WEEKLY=4
export HOMELAB_KEEP_MONTHLY=3
export HOMELAB_KEEP_YEARLY=0
export HOMELAB_CHECK_PCT=2

mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

log "=== heimdall critical backup start ==="
_on_exit() {
  local _rc=$?
  run_cleanup_chain
  log "=== heimdall critical backup end (exit=$_rc) ==="
  exit $_rc
}
trap _on_exit EXIT

require_cmd restic
require_cmd sqlite3
require_cmd docker
require_file "$HOMELAB_PASSWORD_FILE"
require_file "$HOMELAB_SOURCES_FILE"
acquire_lock 9 "$LOCK_FILE"

ensure_dump_dir "$DUMP_DIR"

# --- Authelia online dump (host-visible bind mount) ---
AUTHELIA_DB="/opt/stacks/authelia/data/db.sqlite3"
AUTHELIA_DUMP="${DUMP_DIR}/authelia.sqlite3"
if [[ -f "$AUTHELIA_DB" ]]; then
  sqlite_online_backup "$AUTHELIA_DB" "$AUTHELIA_DUMP"
  register_dump_cleanup "$AUTHELIA_DUMP"
fi

# --- Uptime Kuma online dump (host-visible bind mount) ---
KUMA_DB="/opt/stacks/uptimekuma/data/kuma.db"
KUMA_DUMP="${DUMP_DIR}/uptime-kuma.sqlite3"
if [[ -f "$KUMA_DB" ]]; then
  sqlite_online_backup "$KUMA_DB" "$KUMA_DUMP"
  register_dump_cleanup "$KUMA_DUMP"
else
  log "WARN: Uptime Kuma DB not found at $KUMA_DB"
fi

# --- Grafana online dump (named volume; extract via docker cp first) ---
# Grafana stores its config DB at /var/lib/grafana/grafana.db inside the
# container.  The volume is "prometheus_grafana_data" (project prefix from
# the prometheus stack).  Use docker cp to land it on the host, then
# sqlite3 .backup against the copy for an atomic dump.
GRAFANA_CONTAINER="prometheus-grafana-1"
GRAFANA_TMP="${DUMP_DIR}/grafana.db.raw"
GRAFANA_DUMP="${DUMP_DIR}/grafana.db"
if docker ps --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER}$"; then
  if docker cp "${GRAFANA_CONTAINER}:/var/lib/grafana/grafana.db" "$GRAFANA_TMP" 2>/dev/null; then
    sqlite_online_backup "$GRAFANA_TMP" "$GRAFANA_DUMP"
    rm -f "$GRAFANA_TMP"
    register_dump_cleanup "$GRAFANA_DUMP"
  else
    log "WARN: docker cp grafana.db failed"
  fi
else
  log "WARN: container $GRAFANA_CONTAINER not running"
fi

do_backup_all_targets
