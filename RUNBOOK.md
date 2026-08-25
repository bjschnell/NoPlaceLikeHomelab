# Runbook

Operational recipes for the homelab — the commands worth writing down because they're needed rarely enough to forget and urgently enough that looking them up hurts.

Scoped to the homelab: the three server nodes (all Arch), the Docker layer, the reverse proxy, and the Sunshine host. It is not a general Linux notebook.

> **Restore procedures are not here.** Backup restores, rotation and the append-only prune cadence live in [`homelab-backup/docs/RESTORE.md`](./homelab-backup/docs/RESTORE.md) and [`ROTATION.md`](./homelab-backup/docs/ROTATION.md), where they belong.

---

## Arch node maintenance

All three nodes run Arch, so these apply everywhere. Heimdall is the one that actually needs them — it's the oldest hardware with the smallest disk.

### Reclaim disk space

```bash
# What's eating the disk? -x stays on one filesystem instead of descending into mounts
sudo du -hx --max-depth=1 / 2>/dev/null | sort -hr | head -15
df -h /
```

Package cache and journals are almost always the answer:

```bash
# Package cache — keep the last 2 versions of each package
du -sh /var/cache/pacman/pkg/
sudo paccache -r -k 2

# Nuclear: drop everything except currently-installed versions
sudo paccache -ruk0

# Journals
journalctl --disk-usage
sudo journalctl --vacuum-time=2weeks
```

### Keyring failure blocking updates

When `pacman`/`paru` refuses to update with signature or keyring errors:

```bash
sudo pacman -Sc
sudo pacman -Syyu
```

The double `-yy` forces a refresh of the package databases rather than trusting the cached ones.

---

## File transfer between nodes

### rsync (preferred — resumable, skips unchanged files, shows progress)

```bash
rsync -avz --progress /source/folder/ user@remote:/destination/

# Non-standard SSH port
rsync -avz -e "ssh -p 2222" /source/ user@remote:/dest/

# Tailscale hostnames work directly
rsync -avz ~/stuff/ user@heimdall:/backup/
```

**The trailing slash decides what you get:** `/folder/` copies the *contents* of the folder; `/folder` copies the folder itself into the destination. Getting this backwards produces a nested directory or a flattened mess, and it is the single most common rsync mistake.

### Always use sudo for Docker and database files

```bash
sudo rsync -aHAXv /source/path/ /destination/path/
```

`-aHAX` preserves hard links, ACLs and extended attributes; `sudo` preserves ownership. Without it, ownership is rewritten to the invoking user and services that check it — MariaDB in particular — fail silently on the far side. The copy looks like it worked. It didn't.

---

## Docker

### Diagnostics

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker logs -f container_name
docker exec -it container_name /bin/sh
docker inspect container_name | grep -A 10 "Mounts"
```

### Reclaim space

```bash
# Stopped containers, unused networks, dangling images, build cache
docker system prune -a

# Unused volumes — this deletes data. Check what's unused first.
docker volume prune
```

### Export and import a named volume

```bash
# Export
docker run --rm -v volume_name:/data -v $(pwd):/backup alpine \
  tar czf /backup/volume-backup.tar.gz -C /data .

# Import
docker volume create volume_name
docker run --rm -v volume_name:/data -v $(pwd):/backup alpine \
  sh -c "tar xzf /backup/volume-backup.tar.gz -C /data"
```

### Migrate a stack between nodes

```bash
# Source: stop and package
cd /opt/stacks/service-name && docker compose down
tar czf service-migration.tar.gz service-name/

# Transfer
scp service-migration.tar.gz user@odin:/opt/stacks/

# Destination: extract and start
cd /opt/stacks && tar xzf service-migration.tar.gz
cd service-name && docker compose up -d
```

Dockge watches `/opt/stacks/`, so the stack appears in its UI on the destination without further action.

### Dockge password reset

Stack definitions are YAML files on disk and survive this — only Dockge's own user database is destroyed.

```bash
docker compose down
rm /path/to/dockge/data/dockge.db
docker compose up -d   # first-run setup screen returns
```

---

## NGINX reverse proxy (Heimdall)

### Adding a service

1. Create the config in `/etc/nginx/sites-available/service-name`
2. Symlink it: `sudo ln -s /etc/nginx/sites-available/service-name /etc/nginx/sites-enabled/`
3. Test before reloading: `sudo nginx -t`
4. Reload: `sudo systemctl reload nginx`

Step 3 is not optional. A reload with a broken config takes the reverse proxy down, and on Heimdall that means every service on every node becomes unreachable at once.

### Key paths

```
/etc/nginx/sites-available/                 service configs
/etc/nginx/authelia-location                auth endpoint snippet
/etc/nginx/snippets/tailscale-only.conf     Tailscale-IP restriction
/etc/letsencrypt/live/*/                    TLS certificates
```

New services get Authelia by default — see [ADR 002](./decisions/002-authelia-at-boundary.md). Anything that bypasses it needs a documented reason and should be IP-restricted via the Tailscale snippet instead.

---

## Sunshine host (Thor)

Script wiring and the virtual-display hooks are documented in [`sunshine/`](./sunshine/). These are the failure modes that come up during streamed sessions.

### Audio stops working mid-stream

```bash
pactl list short sinks
pactl get-default-sink
systemctl --user restart pipewire pipewire-pulse wireplumber
```

### A window vanished

Common after a Moonlight session ends — the window is still alive on the virtual display's workspace, which no longer exists.

```bash
hyprctl clients                      # every window and its workspace
hyprctl monitors                     # what Hyprland thinks is connected
hyprctl dispatch workspace N
hyprctl dispatch focuswindow ghostty
hyprctl dispatch movetoworkspace 1,class:com.mitchellh.ghostty
hyprctl dispatch togglespecialworkspace
hyprctl reload
```

### GTK apps break but everything else is fine

If GTK4 apps segfault with scale-factor errors after a streamed session, the virtual display's scale is usually cached:

```bash
rm -rf ~/.cache/gtk-4.0/

# Confirm the session environment is intact
echo $WAYLAND_DISPLAY
echo $DBUS_SESSION_BUS_ADDRESS

# If either is empty, the portal lost the session
systemctl --user restart xdg-desktop-portal
systemctl --user restart xdg-desktop-portal-hyprland
```

---

## Drives

### Securely wipe before disposal

```bash
lsblk    # identify the target. Verify twice — this is unrecoverable.

# Spinning disk: one pass plus a zero pass
shred -v -n 1 -z /dev/sdX

# NVMe: firmware crypto erase
nvme format /dev/nvmeX --ses=1

# SATA SSD
hdparm --security-erase /dev/sdX
```

Run from a live USB so the target isn't mounted, and confirm the device node against `lsblk` output rather than memory. Drive letters are not stable across boots.

---

## Miscellaneous

### Tailscale

```bash
tailscale status        # connected devices across the tailnet
tailscale ping heimdall # test connectivity to a specific node
```

### Fish shell globbing

Fish does not expand globs the way bash does, and `rm -rf /path/*` will not do what a bash-shaped memory expects. Recreate the directory instead:

```fish
rm -rf /path/ && mkdir -p /path/
```
