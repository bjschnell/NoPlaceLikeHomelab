# 🏠 Homelab

A three-node home infrastructure built around clear separation of responsibilities — network edge, application hosting, and media/storage are intentionally isolated so that any single node can go down without taking the rest of the stack with it.

> **Snapshot of current state.** This documents what's actually deployed today, not a target architecture — it's updated as the stack changes. Some services are mid-migration between nodes; where that matters it's noted.

> **Companion docs:** [`SERVICES.md`](./SERVICES.md) is a flat reference of every service and where it runs. [`decisions/`](./decisions) holds the Architecture Decision Records — the *why* behind the choices below, including the things deliberately *not* done. [`ROADMAP.md`](./ROADMAP.md) covers planned work and what gates it. [`RUNBOOK.md`](./RUNBOOK.md) holds operational recipes.

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
    │      ODIN      │        │   MUNINN (host: Archy) │
    │   (Dell 7080)  │        │      (i7-3930K)        │
    │                │        │                        │
    │ Home Assistant │        │ Jellyfin · Immich      │
    │ Vaultwarden    │        │ Sonarr · Radarr        │
    │ PingPong       │        │ Prowlarr · FlareSolverr│
    │ PostFix        │        │ Nextcloud              │
    │ Homepage       │        │ Samba (bare metal)     │
    │                │        │ Portainer Agent        │
    └────────────────┘        └───────────────────────┘
```

![Homelab architecture diagram](./assets/architecture.png)

<details>
<summary>Diagram as Mermaid source (renders natively on GitHub)</summary>

```mermaid
graph TB
    subgraph Clients["Clients"]
        direction LR
        Thor["Thor · CachyOS<br/>Sunshine host (bare metal)"]
        Mjolnir["Mjolnir · Win11"]
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

    subgraph Odin["ODIN · Dell OptiPlex 7080 (i5-10500T) · Primary App Host"]
        direction LR
        A_apps["Homepage · Vaultwarden · PingPong<br/>Home Assistant (VM)"]
        A_mgmt["PostFix · Restic · Dockge<br/>node_exporter · cAdvisor"]
    end

    subgraph Muninn["MUNINN (host: Archy) · Intel i7-3930K · NAS / Media"]
        direction LR
        M_media["Jellyfin · Immich<br/>Sonarr · Radarr · Prowlarr<br/>FlareSolverr"]
        M_store["Nextcloud · Samba (bare metal)<br/>Portainer Agent · Restic · Dockge<br/>node_exporter · cAdvisor"]
    end

    Authelia -- authenticated proxy --> Odin
    Authelia -- authenticated proxy --> Muninn
    Tailscale -. mesh .-> Heimdall
    Tailscale -. mesh .-> Odin
    Tailscale -. mesh .-> Muninn
    Obs -. scrapes metrics .-> Odin
    Obs -. scrapes metrics .-> Muninn
    SteamDeck -. Moonlight stream .-> Thor

    classDef edge fill:#1e3a5f,stroke:#4a90d9,color:#fff;
    classDef app fill:#1f4d2e,stroke:#52a373,color:#fff;
    classDef nas fill:#5c2a2a,stroke:#c97070,color:#fff;
    classDef net fill:#33373d,stroke:#8a929c,color:#fff;
    class Heimdall edge;
    class Odin app;
    class Muninn nas;
    class Cloudflare,Tailscale,Internet,Clients net;
