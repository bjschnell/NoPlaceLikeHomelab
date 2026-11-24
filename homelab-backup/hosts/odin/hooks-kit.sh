# shellcheck shell=bash
pre_backup() {
  pacman -Qqe >"${DUMP_DIR}/pacman-explicit.txt" 2>/dev/null || true
  register_dump_cleanup "${DUMP_DIR}/pacman-explicit.txt"
}
