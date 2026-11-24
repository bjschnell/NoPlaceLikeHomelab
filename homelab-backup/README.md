# homelab-backup (v2: rebuild kits)

Goal: for every host, back up only what is needed to bring a replacement up
fast with its existing data. No media, no caches, no code that lives in git.

| Host | Hot (6h) | Kit (nightly 03:00) |
|---|---|---|
| thor (apps) | Vaultwarden DB | stacks, Vaultwarden/Kuma/Frugalicious dumps, systemd, ssh |
| heimdall (edge) | Authelia DB | stacks (nginx+certs), AdGuard conf, Authelia/Kuma/Dockge/Grafana dumps |
| huginn (Hermes) | Honcho pg dump | Hermes config/auth/skills/cron/state, Honcho dump, calendar-sync, iCloud |
| odin (dev desktop) | none | ssh/gpg keys, dotfiles, package list |

Target: muninn rest-server (append-only, per-host auth, `--private-repos`).
Repo URL: `rest:http://100.83.19.1:8000/<host>/<tier>`. Offsite is phase 2.

## Layout
```
bin/backup.sh <hot|kit>   generic runner, host = lowercased /etc/hostname
config/targets.conf       muninn address
hosts/<host>/             sources-<tier>.txt, excludes.txt, hooks-<tier>.sh (dumps)
systemd/                  homelab-backup-{hot,kit}.{service,timer}
lib/                      shell primitives
target-setup/MUNINN.md    rest-server hardening + user creation
```

## Per-host install (needs sudo; run as root)
```bash
git clone <repo> /opt/homelab-backup
install -d -m 700 /root/.restic
# repo.pwd: unique restic password per host, generated on your workstation,
# stored in Vaultwarden FIRST. env: REST_PASS=... plus optional
# KUMA_PUSH_HOT=https://.../api/push/<token>  KUMA_PUSH_KIT=...
install -m 600 repo.pwd /root/.restic/repo.pwd
install -m 600 env      /root/.restic/env
export RESTIC_REPOSITORY=rest:http://100.83.19.1:8000/$(cat /etc/hostname)/kit
export RESTIC_REST_USERNAME=$(cat /etc/hostname) RESTIC_REST_PASSWORD=...   # same as REST_PASS
export RESTIC_PASSWORD_FILE=/root/.restic/repo.pwd
restic init            # repeat with .../hot for hosts that have a hot tier
cp systemd/*.service systemd/*.timer /etc/systemd/system/ && systemctl daemon-reload
systemctl enable --now homelab-backup-kit.timer homelab-backup-hot.timer
systemctl start homelab-backup-kit.service   # smoke test, then check the log
```
Logs: `/var/log/homelab-backup/<host>-<tier>.log`. Freshness: the Kuma push
monitors alert when a heartbeat is missed (set interval hot=7h, kit=26h).

## Archive
The pre-migration repos (`allfather-*`, `heimdall-*`, `odin-*`) on muninn under
`/Tres/restic-repos` are the old fleet and stay read-only. They are not served
under `--private-repos`; read them locally with `restic -r /Tres/restic-repos/<name>`.
Names there refer to retired boxes. Do not prune until verified restorable.
