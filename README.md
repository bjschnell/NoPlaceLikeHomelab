# 🏠 Homelab

A three-node home infrastructure built around clear separation of responsibilities — network edge, application hosting, and media/storage are intentionally isolated so that any single node can go down without taking the rest of the stack with it.

> **Snapshot of current state.** This documents what's actually deployed today, not a target architecture — it's updated as the stack changes. Some services are mid-migration between nodes; where that matters it's noted.

> **Companion docs:** [`SERVICES.md`](./SERVICES.md) is a flat reference of every service and where it runs. [`decisions/`](./decisions) holds the Architecture Decision Records — the *why* behind the choices below.

---

## Architecture Overview

```
Internet
    │
    ├── Cloudflare (DNS + DDoS)
    │
    └── Tailscale (WireGuard overlay — remote access)
            │
    ┌────────────────┐
    │    HEIMDALL    │  ← Network edge. Always on. If this goes down, nothing else matters.
    │     (GE60)     │     AdGuard · NGINX (bare metal) · Authelia · Prometheus · Grafana · Uptime Kuma · Portainer
    └───────┬────────┘
            │ authenticated reverse proxy
    ┌───────▼────────┐        ┌───────────────────────┐
    │    ALLFATHER   │        │   MUNINN (host: Archy) │
    │   (Dell 7080)  │        │      (i7-3930K)        │
    │                │        │                        │
    │ Home Assistant │        │ Jellyfin · Immich      │
    │ Vaultwarden    │        │ Sonarr · Radarr        │
    │ PingPong       │        │ Prowlarr · FlareSolverr│
    │ 2009Scape      │        │ Nextcloud              │
    │ PostFix        │        │ Samba (bare metal)     │
    │ Homepage       │        │ Portainer Agent        │
    └────────────────┘        └───────────────────────┘
```

![Homelab architecture diagram](./assets/architecture.png)

<details>
<summary>Diagram as Mermaid source (renders natively on GitHub)</summary>

```mermaid
graph TB
    subgraph Clients["Clients"]
        direction LR
        Ragnarok["Ragnarok · CachyOS<br/>Sunshine host (bare metal)"]
        Odin["Odin · Win11"]
        SteamDeck["Steam Deck"]
        iPhone["iPhone"]
    end

    Clients --> Internet(("Internet"))
    Internet --> Cloudflare["Cloudflare<br/>DNS · DDoS"]
    Internet --> Tailscale["Tailscale<br/>WireGuard overlay"]
    Cloudflare --> NGINX

    subgraph Heimdall["HEIMDALL · MSI GE60 · Edge / Network / Monitoring · 24/7"]
        direction TB
        NGINX["NGINX (bare metal)<br/>reverse proxy"] --> Authelia["Authelia · SSO"]
        AdGuard["AdGuard Home<br/>DNS filtering"]
        Obs["Monitoring<br/>Prometheus · Grafana · Uptime Kuma"]
        Mgmt_H["Portainer · Dockge · Restic<br/>node_exporter · cAdvisor"]
    end

    subgraph Allfather["ALLFATHER · Dell OptiPlex 7080 (i5-10500T) · Primary App Host"]
        direction LR
        A_apps["Homepage · Vaultwarden · PingPong<br/>2009Scape · Home Assistant (VM)"]
        A_mgmt["PostFix · Restic · Dockge<br/>node_exporter · cAdvisor"]
    end

    subgraph Muninn["MUNINN (host: Archy) · Intel i7-3930K · NAS / Media"]
        direction LR
        M_media["Jellyfin · Immich<br/>Sonarr · Radarr · Prowlarr<br/>FlareSolverr"]
        M_store["Nextcloud · Samba (bare metal)<br/>Portainer Agent · Restic · Dockge<br/>node_exporter · cAdvisor"]
    end

    Authelia -- authenticated proxy --> Allfather
    Authelia -- authenticated proxy --> Muninn
    Tailscale -. mesh .-> Heimdall
    Tailscale -. mesh .-> Allfather
    Tailscale -. mesh .-> Muninn
    Obs -. scrapes metrics .-> Allfather
    Obs -. scrapes metrics .-> Muninn
    SteamDeck -. Moonlight stream .-> Ragnarok

    classDef edge fill:#1e3a5f,stroke:#4a90d9,color:#fff;
    classDef app fill:#1f4d2e,stroke:#52a373,color:#fff;
    classDef nas fill:#5c2a2a,stroke:#c97070,color:#fff;
    classDef net fill:#33373d,stroke:#8a929c,color:#fff;
    class Heimdall edge;
    class Allfather app;
    class Muninn nas;
    class Cloudflare,Tailscale,Internet,Clients net;
```
</details>

