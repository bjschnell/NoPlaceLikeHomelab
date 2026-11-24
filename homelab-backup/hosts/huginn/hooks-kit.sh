# shellcheck shell=bash
pre_backup() {
  local f
  f="${DUMP_DIR}/honcho.sql.gz";     pg_dumpall_in_container honcho-database-1 "$f"; register_dump_cleanup "$f"
  f="${DUMP_DIR}/hermes-state.db";   sqlite_online_backup /home/xdx/.hermes/state.db "$f"; register_dump_cleanup "$f"
}
