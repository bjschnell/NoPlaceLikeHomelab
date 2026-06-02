# Homelab Backup Architecture

## Goals & non-goals

**Goals**
- Application-consistent, encrypted, deduplicated backups for the live homelab
- No host holds its own backups (every host's data lives on at least 2 *other* hosts where possible)
- Tiered cadence so RPO matches data criticality
- Ransomware-hardened: a compromised source host cannot destroy backups
- Reproducible from a Git-managed config repo

**Non-goals (this round)**
- Offsite / cloud copies (deferred)
- Backup of muninn (does not exist; archy is the legacy box and is target-only here)
- Backup of bulk media (Jellyfin library, Immich photos, *arr media on archy)
- Home Assistant backups (HA's supervisor writes its own .tar files via Samba to archy; that flow is independent of this pipeline)

## Hosts

| Host | Role | Notes |
|---|---|---|
| **archy**     | Legacy box, now: backup target + media on /Tres | i7-3930k, no ZFS pool, /Tres = 1.8 TB single drive |
| **allfather** | App host: Vaultwarden, Homepage, pingpong, Dockge UI, cadvisor, node-exporter | Source + peer target |
| **heimdall**  | Edge: nginx, Authelia, AdGuard, Prometheus stack, Grafana, Uptime Kuma, Portainer | Source + peer target |

## Topology

```
                ┌─────────────────────────┐
                │          archy          │  primary target
                │  /Tres/restic-repos/    │  (single-disk, will mirror later)
                └─────────────────────────┘
                        ▲
              ┌─────────┴──────────┐
              │                    │
     ┌────────┴──────┐    ┌────────┴────────┐
     │   allfather   │◄──►│    heimdall     │  peers back each other up
     │  (apps)       │    │  (edge)         │  for critical+full tiers
     └───────────────┘    └─────────────────┘
       /var/lib/restic-repos/  /var/lib/restic-repos/
```

| Source host | Hot (6h)   | Critical (nightly)   | Full (weekly)        |
|---|---|---|---|
| **allfather** | archy only | archy + heimdall | archy + heimdall |
| **heimdall**  | archy only | archy + allfather | archy + allfather |

## Tiers

### Hot — every 6 hours

Tiniest, most-critical secrets only. RPO = 6 hours.

- **allfather**: Vaultwarden SQLite DB (`/opt/stacks/vaultwarden/vw-data/db.sqlite3`), via `sqlite3 .backup`
- **heimdall**: Authelia SQLite DB (`/opt/stacks/authelia/data/db.sqlite3`), via `sqlite3 .backup`

Retention: 7 daily snapshots. Critical tier owns longer history.

Hot tier ships to archy ONLY — running every 6 hours on three targets is wasteful and the critical tier on the peer host already provides 24-hour worst-case fallback if archy is offline.

### Critical — nightly at 03:00

Everything you need to rebuild a working homelab in a hurry. Sub-100MB per host.

**allfather:**
- Vaultwarden DB (online dump)
- All `/opt/stacks/*` (compose files + bind-mounted config dirs for homepage, pingpong, etc.)
- `/opt/dockge/data` (Dockge stores stack definitions here, including AdGuard's compose)
- SSH keys (`/root/.ssh`, `/home/xdx/.ssh`)
- Restic config (`/root/.restic`)

**heimdall:**
- Authelia DB (online dump)
- Uptime Kuma DB (online dump from `/opt/stacks/uptimekuma/data/kuma.db`)
- Grafana DB (extracted via `docker cp` from `prometheus-grafana-1` container, then online dump)
- All `/opt/stacks/*` (authelia, portainer, prometheus, uptimekuma compose + configs)
- `/apps/adguardhome/{conf,work}` (AdGuard's bind-mount source on the host)
- `/etc/nginx`, `/etc/letsencrypt` (native edge proxy + certs)
- SSH keys, restic config

Retention: 7 daily, 4 weekly, 3 monthly.

### Full — weekly, Sunday 04:00

Superset of critical. Adds bulky things acceptable to lose a week of:

- Both hosts: full `/etc`, crontabs, systemd unit overrides

Retention: 4 weekly, 3 monthly, 1 yearly.

## What is NOT backed up, by design

- **Prometheus TSDB.** Lives in Docker named volume `prometheus_prometheus_data`, regenerates from scrapes, the value (rules + scrape configs) lives in `/opt/stacks/prometheus/prometheus.yml` which IS backed up.
- **AdGuard query log + stats.** Huge, ephemeral, low restore value. See `excludes.txt`.
- **Home Assistant.** Self-backed-up via supervisor; lands on archy via Samba.
- **Media on /Tres.** Mirrored elsewhere per user.
- **Immich photos / Nextcloud user data on /Uno.** Out of scope this round (will be added when archy gets a proper backup-target drive).

## Why this structure

### Per-host repos, not shared
Eight repos total (allfather × 3 tiers + heimdall × 3 tiers, replicated across targets). One blast radius per source host. Restic's cross-host dedup savings are negligible at homelab scale.

### Per-source-host passwords (2 total)
A compromise of allfather should not yield plaintext access to heimdall's repos. Single-global was rejected for this reason.

### rest-server `--append-only`
A compromised source host cannot run `restic forget --prune` and destroy backups. Pruning is an offline operation done on the target host directly.

### Application-consistent, not crash-consistent
SQLite DBs dumped via `sqlite3 .backup` (atomic) before restic snapshots them. Three SQLite DBs on heimdall are dumped this way; one on allfather (Vaultwarden).

### Two cadences = two systemd timers
Critical at 03:00, full at 04:00 Sunday. Full unit declares `Conflicts=critical.service` so they cannot run concurrently. Each script has its own lock file too.

## Single-disk risk on archy

Archy's `/Tres` is a single 1.8 TB drive. If it dies, the primary backup copy dies with it. Mitigation: heimdall and allfather hold each other's critical+full as peer copies, so for THOSE tiers the data survives. Hot tier (archy only) is fragile by design — if archy dies, you fall back to the previous night's critical snapshot from the peer.

This is acknowledged technical debt. Migrating to a proper dedicated backup drive (or a ZFS mirror) is planned. Restic repos are portable: `rsync` the entire repo dir to the new disk and update the URL.

## Failure modes & recovery

| Failure | Effect | Recovery |
|---|---|---|
| archy down | Hot tier fails entirely; critical/full still ship to peer | None; resumes when archy is back |
| heimdall down | allfather's critical/full to heimdall fails; archy copy succeeds | None; resumes |
| allfather down | heimdall's critical/full to allfather fails; archy copy succeeds | None; resumes |
| /Tres dies on archy | Lose primary copy + hot tier history; peer copies intact | Replace drive, re-init repos, resume backups |
| Single source host SSD dies | Live data lost on that host | Restore from peer or archy |
| Source host compromised | Attacker has decryption key for THIS host's repos only | Rotate password (see ROTATION.md), prune compromise-window snapshots after rotation |
| Forgotten password | All repos for that source unreadable | Recover from password manager |

## Outstanding work

1. **Offsite copy** — restic copy from archy → B2 weekly, eventually.
2. **Archy as a source host** — when /Tres → proper backup drive happens, also start backing up the *arr stack configs and HA self-backup tars (the ones already on archy via Samba).
3. **Failure notifications** — `OnFailure=` stub exists in systemd units; wire to ntfy / Healthchecks.io / Uptime Kuma push.
4. **Append-only prune cadence** — repos grow unbounded under append-only until offline prune. Schedule monthly per-target maintenance window.
5. **Quarterly restore drill** — see RESTORE.md. First drill within 2 weeks of deployment.
