# qwen-common.sh — shared config + process helpers for the Qwen scripts.
#
# Sourced by both `startup-qwen` and `stop-qwen`. Not meant to be run directly.
# Keeps the server path, state locations, and stop logic in ONE place so the
# start and stop scripts can never disagree.

SERVER="${LLAMA_SERVER:-$HOME/repos/llama.cpp/build/bin/llama-server}"

STATE_DIR="$HOME/.local/state/startup-qwen"
PIDFILE="$STATE_DIR/qwen.pid"
LOGFILE="$STATE_DIR/qwen.log"
mkdir -p "$STATE_DIR"

is_running() {
  [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

# Wait up to ~10s for a pid to exit, SIGKILL if it won't.
_kill_pid() {
  local pid="$1"
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 50); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "  pid $pid didn't stop gracefully; sending SIGKILL."
    kill -9 "$pid" 2>/dev/null || true
  fi
}

do_stop() {
  if is_running; then
    local pid; pid="$(cat "$PIDFILE")"
    echo "Stopping llama-server (pid $pid) ..."
    _kill_pid "$pid"
    rm -f "$PIDFILE"
    echo "Stopped."
    return 0
  fi

  # No valid PID file. Fall back to matching the running binary directly, so a
  # stale/missing PID file doesn't leave an orphaned server we can't stop.
  rm -f "$PIDFILE"
  local pids
  pids="$(pgrep -f "$SERVER" || true)"
  if [[ -z "$pids" ]]; then
    echo "startup-qwen: not running."
    return 0
  fi
  echo "No PID file, but found running server(s): $pids"
  for pid in $pids; do _kill_pid "$pid"; done
  echo "Stopped."
}
