# shellcheck shell=bash
# lib/quiesce.sh - application-consistent backup primitives
#
# Provides:
#   docker_compose_stop <compose-file>
#   docker_compose_start <compose-file>
#   sqlite_online_backup <src.db> <dst.db>
#   mysqldump_to_file <container> <user> <pwfile> <db> <out.sql.gz>
#   ensure_dump_dir <path>           - create with 0700 perms, owned by root
#   register_dump_cleanup <path>     - removes file at script end
#
# All functions log via log() from common.sh.  Caller must source common.sh
# first.

docker_compose_stop() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    log "WARN: compose file missing, skipping stop: $f"
    return 0
  fi
  log "INFO: docker compose stop: $f"
  docker compose -f "$f" stop || log "WARN: stop failed for $f"
}

docker_compose_start() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    log "WARN: compose file missing, skipping start: $f"
    return 0
  fi
  log "INFO: docker compose start: $f"
  if ! docker compose -f "$f" start; then
    log "INFO: start failed, trying up -d for $f"
    docker compose -f "$f" up -d || log "ERROR: up -d failed for $f"
  fi
}

# --- SQLite online backup -------------------------------------------------
# Uses the .backup command which is safe against a live writer.  This is
# how Vaultwarden and Authelia should be backed up: zero downtime, fully
# consistent snapshot via SQLite's own atomic copy semantics.
#
# If the DB lives inside a container and is not visible on the host
# filesystem, use sqlite_online_backup_in_container instead.

sqlite_online_backup() {
  local src="$1" dst="$2"
  require_file "$src"
  require_cmd sqlite3
  local dst_dir
  dst_dir="$(dirname "$dst")"
  mkdir -p "$dst_dir"
  log "INFO: sqlite online backup: $src -> $dst"
  # .backup is atomic from SQLite's perspective; the destination is
  # written via the SQLite backup API and is consistent on success.
  sqlite3 "$src" ".backup '$dst'"
  chmod 600 "$dst"
}

# Run sqlite3 .backup *inside* a container that has the DB mounted.  Useful
# when the DB lives on a Docker volume not directly accessible on the host
# (or when host sqlite3 version differs from the app's expectations).
#
# Args: <container> <db-path-in-container> <out-on-host>
sqlite_online_backup_in_container() {
  local container="$1" db_in="$2" out_host="$3"
  local out_dir
  out_dir="$(dirname "$out_host")"
  mkdir -p "$out_dir"
  log "INFO: sqlite online backup (in $container): $db_in -> $out_host"
  # Use a tmp path inside the container, then copy out.
  local tmp_in
  tmp_in="/tmp/$(basename "$out_host")"
  docker exec "$container" sqlite3 "$db_in" ".backup '$tmp_in'" \
    || die "sqlite3 .backup failed inside $container"
  docker cp "${container}:${tmp_in}" "$out_host" \
    || die "docker cp failed for $container:$tmp_in"
  docker exec "$container" rm -f "$tmp_in" || true
  chmod 600 "$out_host"
}

# --- MariaDB / MySQL dump -------------------------------------------------
# For Nextcloud and any other MariaDB-backed app.  Currently unused (Nextcloud
# is out of scope for this backup round) but kept here for the future Phase 4
# when Nextcloud joins the backup set.

mysqldump_to_file() {
  local container="$1" user="$2" pwfile="$3" db="$4" out="$5"
  require_file "$pwfile"
  local out_dir
  out_dir="$(dirname "$out")"
  mkdir -p "$out_dir"
  log "INFO: mysqldump $db (in $container) -> $out"
  # --single-transaction gives a consistent snapshot for InnoDB tables
  # without locking; --quick streams row-by-row to avoid memory blowup.
  docker exec -i "$container" \
    mysqldump --single-transaction --quick --routines --triggers \
    -u"$user" -p"$(cat "$pwfile")" "$db" \
    | gzip -1 > "$out"
  chmod 600 "$out"
}

# --- dump dir helpers -----------------------------------------------------

ensure_dump_dir() {
  local d="$1"
  mkdir -p "$d"
  chmod 700 "$d"
}

# Register a file (or directory) for deletion when the script exits.
# Useful for SQL dumps: we write them, restic backs them up, then they
# vanish so we don't accumulate stale plaintext DB copies on disk.

register_dump_cleanup() {
  local target="$1"
  # Closure over $target via a generated function name
  local fn_name
  fn_name="__cleanup_dump_$(echo "$target" | tr -c 'a-zA-Z0-9' '_')"
  eval "${fn_name}() { [[ -e \"$target\" ]] && rm -rf \"$target\"; }"
  register_cleanup "$fn_name"
}
