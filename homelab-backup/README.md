# homelab-backup

Distributed restic-based backup. Replaces the old monolithic bash script that ran on archy.

> **Names in this directory are live hostnames.** `odin`, `heimdall` and `archy` are what the
> machines actually answer to: systemd resolves `%H` to the real hostname to pick `hosts/<host>/`,
> the restic repo paths and `.pwd` filenames are built from it, and the `.home` DNS records match.
> Two of the three match the documented node names; the exception is **`archy`, which the
> architecture docs call Muninn** — see the [README](../README.md). Renaming anything here means
> renaming the host, its DNS record, its `.pwd` file, and the repo directories on every target in
> the same pass, or the next run writes to a fresh empty repo.

## TL;DR

Two source hosts (`odin`, `heimdall`) push restic snapshots to archy (primary) plus to each other (peer). Three tiers, three cadences. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Layout

```
lib/                  shared shell primitives
hosts/<host>/         host-specific scripts + sources/excludes
systemd/              service + timer units (host-agnostic via %H)
target-setup/         one-time setup to make a host into a backup target
docs/                 architecture, restore, rotation runbooks
```

## Initial deployment

### 1. On every host (odin, heimdall, archy), clone to `/opt/homelab-backup`

```bash
sudo git clone <repo-url> /opt/homelab-backup
sudo chmod +x /opt/homelab-backup/hosts/*/*.sh
sudo chmod +x /opt/homelab-backup/target-setup/*.sh
```

### 2. Generate the two passwords on a trusted workstation

Do this once, on a workstation NOT in the homelab (e.g. mjolnir). Save the values to your password manager immediately — these are the encryption keys for every backup.

```bash
openssl rand -base64 48 > /tmp/odin.pwd
openssl rand -base64 48 > /tmp/heimdall.pwd
chmod 600 /tmp/odin.pwd /tmp/heimdall.pwd
# Save both to your password manager NOW, before they leave this machine.
```

### 3. Understand where each password file needs to land

Two distinct locations exist on the homelab hosts. Each plays a different role:

- **`/root/.restic/<host>.pwd`** — permanent runtime credential. Source hosts read this every time they run a backup. Owned by root, mode 600.
- **`/tmp/restic-passwords/<host>.pwd`** — temporary bootstrap fuel used only during step 5 (the rest-server installer). The installer reads it to `restic init` empty repos, then shreds the file. Not used after install.

The full distribution is:

| Host       | `/root/.restic/<host>.pwd`     | `/tmp/restic-passwords/<host>.pwd` (temporary)        |
|------------|--------------------------------|-------------------------------------------------------|
| odin       | `odin.pwd`                     | `heimdall.pwd`                                        |
| heimdall   | `heimdall.pwd`                 | `odin.pwd`                                            |
| archy      | (none — target-only)           | `odin.pwd` + `heimdall.pwd`                           |

### 4. Distribute password files from the trusted workstation

SCP the files into a writable staging location on each host (`/tmp/staging/`), then SSH in and place them at the correct final locations with `sudo`. SCP cannot write directly to `/root/` because the unprivileged login user does not own that directory.

The pattern, executed once per host, looks like this:

```bash
# from the trusted workstation (mjolnir)

# --- odin: needs odin.pwd in /root/.restic/, heimdall.pwd in /tmp/restic-passwords/
scp /tmp/odin.pwd /tmp/heimdall.pwd xdx@odin.home:/tmp/
ssh xdx@odin.home '
  sudo mkdir -p /root/.restic /tmp/restic-passwords &&
  sudo chmod 700 /root/.restic &&
  sudo install -m 600 -o root -g root /tmp/odin.pwd /root/.restic/odin.pwd &&
  sudo install -m 600 -o root -g root /tmp/heimdall.pwd  /tmp/restic-passwords/heimdall.pwd &&
  shred -u /tmp/odin.pwd /tmp/heimdall.pwd
'

# --- heimdall: needs heimdall.pwd in /root/.restic/, odin.pwd in /tmp/restic-passwords/
scp /tmp/odin.pwd /tmp/heimdall.pwd xdx@heimdall.home:/tmp/
ssh xdx@heimdall.home '
  sudo mkdir -p /root/.restic /tmp/restic-passwords &&
  sudo chmod 700 /root/.restic &&
  sudo install -m 600 -o root -g root /tmp/heimdall.pwd  /root/.restic/heimdall.pwd &&
  sudo install -m 600 -o root -g root /tmp/odin.pwd /tmp/restic-passwords/odin.pwd &&
  shred -u /tmp/odin.pwd /tmp/heimdall.pwd
'

# --- archy: target only, both passwords go to /tmp/restic-passwords/
scp /tmp/odin.pwd /tmp/heimdall.pwd xdx@archy.home:/tmp/
ssh xdx@archy.home '
  sudo mkdir -p /tmp/restic-passwords &&
  sudo install -m 600 -o root -g root /tmp/odin.pwd /tmp/restic-passwords/odin.pwd &&
  sudo install -m 600 -o root -g root /tmp/heimdall.pwd  /tmp/restic-passwords/heimdall.pwd &&
  shred -u /tmp/odin.pwd /tmp/heimdall.pwd
'

# --- finally, shred the originals on the workstation
shred -u /tmp/odin.pwd /tmp/heimdall.pwd
```

