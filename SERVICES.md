# Services Reference

A flat reference of every service in the homelab: what it does, which node it runs on, and the port it listens on internally.

> **Snapshot of current state**, updated as the stack changes.

> **Note on ports:** Config files are intentionally excluded from this repo (see the README), so the ports below are each service's **upstream default**. A few overlap across nodes (e.g. several default to `3000`/`9000`); on the live network these are remapped or separated by host. Treat this as a reference for *what runs where*, not a literal port map of the running stack. `—` means the service has no listening port of its own (a CLI tool, agent, or scheduled job).

---

## Heimdall — Edge / Network / Monitoring (MSI GE60)

| Service | Port (internal) | Purpose |
|---|---|---|
| AdGuard Home | 53 (DNS), 80 (web) | Network-wide DNS ad/tracker blocking + local subdomain resolution |
| NGINX *(bare metal)* | 80, 443 | Reverse proxy — terminates external traffic, routes `*.portalgun.dev` |
| Authelia | 9091 | SSO / forward-auth layer in front of NGINX |
| Tailscale | — | WireGuard overlay daemon (uses UDP 41641 for direct connections) |
| Prometheus | 9090 | Metrics collection — scrapes Allfather and Muninn |
| Uptime Kuma | 3001 | Service availability / uptime monitoring |
| Portainer | 9000, 9443 | Container management (server; agents run on the other nodes) |
| Dockge | 5001 | Docker Compose stack management UI |
| Restic | — | Automated backups (CLI, scheduled) → [ADR 006](./decisions/006-distributed-restic-append-only.md) · [`homelab-backup/`](./homelab-backup/) |

## Allfather — Primary Application Host (Dell OptiPlex 7080, i5-10500T)

| Service | Port (internal) | Purpose |
|---|---|---|
| Homepage | 3000 | Unified homelab dashboard |
| Home Assistant | 8123 | Home automation (runs in a VirtualBox VM) |
| Vaultwarden | 80 | Self-hosted Bitwarden-compatible password manager |
| PingPong | — | Machine-to-machine messaging (personal project) |
| 2009Scape | 43594 | Self-hosted 2009-era RuneScape game server |
| PostFix | 25, 587 | Mail relay (SMTP / submission) |
| Restic | — | Automated backups (CLI, scheduled) → [ADR 006](./decisions/006-distributed-restic-append-only.md) · [`homelab-backup/`](./homelab-backup/) |
| Dockge | 5001 | Docker Compose stack management UI |
| node_exporter | 9100 | Host-level metrics |
| cAdvisor | 8080 | Per-container resource metrics |

## Muninn — NAS / Media (Intel i7-3930K · hostname `archy`)

| Service | Port (internal) | Purpose |
|---|---|---|
| Jellyfin | 8096 (HTTP), 8920 (HTTPS) | Media server |
| Immich | 2283 | Photo management (Google Photos replacement) |
| Sonarr | 8989 | TV library management |
| Radarr | 7878 | Movie library management |
| Prowlarr | 9696 | Indexer aggregator for Sonarr/Radarr |
| FlareSolverr | 8191 | Cloudflare challenge solver for indexers |
| Nextcloud | 80, 443 | File sync and cloud storage |
| Portainer Agent | 9001 | Exposes this node to the Portainer server on Heimdall |
| Restic | — | Backup target (primary, append-only via rest-server) → [ADR 006](./decisions/006-distributed-restic-append-only.md) · [`homelab-backup/`](./homelab-backup/) |
| Dockge | 5001 | Docker Compose stack management UI |
| node_exporter | 9100 | Host-level metrics |
| cAdvisor | 8080 | Per-container resource metrics |

---

## Off-Node: Game Streaming

| Service | Host | Purpose |
|---|---|---|
| Sunshine *(bare metal)* | Ragnarok (gaming desktop) | GPU game-stream host; Moonlight clients (Steam Deck, etc.) connect over LAN / Tailscale → [ADR 003](./decisions/003-moonlight-bare-metal.md) · Hyprland virtual-display hooks in [`sunshine/`](./sunshine/) |

---

## Access Patterns

- **External:** `Internet → Cloudflare → NGINX (Heimdall) → Authelia → service`. Nothing on Allfather or Muninn is reachable from outside without passing the authenticated proxy.
- **Remote (trusted devices):** `Tailscale → service` over the WireGuard mesh. No router port-forwarding.
- **LAN:** Direct host-to-host on the local network; AdGuard resolves internal subdomains locally.
- **Game streaming:** Moonlight clients connect to Sunshine on Ragnarok directly over the LAN / Tailscale.
