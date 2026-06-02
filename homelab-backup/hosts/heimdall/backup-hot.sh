#!/usr/bin/env bash
# hosts/heimdall/backup-hot.sh
# Hot tier: Authelia SQLite, every 6 hours, archy only.
set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
# shellcheck source=../../lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=../../lib/quiesce.sh
source "${REPO_DIR}/lib/quiesce.sh"
# shellcheck source=../../lib/restic-wrapper.sh
source "${REPO_DIR}/lib/restic-wrapper.sh"

LOG_FILE="/var/log/homelab-backup/heimdall-hot.log"
LOCK_FILE="/var/lock/homelab-backup-heimdall-hot.lock"
DUMP_DIR="/var/backups/homelab/hot"

export HOMELAB_HOST="heimdall"
export HOMELAB_TIER="hot"
export HOMELAB_SOURCES_FILE="${REPO_DIR}/hosts/heimdall/sources-hot.txt"
export HOMELAB_EXCLUDES_FILE="${REPO_DIR}/hosts/heimdall/excludes.txt"
export HOMELAB_PASSWORD_FILE="/root/.restic/heimdall.pwd"

export HOMELAB_TARGETS=(
  "archy=rest:http://archy.home:8000/heimdall-hot/"
)

export HOMELAB_KEEP_DAILY=7
export HOMELAB_KEEP_WEEKLY=0
export HOMELAB_KEEP_MONTHLY=0
export HOMELAB_KEEP_YEARLY=0
export HOMELAB_CHECK_PCT=1

mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

log "=== heimdall hot backup start ==="
_on_exit() {
  local _rc=$?
  run_cleanup_chain
  log "=== heimdall hot backup end (exit=$_rc) ==="
  exit $_rc
}
trap _on_exit EXIT

require_cmd restic
require_cmd sqlite3
require_file "$HOMELAB_PASSWORD_FILE"
require_file "$HOMELAB_SOURCES_FILE"
acquire_lock 9 "$LOCK_FILE"

ensure_dump_dir "$DUMP_DIR"

# Authelia DB: bind-mounted on the host at /opt/stacks/authelia/data/.
# (Discovered: /opt/stacks/authelia/data/db.sqlite3, owned xdx:xdx, mode 640.)
AUTHELIA_DB="/opt/stacks/authelia/data/db.sqlite3"
AUTHELIA_DUMP="${DUMP_DIR}/authelia.sqlite3"

if [[ -f "$AUTHELIA_DB" ]]; then
  sqlite_online_backup "$AUTHELIA_DB" "$AUTHELIA_DUMP"
  register_dump_cleanup "$AUTHELIA_DUMP"
else
  log "WARN: Authelia DB not found at $AUTHELIA_DB"
fi

do_backup_all_targets