You will get prompted for `xdx`'s sudo password on each host. The `shred -u` calls remove the SCP-staged copies from `/tmp/` after they've been placed, leaving only the canonical destinations.

After this step, every host has exactly the password files it needs, and no extras. Verify on each host:

```bash
sudo ls -la /root/.restic/ 2>/dev/null
sudo ls -la /tmp/restic-passwords/
```

### 5. Set up each target host (rest-server install + repo init)

The bootstrap password files are now in place from step 4. Run the installer on each target. The installer initializes repos, installs the systemd unit, and shreds `/tmp/restic-passwords/`.

**On archy** (primary target, hosts everything):
```bash
sudo REPO_ROOT=/Tres/restic-repos \
     TARGET_REPOS="odin-hot odin-critical odin-full \
                   heimdall-hot heimdall-critical heimdall-full" \
     /opt/homelab-backup/target-setup/install-rest-server.sh
```

**On heimdall** (peer target, hosts odin's critical+full):
```bash
sudo TARGET_REPOS="odin-critical odin-full" \
     /opt/homelab-backup/target-setup/install-rest-server.sh
```

**On odin** (peer target, hosts heimdall's critical+full):
```bash
sudo TARGET_REPOS="heimdall-critical heimdall-full" \
     /opt/homelab-backup/target-setup/install-rest-server.sh
```

After all three installers complete, `/tmp/restic-passwords/` is empty and removed. The only password files remaining on disk are at `/root/.restic/<host>.pwd` on odin and heimdall.

### 6. Verify rest-server is reachable

A bare `GET /` returns HTTP 405 (Method Not Allowed) — that's rest-server responding correctly, not an error. The right check hits an actual repo path:

```bash
# from any source host
curl -sf -o /dev/null -w "%{http_code}\n" http://archy.home:8000/odin-hot/config
# expect: 200
```

`200` = repo exists and is being served. `404` = repo not initialized (re-run the installer). Connection error = rest-server isn't running (`systemctl status rest-server` on the target).

Repeat for each repo you expect to find:

```bash
for r in odin-hot odin-critical odin-full \
         heimdall-hot heimdall-critical heimdall-full; do
  printf '%-30s -> ' "$r"
  curl -sf -o /dev/null -w "%{http_code}\n" "http://archy.home:8000/${r}/config"
done
```

All six should return `200`.

For the peer targets (heimdall hosts odin-{critical,full}; odin hosts heimdall-{critical,full}), check those endpoints similarly:

```bash
# from any source host
curl -sf -o /dev/null -w "%{http_code}\n" http://heimdall.home:8000/odin-critical/config
curl -sf -o /dev/null -w "%{http_code}\n" http://odin.home:8000/heimdall-critical/config
```

### 7. Install systemd units on each source host (odin, heimdall)

```bash
cd /opt/homelab-backup
for f in systemd/*.service systemd/*.timer; do
  sudo install -m 644 "$f" "/etc/systemd/system/$(basename "$f")"
done
sudo systemctl daemon-reload

sudo systemctl enable --now homelab-backup-hot.timer
sudo systemctl enable --now homelab-backup-critical.timer
sudo systemctl enable --now homelab-backup-full.timer
```

### 8. Smoke test

```bash
# Force a hot run immediately
sudo systemctl start homelab-backup-hot.service

# Watch the log
sudo tail -f /var/log/homelab-backup/<host>-hot.log

# Verify a snapshot exists on the target
sudo RESTIC_REPOSITORY="rest:http://archy.home:8000/<host>-hot/" \
     RESTIC_PASSWORD_FILE=/root/.restic/<host>.pwd \
     restic snapshots
```

## Operations

- **Status of timers:** `systemctl list-timers 'homelab-backup-*'`
- **Recent run logs:** `journalctl -u homelab-backup-critical.service -n 200`
- **Force a run:** `systemctl start homelab-backup-<tier>.service`
- **Disable temporarily:** `systemctl stop homelab-backup-<tier>.timer`

For prune scheduling: see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) → "Outstanding work".

## When something breaks

1. `/var/log/homelab-backup/<host>-<tier>.log` on the source host
2. `journalctl -u rest-server -n 200` on the target
3. From source: `restic -r <repo-url> snapshots`
4. If the repo is reachable but corrupt: `restic check` (read-only, safe)

For full restore procedures: [`docs/RESTORE.md`](docs/RESTORE.md).
