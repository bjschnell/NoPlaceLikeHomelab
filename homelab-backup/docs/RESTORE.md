# Restore Runbook

> **Snapshots taken before the `allfather` → `odin` rename carry the old host tag.** The host tag is
> written into each snapshot at backup time, so `restic snapshots --host odin` will not list anything
> from before the rename. Use `restic snapshots` with no `--host` filter when hunting for an older
> snapshot, or pass `--host allfather` explicitly. This applies only to snapshot metadata — the repo
> paths and password files below are the current ones.

## Pre-restore checklist

1. Find the password. Per-source-host:
   - odin repos → password manager entry "homelab-restic-odin"
   - heimdall repos → password manager entry "homelab-restic-heimdall"
2. Pick a target. Always prefer archy (most recent, highest retention).
3. Confirm archy + rest-server is reachable:
   ```bash
   curl -sf http://archy.home:8000/ && echo OK
   ```

## Restoring a single file

```bash
export RESTIC_REPOSITORY="rest:http://archy.home:8000/odin-critical/"
export RESTIC_PASSWORD_FILE=/path/to/odin.pwd

# find the snapshot you want
restic snapshots --host odin --tag critical

# inspect contents
restic ls latest /opt/stacks/vaultwarden/

# restore one path
restic restore latest --target /tmp/restore-$$ \
  --include /opt/stacks/vaultwarden/docker-compose.yml
```

## Restoring Vaultwarden after total loss

1. Restore the SQLite DB from the most recent **hot** snapshot:
   ```bash
   export RESTIC_REPOSITORY="rest:http://archy.home:8000/odin-hot/"
   export RESTIC_PASSWORD_FILE=/root/.restic/odin.pwd
   restic restore latest --target /tmp/vw-restore \
     --include /var/backups/homelab/hot/vaultwarden.sqlite3
   ```
2. Restore the compose stack from the **critical** repo:
   ```bash
   export RESTIC_REPOSITORY="rest:http://archy.home:8000/odin-critical/"
   restic restore latest --target /tmp/vw-restore \
     --include /opt/stacks/vaultwarden
   ```
3. Stage on the new odin:
   ```bash
   mkdir -p /opt/stacks/vaultwarden/vw-data
   cp /tmp/vw-restore/var/backups/homelab/hot/vaultwarden.sqlite3 \
      /opt/stacks/vaultwarden/vw-data/db.sqlite3
   # restore container ownership (Vaultwarden runs as uid 0 by default in
   # the official image but check your compose for any user override)
   chown -R root:root /opt/stacks/vaultwarden/vw-data
   ```
4. Bring it up:
   ```bash
   cd /opt/stacks/vaultwarden && docker compose up -d
   ```
5. Verify login from a test client BEFORE assuming success.

## Restoring Authelia

Same shape, on heimdall:
- Hot DB at `/var/backups/homelab/hot/authelia.sqlite3` after restore
- Place at `/opt/stacks/authelia/data/db.sqlite3`, mode 640, owner xdx:xdx
- Configs at `/opt/stacks/authelia/config/`
- `cd /opt/stacks/authelia && docker compose up -d`

## Restoring nginx + letsencrypt on heimdall

```bash
export RESTIC_REPOSITORY="rest:http://archy.home:8000/heimdall-critical/"
restic restore latest --target / \
  --include /etc/nginx \
  --include /etc/letsencrypt
systemctl restart nginx
nginx -t   # confirm config validity
```

## Bare-metal restore of a host

1. Reinstall the OS (Arch on odin, whatever heimdall runs).
2. Install: `restic`, `docker`, `curl`, `sqlite3`.
3. Restore SSH keys + restic password from the peer host's repo:
   ```bash
   # Restoring odin. Use heimdall as the source -- archy may not
   # be reachable, or you may not have its credentials yet.
   export RESTIC_REPOSITORY="rest:http://heimdall.home:8000/odin-critical/"
   # You'll need the password file out-of-band (password manager).
   restic restore latest --target / \
     --include /root/.ssh \
     --include /root/.restic
   ```
4. Once SSH + restic password are local, restore the rest from archy (faster):
   ```bash
   export RESTIC_REPOSITORY="rest:http://archy.home:8000/odin-full/"
   restic restore latest --target /
   ```
5. `systemctl daemon-reload && systemctl enable --now <units>` for services.
6. `cd /opt/stacks/<service> && docker compose up -d` for each Dockge stack.
7. `systemctl restart nginx` (if heimdall).

## Restore drill protocol (quarterly)

Untested backups are not backups. Run this every 3 months:

1. Pick one service at random.
2. On a throwaway VM, restore that service from the most recent critical snapshot.
3. Bring it up. Verify the application data loads. Verify a known query returns expected output.
4. Tear down the VM.
5. Log the drill outcome in `docs/DRILL-LOG.md`.

If a drill fails, treat it as a Sev1.