```
</details>

The key architectural principle: **Heimdall is the only node that faces the network.** All service traffic routes through it. Odin and Muninn are unreachable directly from outside — Tailscale or the reverse proxy are the only entry points.

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

**Design decision:** Monitoring lives on the edge node intentionally. If Odin or Muninn goes down, that's exactly when you need visibility. Monitoring on the failing node is useless. → [ADR 001](./decisions/001-monitoring-on-edge-node.md)

---

### Odin — Primary Application Host
*Dell OptiPlex 7080 (i5-10500T, 32GB) · Primary compute node*

Runs the day-to-day application services. This node is the intended landing spot for CPU-bound services as they migrate off the older Muninn hardware over time.

| Service | Role |
|---|---|
| Homepage | Unified homelab dashboard |
| Home Assistant | Home automation (runs in a VirtualBox VM) |
| Vaultwarden | Self-hosted Bitwarden password manager |
| PingPong | Machine-to-machine messaging (personal project) |
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

**No direct port forwarding** to Odin or Muninn. Both nodes are only reachable via the reverse proxy (authenticated) or Tailscale. → [ADR 004](./decisions/004-no-direct-port-forwarding.md)

**Physical layer:** an eero 6 Pro mesh handles routing and Wi-Fi, with unmanaged 1GbE switches fanning out to the wired nodes. It supports no VLANs and no prosumer controls, which the architecture routes around rather than relies on — the router does no security work here. It also caps the 3 Gbps ISP link at 1 Gbps. Staying on it is a deliberate call with named revisit triggers. → [ADR 007](./decisions/007-no-network-upgrade.md)

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

**Backups everywhere, working toward 3-2-1.** Restic runs on all three nodes with per-host encryption keys and append-only targets — a compromised source host can write new snapshots but cannot destroy history. Tiered cadence (hot every 6h, critical nightly, full weekly) matches RPO to data criticality, and critical+full replicate to a peer host as well as Muninn. Offsite is the remaining gap and is tracked in the [roadmap](./ROADMAP.md#backup--offsite-copy). → [ADR 006](./decisions/006-distributed-restic-append-only.md) · scripts and runbooks in [`homelab-backup/`](./homelab-backup/)

---

## Repository Layout

```
.
├── README.md          # This file — architecture overview
├── SERVICES.md        # Flat reference: every service, its port, and its node
├── ROADMAP.md         # Planned work, and the conditions that promote each item
├── RUNBOOK.md         # Operational recipes: node maintenance, Docker, NGINX, Sunshine
├── LICENSE            # MIT
├── assets/
│   └── architecture.png   # Rendered architecture diagram (Mermaid source inline in this README)
├── decisions/         # Architecture Decision Records (ADRs)
│   ├── README.md          # ADR index + "decided against" log
│   ├── 001-monitoring-on-edge-node.md
│   ├── 002-authelia-at-boundary.md
│   ├── 003-moonlight-bare-metal.md
│   ├── 004-no-direct-port-forwarding.md
│   ├── 005-docker-compose-over-kubernetes.md
│   ├── 006-distributed-restic-append-only.md
│   └── 007-no-network-upgrade.md
├── homelab-backup/    # Distributed restic backup: scripts, systemd units, restore + rotation runbooks
├── scripts/           # Standalone ops scripts: local LLM server, Samba users, emergency reboot
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
| Odin | Dell OptiPlex 7080 Micro | Intel Core i5-10500T (10th gen, Comet Lake, 35W) | 32GB DDR4 | Applications |
| Muninn (`archy`) | Custom — ASUS Sabertooth X79 | Intel i7-3930K | 32GB DDR3 | NAS / Media |

**Component notes.** Odin runs a 256GB SSD. That's modest for the primary application host and is the practical ceiling on how much can migrate onto it from Muninn — worth keeping in mind whenever a service is considered for the move.

Muninn carries a GTX 680 on the nouveau driver — legacy, and unnecessary since [ADR 003](./decisions/003-moonlight-bare-metal.md) put game streaming on Thor and Odin's Quick Sync covers transcoding. Its 1400W Platinum Corsair PSU (~2014) is heavily over-specced for the current load, which is the main reason to expect it to keep going. The CMOS battery is worth replacing if it hasn't been.

Heimdall is a 2013 laptop and its internal HDD dates from roughly the same period, though it sat unpowered for most of its life. It is not a machine to trust with data — which is consistent with its role, since the edge node holds configuration rather than anything irreplaceable. Its 8GB of RAM is the binding constraint on Prometheus retention; see [ADR 001](./decisions/001-monitoring-on-edge-node.md).

Hardware plans — UPS, storage, and the eventual Heimdall replacement — are in [`ROADMAP.md`](./ROADMAP.md).

---

## Devices

| Device | OS | Notes |
|---|---|---|
| Thor (desktop) | CachyOS / Hyprland | AMD Ryzen 9 9950X3D · RTX 5080 · 32GB DDR5-6000 CL30 · daily driver · **Sunshine game-stream host (bare metal)** |
| Mjolnir | Windows 11 | Windows dual-boot on the Thor hardware · gaming / Windows workloads |
| MacBook Pro (M5 Pro) | macOS | 24GB · 1TB SSD · portable development, iOS work, local AI |
| Steam Deck | SteamOS | Portable gaming · Moonlight client |
| iPhone | iOS | Mobile · Tailscale client · Moonlight client |
| Apple TV | tvOS | Wired via the eero mesh |

---

## Security — Avigilon ACC ES Analytics Appliance

Standalone video surveillance appliance, acquired free from work. Not Docker-hosted — runs its own embedded OS/firmware and manages recording, storage, and video analytics locally at the edge.

| Spec | Value |
|---|---|
| Model | Avigilon ACC ES Analytics Appliance (VMA-RPA-4Px) |
| Recording rate | 80 Mbps · Stream out 50 Mbps |
| Camera channels | 6 (4x PoE+ ports on-board, 60W total PoE output) |
| Uplink | 2x 10/100/1000 Mbps RJ-45 |
| Storage | 2TB or 4TB model (edge retention) |
| Power | 48-54V DC, dedicated power supply (not standard AC) |
| Dimensions | 239.5 x 169.4 x 44 mm (9.43" x 6.67" x 1.73") — fits 1U w/ official VMA-RPX-4PRMS1U rack tray |
| Weight | 3.39 kg / 7.47 lb (incl. PSU + bracket) |
| Operating temp | 0°C to 50°C, 10-90% RH non-condensing — **indoor/conditioned space only** |

**Cameras (behind the appliance):**

| Qty | Model | Type |
|---|---|---|
| 1 | Avigilon H3A | Bullet |
| 4 | Avigilon H4A | Dome |

Planned home: 1U slot in the DeskPi RackMate T1, alongside Odin and the eventual Heimdall replacement.
