# shellcheck shell=bash
# lib/restic-wrapper.sh - the actual backup orchestration
#
# Caller exports:
#   HOMELAB_HOST                 - hostname tag (allfather, heimdall)
#   HOMELAB_TIER                 - hot | critical | full
#   HOMELAB_SOURCES_FILE         - path to a file with one source path per line
#   HOMELAB_EXCLUDES_FILE        - path to excludes file (optional, may be empty)
#   HOMELAB_PASSWORD_FILE        - path to restic password file
#   HOMELAB_TARGETS              - bash array of "name=URL" strings
#                                   e.g. ("archy=rest:http://...")
#   HOMELAB_KEEP_DAILY           - retention: daily snapshots
#   HOMELAB_KEEP_WEEKLY          -            weekly
#   HOMELAB_KEEP_MONTHLY         -            monthly
#   HOMELAB_KEEP_YEARLY          -            yearly
#   HOMELAB_CHECK_PCT            - read-data-subset percentage for check
#
# Then calls: do_backup_all_targets
#
# The wrapper backs up to each target sequentially.  Failure of one target
# does not abort the others -- we want best-effort multi-target writes so a
# single offline target doesn't kill the whole job.  Overall exit code is
# nonzero if ANY target failed.

do_backup_to_target() {
  local target_name="$1" repo_url="$2"
  local rc=0

  log "INFO: ===== target: $target_name ($repo_url) ====="

  export RESTIC_REPOSITORY="$repo_url"
  export RESTIC_PASSWORD_FILE="$HOMELAB_PASSWORD_FILE"

  # In append-only mode, we cannot run init from the source side.  The
  # target host is responsible for repo init (via target-setup scripts).
  # So we just verify the repo is reachable and decryptable.
  if ! restic_repo_ok "$repo_url" "$HOMELAB_PASSWORD_FILE"; then
    log "ERROR: repo unreachable or wrong password: $repo_url"
    return 1
  fi

  # --- backup ---
  local tag="${HOMELAB_TIER},${HOMELAB_HOST}"
  local exclude_args=()
  if [[ -n "${HOMELAB_EXCLUDES_FILE:-}" && -s "$HOMELAB_EXCLUDES_FILE" ]]; then
    exclude_args=(--exclude-file "$HOMELAB_EXCLUDES_FILE")
  fi

  log "INFO: restic backup -> $target_name"
  if ! prio restic backup \
        --files-from "$HOMELAB_SOURCES_FILE" \
        "${exclude_args[@]}" \
        --host "$HOMELAB_HOST" \
        --tag "$tag" \
        --exclude-caches \
        --verbose; then
    log "ERROR: backup failed for target $target_name"
    rc=1
    # Don't try to forget/check a repo we couldn't write to
    return $rc
  fi

  # --- forget + prune ---
  # NOTE: with rest-server --append-only, prune will fail by design.
  # That is expected and correct: pruning on the target is a separate,
  # privileged operation (see target-setup/maintenance.md).  We log and
  # continue.  We still call `forget` (without --prune) so that the
  # snapshot policy is recorded; the actual data deletion happens during
  # offline maintenance windows on the target host.
  log "INFO: restic forget on $target_name (policy only, no prune)"
  if ! prio restic forget \
        --keep-daily   "${HOMELAB_KEEP_DAILY:-0}" \
        --keep-weekly  "${HOMELAB_KEEP_WEEKLY:-0}" \
        --keep-monthly "${HOMELAB_KEEP_MONTHLY:-0}" \
        --keep-yearly  "${HOMELAB_KEEP_YEARLY:-0}" \
        --tag "$tag" \
        --host "$HOMELAB_HOST"; then
    log "WARN: forget failed on $target_name (often expected under --append-only)"
  fi

  # --- integrity check ---
  log "INFO: restic check --read-data-subset=${HOMELAB_CHECK_PCT}% on $target_name"
  if ! prio restic check --read-data-subset="${HOMELAB_CHECK_PCT}%"; then
    log "WARN: integrity check found issues on $target_name"
    # Don't fail the run on a check warning -- we'd rather have *some*
    # backup recorded than none.  The WARN bubbles up via systemd OnFailure
    # if you wire it to log-level matching.
  fi

  log "INFO: ===== target $target_name done ====="
  return $rc
}

do_backup_all_targets() {
  local overall_rc=0
  local entry name url
  for entry in "${HOMELAB_TARGETS[@]}"; do
    name="${entry%%=*}"
    url="${entry#*=}"
    if ! do_backup_to_target "$name" "$url"; then
      overall_rc=1
      log "WARN: target $name failed; continuing to remaining targets"
    fi
  done
  return $overall_rc
}