The key architectural principle: **Heimdall is the only node that faces the network.** All service traffic routes through it. Allfather and Muninn are unreachable directly from outside — Tailscale or the reverse proxy are the only entry points.

---

## The Nodes

### Heimdall — Network Edge & Monitoring
*MSI GE60 (2OE) · Running 24/7*

The most critical node. Handles all DNS, routing, authentication, and observability. Deliberately kept lean — if a service doesn't belong to "traffic direction" or "observation," it doesn't run here.

| Service | Role |
|---|---|
| AdGuard Home | Network-wide DNS ad/tracker blocking |
| NGINX *(bare metal)* | Reverse proxy — routes `*.portalgun.dev` subdomains |
| Authelia | SSO authentication layer in front of NGINX |
| Tailscale | Overlay network for secure remote access |
| Prometheus | Metrics collection (scrapes all three nodes) |
| Grafana | Metrics dashboards |
| Uptime Kuma | Service availability monitoring |
| Portainer | Container management (server; agents on the other nodes) |
| Dockge | Docker Compose management UI |
| Restic | Automated backups |
| node_exporter + cAdvisor | Host and container metrics |

**Design decision:** Monitoring lives on the edge node intentionally. If Allfather or Muninn goes down, that's exactly when you need visibility. Monitoring on the failing node is useless. → [ADR 001](./decisions/001-monitoring-on-edge-node.md)

---

### Allfather — Primary Application Host
*Dell OptiPlex 7080 (i5-10500T, 32GB) · Primary compute node*

Runs the day-to-day application services. This node is the intended landing spot for CPU-bound services as they migrate off the older Muninn hardware over time.

| Service | Role |
|---|---|
| Homepage | Unified homelab dashboard |
| Home Assistant | Home automation (runs in a VirtualBox VM) |
| Vaultwarden | Self-hosted Bitwarden password manager |
| PingPong | Machine-to-machine messaging (personal project) |
| 2009Scape | Self-hosted 2009-era RuneScape game server |
| PostFix | Mail relay |
| Restic | Automated backups |
| Dockge | Docker Compose management UI |
| node_exporter + cAdvisor | Host and container metrics (scraped by Prometheus on Heimdall) |

---

### Muninn — NAS & Media
*Intel i7-3930K · Storage and media workloads · hostname: `archy`*

The oldest machine in the stack, repurposed as a dedicated storage and media node. The 3930K's age doesn't matter for this role — media serving and file storage are I/O-bound, not CPU-bound. (Documented as **Muninn** to fit the node naming scheme; the live hostname is still `archy`.)

| Service | Role |
|---|---|
| Jellyfin | Self-hosted media server |
| Immich | Self-hosted photo management (Google Photos replacement) |
| Sonarr / Radarr | TV and movie library management |
| Prowlarr | Indexer aggregator |
| FlareSolverr | Cloudflare bypass for indexers |
| Nextcloud | Self-hosted file sync and cloud storage |
| Samba *(bare metal)* | LAN file sharing (SMB) |
| Portainer Agent | Exposes this node to Portainer on Heimdall |
| Restic | Automated backups |
| Dockge | Docker Compose management UI |
| node_exporter + cAdvisor | Host and container metrics (scraped by Prometheus on Heimdall) |

---

## Network & Security

**External traffic:** Cloudflare sits in front of the public domain. All traffic terminates at NGINX (bare metal) on Heimdall. Authelia enforces authentication before any service is reachable. → [ADR 002](./decisions/002-authelia-at-boundary.md)

