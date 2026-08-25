#!/usr/bin/env bash
# hosts/allfather/backup-hot.sh
# Hot tier: Vaultwarden SQLite, every 6 hours, archy only.
set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
# shellcheck source=../../lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=../../lib/quiesce.sh
source "${REPO_DIR}/lib/quiesce.sh"
# shellcheck source=../../lib/restic-wrapper.sh
source "${REPO_DIR}/lib/restic-wrapper.sh"

LOG_FILE="/var/log/homelab-backup/allfather-hot.log"
LOCK_FILE="/var/lock/homelab-backup-allfather-hot.lock"
DUMP_DIR="/var/backups/homelab/hot"

export HOMELAB_HOST="allfather"
export HOMELAB_TIER="hot"
export HOMELAB_SOURCES_FILE="${REPO_DIR}/hosts/allfather/sources-hot.txt"
export HOMELAB_EXCLUDES_FILE="${REPO_DIR}/hosts/allfather/excludes.txt"
export HOMELAB_PASSWORD_FILE="/root/.restic/allfather.pwd"

export HOMELAB_TARGETS=(
  "archy=rest:http://archy.home:8000/allfather-hot/"
)

export HOMELAB_KEEP_DAILY=7
export HOMELAB_KEEP_WEEKLY=0
export HOMELAB_KEEP_MONTHLY=0
export HOMELAB_KEEP_YEARLY=0
export HOMELAB_CHECK_PCT=1

mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

log "=== allfather hot backup start ==="
_on_exit() {
  local _rc=$?
  run_cleanup_chain
  log "=== allfather hot backup end (exit=$_rc) ==="
  exit $_rc
}
trap _on_exit EXIT

require_cmd restic
require_cmd docker
require_cmd sqlite3
require_file "$HOMELAB_PASSWORD_FILE"
require_file "$HOMELAB_SOURCES_FILE"
acquire_lock 9 "$LOCK_FILE"

ensure_dump_dir "$DUMP_DIR"

# Vaultwarden DB: bind-mounted on the host at /opt/stacks/vaultwarden/vw-data/.
# Live writer present (WAL is active) -- sqlite3 .backup is safe regardless.
VW_DB="/opt/stacks/vaultwarden/vw-data/db.sqlite3"
VW_DUMP="${DUMP_DIR}/vaultwarden.sqlite3"

if [[ -f "$VW_DB" ]]; then
  sqlite_online_backup "$VW_DB" "$VW_DUMP"
  register_dump_cleanup "$VW_DUMP"
else
  log "WARN: Vaultwarden DB not found at $VW_DB"
fi

do_backup_all_targets
