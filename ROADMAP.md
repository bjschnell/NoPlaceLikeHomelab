# Roadmap

Planned work on the homelab, ordered by how much damage its absence could do. The [README](./README.md) documents what exists today; this documents what doesn't yet and why it's queued where it is.

Nothing here is scheduled. Each item carries the condition that promotes it, because most of this is gated on a failure, a purchase, or another item landing first. Choices deliberately *not* on this list are recorded under [Decided against](./decisions/README.md#decided-against).

---

## Priority — data safety

These two are the only items where waiting carries real risk. Everything below them is improvement; these are exposure.

### UPS for the server nodes

An 850–1500VA CyberPower or APC unit covering Heimdall, Odin and Muninn.

The concern is not uptime, it's the write path. Muninn's storage is aging spinning disks and an abrupt power cut mid-write is one of the shorter routes to data loss in the whole stack. A UPS converts a hard power loss into a controlled shutdown.

Pair it with NUT (Network UPS Tools) so both hosts shut down gracefully on battery rather than merely surviving the blink — a UPS without automated shutdown only shortens the odds, it doesn't remove the failure mode. NUT runs fine in Docker with the USB device passed through.

*Blocked on:* nothing. This is a purchase.

### 8TB drive for Muninn

Muninn's `/Tres` is a single 1.8 TB drive that currently serves as the primary restic backup target. [ADR 006](./decisions/006-distributed-restic-append-only.md) names this explicitly as accepted tech debt: peer replication covers the critical and full tiers if that drive dies, but the hot tier — the 6-hourly Vaultwarden and Authelia snapshots — lives there and only there.

A larger dedicated backup drive closes the hot-tier exposure and unblocks the second item on the backup pipeline's [outstanding work](./homelab-backup/docs/ARCHITECTURE.md#outstanding-work): making Muninn a backup *source* as well as a target, which would finally cover the \*arr configs and the Home Assistant supervisor tarballs that currently land on it unbacked.

A ZFS mirror would be the better answer than a single larger disk. Two drives is the cost question.

*Blocked on:* nothing. This is a purchase, and it is the one that unblocks the most downstream work.

---

## Backup — offsite copy

The remaining gap in the 3-2-1 story. Local distribution across three hosts protects against drive failure and single-host compromise; it does not protect against the site. Fire, flood and theft take all three copies at once.

Two approaches, not yet chosen between:

- **Raspberry Pi with an external USB drive at a family member's house**, replicating back over Tailscale. Cheap after the hardware, no recurring cost, no third party holding the data. Costs a physical dependency on someone else's power and internet, and someone else's house is where the drive fails silently.
- **Backblaze B2 via `restic copy` from Muninn**, which is what the backup pipeline's [outstanding work](./homelab-backup/docs/ARCHITECTURE.md#outstanding-work) already anticipates. Recurring cost that scales with data, no hardware to maintain, and the restore path is bandwidth-bound rather than a drive in a car.

Either way the first pass should cover only the irreplaceable set — photos, documents, Vaultwarden — rather than attempting the full repos. The critical tier is small; the media is not, and the media is replaceable.

*Blocked on:* nothing technically. Both options are affordable; the decision is which failure mode is more tolerable.

---

## Heimdall replacement — lightweight network node

Heimdall is an MSI GE60 laptop from 2013 running the edge: DNS, reverse proxy, auth and the entire monitoring stack. It's stable and the workload is light, so this is explicitly **not** something to do preemptively — see [Decided against](./decisions/README.md#decided-against). The plan exists so that when the machine dies, the replacement is a purchase and an afternoon rather than a research project.

**Candidates**, both around $100–150 CAD used:

- Dell OptiPlex 3050 / 3060 Micro — i5 7th or 8th gen, enterprise build, designed for 24/7 duty
- Lenovo ThinkCentre M710q / M720q — same tier, equally durable

**Requirements:** wired Ethernet (this node's services are network-critical and cannot depend on Wi-Fi), reliable headless Linux, low idle draw for 24/7 operation, and cheap. The workload is DNS and monitoring; any of the above is already overkill.

One thing to reconsider at replacement time rather than now: Heimdall's 8GB of RAM is the constraint that keeps Prometheus retention and scrape cardinality modest, a limitation [ADR 001](./decisions/001-monitoring-on-edge-node.md) accepts deliberately. A 16–32GB replacement would lift it, and that's a reason to size the replacement generously despite the trivial service load.

*Blocked on:* the GE60 failing or becoming unreliable.

---

## Camera NVR — future Frigate host

A dedicated machine for a Frigate NVR. No cameras purchased, no urgency, and deliberately gated — see below.

**Target hardware:** Dell OptiPlex SFF or Micro, i5 8th gen or newer, ~$150–200 CAD used. Intel 8th gen is the floor because Quick Sync does the heavy lifting for camera stream decode; without it the CPU cost of continuous multi-stream object detection preprocessing gets ugly. 16GB RAM minimum, NVMe boot plus a large HDD or SSD for retention.

**Models to watch:** OptiPlex 3060/5060/7060 (8th gen) or 3080/5080/7080 (10th gen) in SFF or Micro; Lenovo ThinkCentre M720q/M920q; HP EliteDesk 800 G4/G5 Mini.

**Optional:** a Google Coral TPU USB accelerator (~$40–60 CAD) moves inference off the CPU entirely and is the single best value add-on for Frigate. A small PoE switch if the cameras are PoE, keeping power and data on one run.

**Why its own machine rather than a container on Odin:** camera recording is a continuous write-heavy workload with a 24/7 duty cycle, and object detection is bursty and resource-hungry. Isolating it means an NVR problem doesn't become a Vaultwarden problem. It also keeps the security-camera segment separable from everything else, which matters more than the resource argument.

*Blocked on:* [ADR 007](./decisions/007-no-network-upgrade.md) being revisited. Cameras belong on an isolated segment with no internet access, reachable only by the NVR — and the current eero mesh cannot express that. Buying cameras before the network can isolate them means running them flat, which is worse than not having them. This dependency runs in both directions: the camera project is the strongest single argument for replacing the router.

---

## Network — wired run to the office

Independent of the router question and available at any time: pulling Ethernet from the office to the upstairs closet would put Thor on a wired path instead of the mesh's wireless backhaul.

This needs no new hardware and is unaffected by [ADR 007](./decisions/007-no-network-upgrade.md) — it's cable and labour. It is the only network improvement currently on the list that isn't gated on the router decision.

*Blocked on:* willingness to run the cable.
