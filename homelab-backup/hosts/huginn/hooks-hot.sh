# shellcheck shell=bash
pre_backup() {
  local f="${DUMP_DIR}/honcho.sql.gz"
  pg_dumpall_in_container honcho-database-1 "$f"; register_dump_cleanup "$f"
}
