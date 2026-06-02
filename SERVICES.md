# Services Reference

A flat reference of every service in the homelab: what it does, which node it runs on, and the port it listens on internally.

> **Note on ports:** Config files are intentionally excluded from this repo (see the README), so the ports below are each service's **upstream default**. A few overlap across nodes (e.g. several default to `3000`); on the live network these are remapped or separated by host. Treat this as a reference for *what runs where*, not a literal port map of the running stack. `—` means the service has no listening port of its own (a CLI tool, agent, or daemon).

---

## Heimdall — Edge / Network / Monitoring (MSI GE60)

| Service | Port (internal) | Purpose |
|---|---|---|
| AdGuard Home | 53 (DNS), 80 (web) | Network-wide DNS ad/tracker blocking + local subdomain resolution |
| NGINX | 80, 443 | Reverse proxy — terminates external traffic, routes `*.portalgun.dev` |
| Authelia | 9091 | SSO / forward-auth layer in front of NGINX |
| Tailscale | — | WireGuard overlay daemon (uses UDP 41641 for direct connections) |
| Prometheus | 9090 | Metrics collection — scrapes all three nodes |
| Grafana | 3000 | Metrics dashboards |
| Uptime Kuma | 3001 | Service availability / uptime monitoring |
| Dockge | 5001 | Docker Compose stack management UI |
| cAdvisor | 8080 | Per-container resource metrics |
| node_exporter | 9100 | Host-level metrics |

## Allfather — Primary Application Host (Dell OptiPlex 7080)

| Service | Port (internal) | Purpose |
|---|---|---|
| Homepage | 3000 | Unified homelab dashboard |
| Home Assistant | 8123 | Home automation |
| Vaultwarden | 80 | Self-hosted Bitwarden-compatible password manager |
| Nextcloud | 80, 443 | File sync and cloud storage |
| PostFix | 25, 587 | Mail relay (SMTP / submission) |
| PingPong | — | Machine-to-machine messaging (personal project) |
| Portainer | 9000, 9443 | Container management |
| Restic | — | Automated backups (CLI, scheduled) |
| Dockge | 5001 | Docker Compose stack management UI |
| cAdvisor | 8080 | Per-container resource metrics |
| node_exporter | 9100 | Host-level metrics |

## Muninn — NAS / Media (Intel i7-3930K)

| Service | Port (internal) | Purpose |
|---|---|---|
| Jellyfin | 8096 (HTTP), 8920 (HTTPS) | Media server |
| Immich | 2283 | Photo management (Google Photos replacement) |
| Sonarr | 8989 | TV library management |
| Radarr | 7878 | Movie library management |
| Prowlarr | 9696 | Indexer aggregator for Sonarr/Radarr |
| FlareSolverr | 8191 | Cloudflare challenge solver for indexers |
| Samba | 139, 445 | LAN file sharing (SMB) |
| Nextcloud (media) | 80, 443 | Media library accessible via Nextcloud |
| Sunshine | 47990 (web UI) | GPU game-stream host (bare metal); stream ports 47984–48010 |
| cAdvisor | 8080 | Per-container resource metrics |
| node_exporter | 9100 | Host-level metrics |

---

## Access Patterns

- **External:** `Internet → Cloudflare → NGINX (Heimdall) → Authelia → service`. Nothing on Allfather or Muninn is reachable from outside without passing the authenticated proxy.
- **Remote (trusted devices):** `Tailscale → service` over the WireGuard mesh. No router port-forwarding.
- **LAN:** Direct host-to-host on the local network; AdGuard resolves internal subdomains locally.
- **Game streaming:** Moonlight clients (Steam Deck, etc.) connect to Sunshine on Muninn directly over the LAN / Tailscale.
