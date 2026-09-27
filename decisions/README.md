# Architecture Decision Records

The *why* behind the homelab's structure. Each ADR captures the context that forced a choice, the alternatives that were genuinely considered, and the consequences — including the bad ones — of the path taken.

The [README](../README.md) describes what is deployed. These describe why it looks like that.

## Index

| ADR | Decision | Status |
|---|---|---|
| [001](./001-monitoring-on-edge-node.md) | Monitoring stack lives on the edge node | Accepted |
| [002](./002-authelia-at-boundary.md) | Authelia enforces authentication at the boundary, not per-service | Draft |
| [003](./003-moonlight-bare-metal.md) | Game streaming (Sunshine) runs bare metal on the gaming desktop | Accepted |
| [004](./004-no-direct-port-forwarding.md) | No direct port forwarding to Odin or Muninn | Draft |
| [005](./005-docker-compose-over-kubernetes.md) | Docker Compose over Kubernetes | Draft |
| [006](./006-distributed-restic-append-only.md) | Distributed restic backups, per-host keys, append-only targets | Accepted |
| [007](./007-no-network-upgrade.md) | Stay on the eero mesh; no router or switch upgrade | Revisit triggered → [NETWORK.md](../NETWORK.md) |

**Draft** means the decision is made and in effect, but the full rationale hasn't been written down yet — the summary lives inline in the README until it is.

---

## Decided against

Choices deliberately *not* made. These are recorded because the reasoning behind a rejected option decays fastest: a year later the option looks freshly attractive and the objection that killed it has been forgotten. Each entry names the condition that would justify reopening it.

**Don't build a single large AM5 server.** The distributed three-node approach is cheaper and better matched to the actual workloads. The AM5 cascade plan was appealing hardware and over-specced for what the stack does. *Reopen if:* consolidation pressure or a workload genuinely needing that much single-machine compute appears.

**Don't upgrade the network.** The 1 Gbps ceiling doesn't matter for almost any device on it, and the router is only half the upgrade. → [ADR 007](./007-no-network-upgrade.md), which carries the full reasoning and revisit triggers. *Reopened (September 2026):* cameras arrived, which was the strongest trigger; the replacement design is in [NETWORK.md](../NETWORK.md).

**Don't buy a gaming GPU for Muninn.** The i5-10500T's Quick Sync on Odin covers hardware transcoding and any future remote-desktop streaming, which is what the aging GTX 680 was there for. Real-time *game* streaming stays on Thor's dedicated GPU regardless. → [ADR 003](./003-moonlight-bare-metal.md). *Reopen if:* a local AI inference workload lands, which is a different justification for a card and should be argued on its own terms.

**Don't buy a laptop for couch Moonlight use.** The existing hardware already covers it, and a tablet is the better form factor for that spot. *Reopen if:* the existing couch client dies.

**Don't replace Heimdall (the GE60) preemptively.** It is stable and its workload is light. Replacement hardware is picked and cheap, so the plan can execute on short notice. → [ROADMAP](../ROADMAP.md). *Reopen if:* it becomes unreliable, or the monitoring workload outgrows 8GB of RAM.

**Don't buy cameras before the NVR host and network segmentation exist.** Cameras on a flat network with internet access are a liability rather than a security improvement. The isolation they need isn't currently expressible on the eero. *Reopen if:* [ADR 007](./007-no-network-upgrade.md) is revisited and VLAN capability lands. *Overtaken (September 2026):* an Avigilon appliance and cameras came free from work, so the liability this entry warned about is now real, and it is the reason the network plan is active.

**Don't treat offsite backup as a prerequisite.** The distributed restic tier was built first rather than waiting on an offsite story, deliberately — → [ADR 006](./006-distributed-restic-append-only.md). Offsite remains the acknowledged gap and is tracked in the [ROADMAP](../ROADMAP.md), not deferred indefinitely.