**Remote access:** Tailscale provides a zero-config WireGuard overlay network across all three nodes. Internal services are reachable over Tailscale without any port forwarding on the router.

**Internal traffic:** AdGuard handles DNS for the local network and resolves internal subdomains locally (no hairpin NAT). All inter-node communication stays on the LAN.

**No direct port forwarding** to Allfather or Muninn. Both nodes are only reachable via the reverse proxy (authenticated) or Tailscale. → [ADR 004](./decisions/004-no-direct-port-forwarding.md)

---

## Observability Stack

All three nodes run `node_exporter` (host metrics) and `cAdvisor` (container metrics). Prometheus on Heimdall scrapes them centrally, Grafana provides dashboards, and Uptime Kuma monitors availability of each service endpoint.

Running collection on the edge node means monitoring survives compute-node failures — the most useful property a monitoring stack can have.

---

## Design Principles

**Separation of responsibilities.** Network edge, application hosting, and storage/media are on separate hardware. A node going down affects only its own services.

**Monitoring on the edge.** Observability infrastructure lives on the most stable node, not with the services it monitors.

**Auth at the boundary.** Authelia handles SSO for all externally-accessible services at the reverse proxy layer. Services themselves don't need to implement authentication individually.

**Boring infrastructure.** Docker Compose over Kubernetes. Tailscale over self-managed WireGuard. The goal is services that run quietly, not an infrastructure playground. → [ADR 005](./decisions/005-docker-compose-over-kubernetes.md)

**Backups everywhere, working toward 3-2-1.** Restic runs on all three nodes with per-host encryption keys and append-only targets — a compromised source host can write new snapshots but cannot destroy history. Tiered cadence (hot every 6h, critical nightly, full weekly) matches RPO to data criticality, and critical+full replicate to a peer host as well as Archy. Offsite is the remaining gap. → [ADR 006](./decisions/006-distributed-restic-append-only.md) · scripts and runbooks in [`homelab-backup/`](./homelab-backup/)

---

## Repository Layout

```
.
├── README.md          # This file — architecture overview
├── SERVICES.md        # Flat reference: every service, its port, and its node
├── LICENSE            # MIT
├── assets/
│   ├── architecture.png   # Rendered architecture diagram
│   └── diagram.mmd        # Mermaid source for the diagram
├── decisions/         # Architecture Decision Records (ADRs)
│   ├── README.md
│   ├── 001-monitoring-on-edge-node.md
│   ├── 002-authelia-at-boundary.md
│   ├── 003-moonlight-bare-metal.md
│   ├── 004-no-direct-port-forwarding.md
│   ├── 005-docker-compose-over-kubernetes.md
│   └── 006-distributed-restic-append-only.md
├── homelab-backup/    # Distributed restic backup: scripts, systemd units, restore + rotation runbooks
└── sunshine/          # Sunshine bare-metal scripts (Hyprland virtual display for Moonlight streaming)
```

---

## What's Not Here

Config files are intentionally excluded — they contain environment-specific values and secrets even when scrubbed. This repo documents architecture and decisions, not deployment specifics.

---

## Hardware

| Node | Machine | CPU | RAM | Role |
|---|---|---|---|---|
| Heimdall | MSI GE60 (2OE) | Intel Core i7-4700MQ (4th gen, Haswell) | 8GB | Edge / Monitoring |
| Allfather | Dell OptiPlex 7080 | Intel Core i5-10500T (10th gen, Comet Lake, 35W) | 32GB | Applications |
| Muninn (`archy`) | Custom | Intel i7-3930K | 32GB | NAS / Media |

---

## Devices

| Device | OS | Notes |
|---|---|---|
| Ragnarok (desktop) | CachyOS / Hyprland | AMD Ryzen 9 9950X3D · RTX 5080 · daily driver · **Sunshine game-stream host (bare metal)** |
| Odin (laptop) | Windows 11 | Gaming / Windows workloads |
| Steam Deck | SteamOS | Portable gaming · Moonlight client |
| iPhone | iOS | Mobile · Tailscale client |
