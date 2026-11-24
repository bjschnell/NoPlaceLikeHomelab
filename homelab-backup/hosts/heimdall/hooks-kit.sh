# shellcheck shell=bash
pre_backup() {
  local f raw
  f="${DUMP_DIR}/authelia.sqlite3"; sqlite_online_backup /opt/stacks/authelia/data/db.sqlite3 "$f"; register_dump_cleanup "$f"
  f="${DUMP_DIR}/kuma.sqlite3";     sqlite_online_backup /opt/stacks/uptimekuma/data/kuma.db "$f";  register_dump_cleanup "$f"
  f="${DUMP_DIR}/dockge.sqlite3";   sqlite_online_backup /opt/stacks/dockge/data/dockge.db "$f";    register_dump_cleanup "$f"
  # Grafana lives in a named volume: copy out, then atomic dump
  raw="${DUMP_DIR}/grafana.raw"; f="${DUMP_DIR}/grafana.db"
  if docker cp prometheus-grafana-1:/var/lib/grafana/grafana.db "$raw" 2>/dev/null; then
    sqlite_online_backup "$raw" "$f"; rm -f "$raw"; register_dump_cleanup "$f"
  else log "WARN: grafana.db copy failed"; fi
}
