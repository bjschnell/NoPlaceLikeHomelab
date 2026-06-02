#!/usr/bin/env bash
# target-setup/install-rest-server.sh
#
# Idempotent installer: makes a host into a restic backup TARGET.
# Run as root on each of archy, heimdall, allfather (each acts as a
# target for OTHER hosts' backups).
#
# Defaults:
#   archy     -> REPO_ROOT=/Tres/restic-repos
#   heimdall  -> REPO_ROOT=/var/lib/restic-repos
#   allfather -> REPO_ROOT=/var/lib/restic-repos
#
# What this does:
#   1. Creates a system user `restic-backup` (no shell, no login)
#   2. Creates the repo root with proper ownership/permissions
#   3. Downloads + installs rest-server binary
#   4. Initializes one repo per (source-host, tier) the user wants to host
#      (a temporary non-append-only rest-server is brought up just for init)
#   5. Drops a systemd unit running rest-server in --append-only mode
#   6. Enables the systemd unit
#
# Before running: place restic password files at $PWD_DIR (default
# /tmp/restic-passwords/) named <source-host>.pwd.  The script reads them,
# initializes repos, then shreds them.

set -Eeuo pipefail
IFS=$'\n\t'

# Convert the space-separated TARGET_REPOS into a real array, robust to
# any whitespace (newlines from line continuations, multiple spaces, etc.)
# Done early, before anything else touches IFS.
parse_target_repos() {
  local saved_ifs="$IFS"
  IFS=$' \n\t'
  # shellcheck disable=SC2206  # intentional word-split into array
  TARGET_REPOS_ARR=( ${TARGET_REPOS:-} )
  IFS="$saved_ifs"
}

# --- config ---
: "${REPO_ROOT:=/var/lib/restic-repos}"
: "${REST_USER:=restic-backup}"
: "${REST_PORT:=8000}"
: "${REST_VERSION:=0.13.0}"
: "${PWD_DIR:=/tmp/restic-passwords}"
: "${TARGET_REPOS:=}"

if [[ -z "$TARGET_REPOS" ]]; then
  cat <<'EOF' >&2
ERROR: TARGET_REPOS not set.  Examples:

  # On archy (hosts everyone's backups; primary target):
  REPO_ROOT=/Tres/restic-repos \
  TARGET_REPOS="allfather-hot allfather-critical allfather-full \
                heimdall-hot heimdall-critical heimdall-full" \
    sudo ./install-rest-server.sh

  # On heimdall (hosts allfather's critical+full as peer):
  TARGET_REPOS="allfather-critical allfather-full" \
    sudo ./install-rest-server.sh

  # On allfather (hosts heimdall's critical+full as peer):
  TARGET_REPOS="heimdall-critical heimdall-full" \
    sudo ./install-rest-server.sh
EOF
  exit 2
fi

