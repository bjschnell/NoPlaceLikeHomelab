# Services Reference

A flat reference of every service in the homelab: what it does, which node it runs on, and the port it listens on internally.

> **Snapshot of current state**, updated as the stack changes.

> **Note on ports:** Huginn's ports are the live values; the rest are upstream defaults. Config files are intentionally excluded from this repo (see the README), so the ports below are each service's **upstream default**. A few overlap across nodes (e.g. several default to `3000`/`9000`); on the live network these are remapped or separated by host. Treat this as a reference for *what runs where*, not a literal port map of the running stack. `—` means the service has no listening port of its own (a CLI tool, agent, or scheduled job).

---

## Heimdall — Edge / Network / Monitoring (Dell OptiPlex 7060 Micro)

| Service | Port (internal) | Purpose |
|---|---|---|
| AdGuard Home | 53 (DNS), 80 (web) | Primary network DNS ad/tracker blocking + local subdomain resolution |
| NGINX *(bare metal)* | 80, 443 | Reverse proxy — terminates external traffic, routes `*.<domain>` (including Home Assistant) |
| Authelia (+ Valkey) | 9091 | SSO / forward-auth layer in front of NGINX |
| Tailscale | — | WireGuard overlay daemon; tailnet DNS points at this node |
| Prometheus | 9090 | Metrics collection — scrapes every node |
| Grafana | 3000 | Metrics dashboards |
| Uptime Kuma (v2) | 3001 | Service availability / uptime monitoring |
| Dockge | 5001 | Docker Compose stack management UI |
| node_exporter | 9100 | Host-level metrics |
| cAdvisor | 8080 | Per-container resource metrics |

## Huginn — The Brain (HP EliteDesk 800 G6 Mini, i5-10600)

| Service | Port (internal) | Purpose |
|---|---|---|
| Hermes (gateway + dashboard) | 9119 (dashboard) | AI agent runtime and admin UI; run as systemd user services, not containers |
| Alice PWA | 8788 | Daily chat front end for the agent (served by the Hermes gateway process, bound to the tailnet address) |
| Honcho (API, deriver, Postgres + pgvector, Redis) | 8001 (API) | Long-term agent memory |
| llama-embed | 8083 | Embedding model (Qwen3-Embedding-0.6B) for Honcho |
| Radicale | 5232 | CalDAV calendar server |
| gcal-sync | 8765 | Google Calendar → Radicale sync service |
| iCloud bridge | — | On-demand access to iCloud notes, contacts, reminders |
| Tailscale | — | WireGuard overlay daemon |
| node_exporter + cAdvisor | 9100, 8082 | Host and container metrics (bound to the tailnet address) |

## Odin — Legacy Application Host (Dell OptiPlex 7080, i5-10500T)

| Service | Port (internal) | Purpose |
|---|---|---|
| Vaultwarden | 8081 (published) | Self-hosted Bitwarden-compatible password manager |
| PingPong | 6969 | Machine-to-machine messaging (personal project) |
| Portal | 3000 | Home page for the lab (replaced the earlier Homepage dashboard) |
| Frugalicious | 3002 | Budgeting app (reached over the tailnet address) |
| Personal website + cloudflared | — | Public site via Cloudflare tunnel |
| Portainer (+ agent) | 9000, 9443 | Container management (server; agents run on the other nodes) |
| AdGuard Home (secondary) | 53 | Redundant DNS resolver |
| Uptime Kuma (v1) | 3001 | Second availability monitor, kept for redundancy |
| Dockge | 5001 | Docker Compose stack management UI |
| node_exporter | 9100 | Host-level metrics |
| cAdvisor | 8080 | Per-container resource metrics |
| Restic | — | Backup source — **currently not functioning**, being rebuilt → [`homelab-backup/`](./homelab-backup/) |

Odin no longer runs Postfix (the mail relay now runs bare metal on Muninn). Home Assistant (8123) runs in a separate VM on the LAN, not on Odin, and is exposed through the Heimdall proxy.

## Muninn — NAS / Media (Intel i7-3930K · hostname `archy`)

> Bare-metal services below were checked live on 2026-10-26. The container list was **not** re-verified this pass (no container access from the monitoring host) and, along with the failed backup/Nextcloud-cron units noted by systemd, needs a manual check on the box itself.

| Service | Port (internal) | Purpose |
|---|---|---|
| Jellyfin | 8096 (HTTP), 8920 (HTTPS) | Media server |
| Immich | 2283 | Photo management (Google Photos replacement) |
| Sonarr | 8989 | TV library management |
| Radarr | 7878 | Movie library management |
| Prowlarr | 9696 | Indexer aggregator for Sonarr/Radarr |
| FlareSolverr | 8191 | Cloudflare challenge solver for indexers |
| Nextcloud | 80, 443 | File sync and cloud storage |
| Samba *(bare metal)* | 139, 445 | LAN file sharing (SMB) |
| Portainer Agent | 9001 | Exposes this node to the Portainer server on Odin |
| Postfix *(bare metal)* | 25, 587 | Mail relay (SMTP / submission) |
| Dovecot *(bare metal)* | 143, 993 | IMAP/POP3 mail server |
| Valkey *(bare metal)* | 6379 | Key-value store |
| rest-server *(bare metal)* | 8000 | Restic REST server (append-only) backup target |
| Restic | — | Backup target (primary, append-only via rest-server) → [ADR 006](./decisions/006-distributed-restic-append-only.md) · [`homelab-backup/`](./homelab-backup/) |
| Dockge | 5001 | Docker Compose stack management UI |
| node_exporter | 9100 | Host-level metrics |
| cAdvisor | 8080 | Per-container resource metrics |

---

## Off-Node: Game Streaming

| Service | Host | Purpose |
|---|---|---|
| Sunshine *(bare metal)* | Thor (gaming desktop) | GPU game-stream host; Moonlight clients (Steam Deck, etc.) connect over LAN / Tailscale → [ADR 003](./decisions/003-moonlight-bare-metal.md) · Hyprland virtual-display hooks in [`sunshine/`](./sunshine/) |

## Off-Node: Security

| Service | Host | Purpose |
|---|---|---|
| Avigilon ACC ES Analytics Appliance | Standalone (own embedded OS) | Local edge video recording + analytics for 1x H3A bullet + 4x H4A dome cameras. Not Docker-hosted, no separate node in the compute cluster — plugs into LAN via its own dual gigabit uplink. See README.md § Security for full specs. |

---

## Access Patterns

- **External:** `Internet → Cloudflare → NGINX (Heimdall) → Authelia → service`. Nothing on Huginn, Odin or Muninn is reachable from outside without passing the authenticated proxy.
- **Remote (trusted devices):** `Tailscale → service` over the WireGuard mesh. No router port-forwarding.
- **LAN:** Direct host-to-host on the local network; AdGuard resolves internal subdomains locally.
- **Game streaming:** Moonlight clients connect to Sunshine on Thor directly over the LAN / Tailscale.
