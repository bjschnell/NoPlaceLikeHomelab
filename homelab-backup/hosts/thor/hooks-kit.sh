# shellcheck shell=bash
pre_backup() {
  local f
  f="${DUMP_DIR}/vaultwarden.sqlite3"; sqlite_online_backup /opt/stacks/vaultwarden/vw-data/db.sqlite3 "$f"; register_dump_cleanup "$f"
  f="${DUMP_DIR}/kuma.sqlite3";        sqlite_online_backup /opt/stacks/uptimekuma/data/kuma.db "$f";       register_dump_cleanup "$f"
  f="${DUMP_DIR}/frugalicious.sql.gz"; pg_dumpall_in_container frugalicious-db-1 "$f";                      register_dump_cleanup "$f"
  docker ps --format '{{.Names}}\t{{.Image}}' >"${DUMP_DIR}/docker-ps.txt"; register_dump_cleanup "${DUMP_DIR}/docker-ps.txt"
}