parse_target_repos
if [[ ${#TARGET_REPOS_ARR[@]} -eq 0 ]]; then
  echo "ERROR: TARGET_REPOS parsed to empty array; check the value passed in" >&2
  exit 2
fi
echo "==> Will configure ${#TARGET_REPOS_ARR[@]} repo(s): ${TARGET_REPOS_ARR[*]}"

# --- preflight ---
[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }
command -v curl      >/dev/null 2>&1 || { echo "curl required"      >&2; exit 1; }
command -v restic    >/dev/null 2>&1 || { echo "restic required"    >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "systemd required"   >&2; exit 1; }
[[ -d "$PWD_DIR" ]] || { echo "ERROR: password dir not found: $PWD_DIR" >&2; exit 1; }

echo "==> Creating user $REST_USER"
if ! id -u "$REST_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$REPO_ROOT" --shell /usr/sbin/nologin "$REST_USER"
fi

echo "==> Creating repo root: $REPO_ROOT"
mkdir -p "$REPO_ROOT"
chown "$REST_USER:$REST_USER" "$REPO_ROOT"
chmod 750 "$REPO_ROOT"

# --- install rest-server binary ---
REST_BIN=/usr/local/bin/rest-server
if [[ ! -x "$REST_BIN" ]] || ! "$REST_BIN" --version 2>/dev/null | grep -q "$REST_VERSION"; then
  echo "==> Installing rest-server $REST_VERSION"
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  rs_arch="amd64" ;;
    aarch64) rs_arch="arm64" ;;
    *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
  esac
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  url="https://github.com/restic/rest-server/releases/download/v${REST_VERSION}/rest-server_${REST_VERSION}_linux_${rs_arch}.tar.gz"
  curl -fsSL "$url" -o "$tmp/rs.tar.gz"
  tar -xzf "$tmp/rs.tar.gz" -C "$tmp"
  install -m 755 "$tmp"/rest-server_*/rest-server "$REST_BIN"
fi

# --- init repos via temporary non-append-only rest-server ---
echo "==> Bringing up rest-server temporarily (no append-only) for repo init"
"$REST_BIN" --path "$REPO_ROOT" --listen "127.0.0.1:${REST_PORT}" --no-auth &
REST_PID=$!
trap 'kill $REST_PID 2>/dev/null || true; rm -rf "${tmp:-}"' EXIT
sleep 2

for r in "${TARGET_REPOS_ARR[@]}"; do
  [[ -z "$r" ]] && continue
  source_host="${r%-*}"
  pwf="${PWD_DIR}/${source_host}.pwd"
  if [[ ! -f "$pwf" ]]; then
    echo "ERROR: password file missing for $source_host: $pwf" >&2
    exit 1
  fi
  url="rest:http://127.0.0.1:${REST_PORT}/${r}/"
  if RESTIC_REPOSITORY="$url" RESTIC_PASSWORD_FILE="$pwf" \
       restic cat config >/dev/null 2>&1; then
    echo "    repo $r already initialized"
  else
    echo "    initializing repo: $r"
    RESTIC_REPOSITORY="$url" RESTIC_PASSWORD_FILE="$pwf" restic init
    chown -R "$REST_USER:$REST_USER" "$REPO_ROOT/$r"
  fi
done

kill $REST_PID 2>/dev/null || true
wait $REST_PID 2>/dev/null || true

# --- install systemd unit (append-only) ---
echo "==> Installing systemd unit for rest-server (append-only)"
cat > /etc/systemd/system/rest-server.service <<EOF
[Unit]
Description=Restic REST Server (append-only)
Documentation=https://github.com/restic/rest-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${REST_USER}
Group=${REST_USER}
ExecStart=${REST_BIN} \\
  --path ${REPO_ROOT} \\
  --listen 0.0.0.0:${REST_PORT} \\
  --no-auth \\
  --append-only
Restart=on-failure
RestartSec=5s

# Hardening
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
ReadWritePaths=${REPO_ROOT}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now rest-server.service

# --- shred password files used during init ---
echo "==> SECURITY: shredding password files in $PWD_DIR"
shred -u "$PWD_DIR"/*.pwd 2>/dev/null || rm -f "$PWD_DIR"/*.pwd
rmdir "$PWD_DIR" 2>/dev/null || true

cat <<EOF

==> rest-server is up on port ${REST_PORT} in --append-only mode.
==> Repos initialized: $TARGET_REPOS

Next steps:
  1. Verify from a source host (a 405 on bare / is fine; check a repo path):
       curl -sf -o /dev/null -w "%{http_code}\n" \\
         http://$(hostname -f):${REST_PORT}/<one-of-the-repos>/config
       # expect: 200
  2. Restrict the firewall so only source hosts can reach port ${REST_PORT}.
     Example with iptables:
       iptables -A INPUT -p tcp --dport ${REST_PORT} -s <source-host-IP> -j ACCEPT
       iptables -A INPUT -p tcp --dport ${REST_PORT}                       -j REJECT
  3. Run a test backup from a source host.
  4. Schedule offline maintenance for prune (--append-only blocks online prune):
       systemctl stop rest-server
       sudo -u ${REST_USER} restic -r ${REPO_ROOT}/<repo>/ prune
       systemctl start rest-server
EOF
