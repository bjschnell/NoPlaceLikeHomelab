#!/usr/bin/env bash
# bin/backup.sh <hot|kit>
# Generic runner. Host is read from /etc/hostname (lowercased), so there are
# no hostname-keyed script paths to drift. Per-host data lives in hosts/<host>/:
#   sources-<tier>.txt   one path per line (missing paths are skipped with a warning)
#   excludes.txt         restic exclude patterns
#   hooks-<tier>.sh      optional; defines pre_backup() to create DB dumps
set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
TIER="${1:?usage: backup.sh <hot|kit>}"
HOST="$(tr 'A-Z' 'a-z' </etc/hostname)"
HOST_DIR="${REPO_DIR}/hosts/${HOST}"

# shellcheck source=../lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=../lib/quiesce.sh
source "${REPO_DIR}/lib/quiesce.sh"
# shellcheck source=../lib/restic-wrapper.sh
source "${REPO_DIR}/lib/restic-wrapper.sh"
# shellcheck source=../config/targets.conf
source "${REPO_DIR}/config/targets.conf"

LOG_DIR=/var/log/homelab-backup
mkdir -p "$LOG_DIR"
exec >>"${LOG_DIR}/${HOST}-${TIER}.log" 2>&1

require_dir "$HOST_DIR"
SRC_FILE="${HOST_DIR}/sources-${TIER}.txt"
require_file "$SRC_FILE"
# /root/.restic/env defines REST_PASS and optionally KUMA_PUSH_HOT / KUMA_PUSH_KIT
require_file /root/.restic/env
require_file /root/.restic/repo.pwd
# shellcheck disable=SC1091
source /root/.restic/env

DUMP_DIR="/var/backups/homelab/${TIER}"
export DUMP_DIR
log "=== ${HOST} ${TIER} start ==="
_on_exit() { local rc=$?; run_cleanup_chain || true; log "=== ${HOST} ${TIER} end (exit=${rc}) ==="; exit $rc; }
trap _on_exit EXIT

require_cmd restic
acquire_lock 9 "/var/lock/homelab-backup-${TIER}.lock"
ensure_dump_dir "$DUMP_DIR"

# Optional per-host dump hook
if [[ -f "${HOST_DIR}/hooks-${TIER}.sh" ]]; then
  # shellcheck disable=SC1090
  source "${HOST_DIR}/hooks-${TIER}.sh"
  pre_backup
fi

# Drop sources that do not exist so one stale path cannot fail the whole run
LIVE_SRC="$(mktemp)"; register_cleanup_file() { rm -f "$LIVE_SRC"; }; register_cleanup register_cleanup_file
while IFS= read -r p; do
  [[ -z "$p" || "$p" == \#* ]] && continue
  if [[ -e "$p" ]]; then echo "$p" >>"$LIVE_SRC"; else log "WARN: source missing, skipped: $p"; fi
done <"$SRC_FILE"

export HOMELAB_HOST="$HOST" HOMELAB_TIER="$TIER"
export HOMELAB_SOURCES_FILE="$LIVE_SRC"
export HOMELAB_EXCLUDES_FILE="${HOST_DIR}/excludes.txt"
export HOMELAB_PASSWORD_FILE=/root/.restic/repo.pwd
export RESTIC_REST_USERNAME="$HOST" RESTIC_REST_PASSWORD="$REST_PASS"
export HOMELAB_TARGETS=("muninn=rest:http://${MUNINN_ADDR}/${HOST}/${TIER}")
case "$TIER" in
  hot)  export HOMELAB_KEEP_DAILY=7  HOMELAB_KEEP_WEEKLY=0 HOMELAB_KEEP_MONTHLY=0 HOMELAB_KEEP_YEARLY=0 ;;
  kit)  export HOMELAB_KEEP_DAILY=7  HOMELAB_KEEP_WEEKLY=4 HOMELAB_KEEP_MONTHLY=3 HOMELAB_KEEP_YEARLY=0 ;;
  *) die "unknown tier: $TIER" ;;
esac
export HOMELAB_CHECK_PCT=2

# Heartbeat: Uptime Kuma push monitor. Missing heartbeat = alert, so silent
# failure (the old failure mode) cannot happen again.
push_var="KUMA_PUSH_${TIER^^}"
ping_kuma() {
  local url="${!push_var:-}"
  [[ -n "$url" ]] || { log "WARN: ${push_var} not set, no heartbeat"; return 0; }
  curl -fsS -m 15 "${url}?status=$1&msg=$2" >/dev/null || log "WARN: kuma ping failed"
}

if do_backup_all_targets; then ping_kuma up OK; else ping_kuma down FAILED; exit 1; fi
