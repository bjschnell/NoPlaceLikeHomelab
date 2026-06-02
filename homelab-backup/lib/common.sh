# shellcheck shell=bash
# lib/common.sh - shared primitives for homelab-backup scripts
#
# Provides:
#   log <msg>                - timestamped log line
#   die <msg>                - log error and exit 1
#   require_file <path>      - die if file missing
#   require_dir <path>       - die if dir missing
#   require_cmd <name>       - die if command not on PATH
#   prio <cmd...>            - run cmd at low CPU + I/O priority
#   acquire_lock <fd> <path> - flock-based single-instance guard
#   restic_repo_ok <repo> <pwf>            - cat config; 0 if usable
#   restic_init_if_needed <repo> <pwf>     - init repo if absent
#   register_cleanup <fn>    - append a function to the cleanup chain
#   run_cleanup_chain        - run all registered cleanup fns in reverse order
#
# This file is sourced, never executed.  Callers must already have set:
#   set -Eeuo pipefail
#   IFS=$'\n\t'

# --- logging --------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

# --- preflight ------------------------------------------------------------

require_file() { [[ -f "$1" ]] || die "Required file missing: $1"; }
require_dir()  { [[ -d "$1" ]] || die "Required directory missing: $1"; }
require_cmd()  { command -v "$1" >/dev/null 2>&1 || die "Required command missing: $1"; }

# --- priority wrapper -----------------------------------------------------
# Run a command at low CPU and I/O priority so backup never starves
# foreground services.  Uses ionice if available, falls back to nice.

prio() {
  if command -v ionice >/dev/null 2>&1; then
    ionice -c2 -n7 nice -n 19 "$@"
  else
    nice -n 19 "$@"
  fi
}

# --- locking --------------------------------------------------------------
# Caller passes an FD number and a lock path.  Lock is held for the lifetime
# of the script (FD inherited by exec).  Non-blocking: returns 1 if held.

acquire_lock() {
  local fd="$1" path="$2"
  eval "exec ${fd}>\"\$path\""
  if ! flock -n "$fd"; then
    die "Another instance is already running (lock: $path)"
  fi
}

# --- restic helpers -------------------------------------------------------
# These read RESTIC_REPOSITORY and RESTIC_PASSWORD_FILE from the caller's
# environment unless overridden via the explicit arg form.

restic_repo_ok() {
  local repo="$1" pwf="$2"
  RESTIC_REPOSITORY="$repo" RESTIC_PASSWORD_FILE="$pwf" \
    restic cat config >/dev/null 2>&1
}

restic_init_if_needed() {
  local repo="$1" pwf="$2"
  if restic_repo_ok "$repo" "$pwf"; then
    return 0
  fi
  log "INFO: initializing repository: $repo"
  RESTIC_REPOSITORY="$repo" RESTIC_PASSWORD_FILE="$pwf" restic init >/dev/null
}

# --- cleanup chain --------------------------------------------------------
# Multiple modules need to register cleanup behavior (restart containers,
# remove DB dumps, etc).  A single trap calls run_cleanup_chain, which
# invokes registered functions in LIFO order so the last thing set up
# is the first thing torn down.

declare -a __CLEANUP_FNS=()

register_cleanup() {
  __CLEANUP_FNS+=("$1")
}

run_cleanup_chain() {
  local rc=$?
  local i
  for (( i=${#__CLEANUP_FNS[@]}-1; i>=0; i-- )); do
    local fn="${__CLEANUP_FNS[$i]}"
    log "INFO: cleanup -> $fn"
    "$fn" || log "WARN: cleanup function $fn returned non-zero"
  done
  return $rc
}
