#!/usr/bin/env bash
# hosts/heimdall/backup-full.sh
# Full tier: weekly, pushes to archy + allfather.
set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
# shellcheck source=../../lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=../../lib/quiesce.sh
source "${REPO_DIR}/lib/quiesce.sh"
# shellcheck source=../../lib/restic-wrapper.sh
source "${REPO_DIR}/lib/restic-wrapper.sh"

LOG_FILE="/var/log/homelab-backup/heimdall-full.log"
LOCK_FILE="/var/lock/homelab-backup-heimdall-full.lock"
DUMP_DIR="/var/backups/homelab/full"

export HOMELAB_HOST="heimdall"
export HOMELAB_TIER="full"
export HOMELAB_SOURCES_FILE="${REPO_DIR}/hosts/heimdall/sources-full.txt"
export HOMELAB_EXCLUDES_FILE="${REPO_DIR}/hosts/heimdall/excludes.txt"
export HOMELAB_PASSWORD_FILE="/root/.restic/heimdall.pwd"

export HOMELAB_TARGETS=(
  "archy=rest:http://archy.home:8000/heimdall-full/"
  "allfather=rest:http://allfather.home:8000/heimdall-full/"
)

export HOMELAB_KEEP_DAILY=0
export HOMELAB_KEEP_WEEKLY=4
export HOMELAB_KEEP_MONTHLY=3
export HOMELAB_KEEP_YEARLY=1
export HOMELAB_CHECK_PCT=5

mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

log "=== heimdall full backup start ==="
_on_exit() {
  local _rc=$?
  run_cleanup_chain
  log "=== heimdall full backup end (exit=$_rc) ==="
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

# Same dumps as critical (self-contained snapshot at this tier).
AUTHELIA_DB="/opt/stacks/authelia/data/db.sqlite3"
AUTHELIA_DUMP="${DUMP_DIR}/authelia.sqlite3"
if [[ -f "$AUTHELIA_DB" ]]; then
  sqlite_online_backup "$AUTHELIA_DB" "$AUTHELIA_DUMP"
  register_dump_cleanup "$AUTHELIA_DUMP"
fi

KUMA_DB="/opt/stacks/uptimekuma/data/kuma.db"
KUMA_DUMP="${DUMP_DIR}/uptime-kuma.sqlite3"
if [[ -f "$KUMA_DB" ]]; then
  sqlite_online_backup "$KUMA_DB" "$KUMA_DUMP"
  register_dump_cleanup "$KUMA_DUMP"
fi

GRAFANA_CONTAINER="prometheus-grafana-1"
GRAFANA_TMP="${DUMP_DIR}/grafana.db.raw"
GRAFANA_DUMP="${DUMP_DIR}/grafana.db"
if docker ps --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER}$"; then
  if docker cp "${GRAFANA_CONTAINER}:/var/lib/grafana/grafana.db" "$GRAFANA_TMP" 2>/dev/null; then
    sqlite_online_backup "$GRAFANA_TMP" "$GRAFANA_DUMP"
    rm -f "$GRAFANA_TMP"
    register_dump_cleanup "$GRAFANA_DUMP"
  fi
fi

# NOTE: Prometheus TSDB is NOT backed up.  It lives in a Docker named
# volume (prometheus_prometheus_data), is bulky, regenerates from scrapes,
# and the value (rules + scrape configs + dashboards) is captured via
# /opt/stacks/prometheus/prometheus.yml and Grafana's DB above.

do_backup_all_targets
