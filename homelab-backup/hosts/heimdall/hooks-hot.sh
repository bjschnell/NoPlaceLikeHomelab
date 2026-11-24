# shellcheck shell=bash
pre_backup() {
  local d="${DUMP_DIR}/authelia.sqlite3"
  sqlite_online_backup /opt/stacks/authelia/data/db.sqlite3 "$d"
  register_dump_cleanup "$d"
}
