# shellcheck shell=bash
pre_backup() {
  local d="${DUMP_DIR}/vaultwarden.sqlite3"
  sqlite_online_backup /opt/stacks/vaultwarden/vw-data/db.sqlite3 "$d"
  register_dump_cleanup "$d"
}
