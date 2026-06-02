#!/usr/bin/env bash
# hosts/allfather/backup-full.sh
# Full tier: weekly, pushes to archy + heimdall.
set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
# shellcheck source=../../lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=../../lib/quiesce.sh
source "${REPO_DIR}/lib/quiesce.sh"
# shellcheck source=../../lib/restic-wrapper.sh
source "${REPO_DIR}/lib/restic-wrapper.sh"

LOG_FILE="/var/log/homelab-backup/allfather-full.log"
LOCK_FILE="/var/lock/homelab-backup-allfather-full.lock"
DUMP_DIR="/var/backups/homelab/full"

export HOMELAB_HOST="allfather"
export HOMELAB_TIER="full"
export HOMELAB_SOURCES_FILE="${REPO_DIR}/hosts/allfather/sources-full.txt"
export HOMELAB_EXCLUDES_FILE="${REPO_DIR}/hosts/allfather/excludes.txt"
export HOMELAB_PASSWORD_FILE="/root/.restic/allfather.pwd"

export HOMELAB_TARGETS=(
  "archy=rest:http://archy.home:8000/allfather-full/"
  "heimdall=rest:http://heimdall.home:8000/allfather-full/"
)

export HOMELAB_KEEP_DAILY=0
export HOMELAB_KEEP_WEEKLY=4
export HOMELAB_KEEP_MONTHLY=3
export HOMELAB_KEEP_YEARLY=1
export HOMELAB_CHECK_PCT=5

mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

log "=== allfather full backup start ==="
_on_exit() {
  local _rc=$?
  run_cleanup_chain
  log "=== allfather full backup end (exit=$_rc) ==="
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

VW_DB="/opt/stacks/vaultwarden/vw-data/db.sqlite3"
VW_DUMP="${DUMP_DIR}/vaultwarden.sqlite3"
if [[ -f "$VW_DB" ]]; then
  sqlite_online_backup "$VW_DB" "$VW_DUMP"
  register_dump_cleanup "$VW_DUMP"
fi

do_backup_all_targets
