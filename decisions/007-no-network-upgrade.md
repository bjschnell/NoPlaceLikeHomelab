# 007 — Stay on the eero mesh; no router or switch upgrade

**Status:** Accepted

## Context

The physical network is an eero 6 Pro mesh handling both routing and Wi-Fi, with one or two unmanaged 1GbE switches fanning out to the wired devices. Heimdall, Odin, Muninn, Thor and the wired client devices all sit behind that layer. Tailscale runs as an overlay across every node, and AdGuard Home on Heimdall serves DNS with rewrites pointing service subdomains at their internal addresses.

The ISP delivers a 3 Gbps pipe. Everything downstream is capped at 1 Gbps by the eero's ports and the unmanaged switches, so roughly two thirds of the purchased bandwidth is unreachable. That is the obvious complaint, and it is the one that prompts the upgrade question.

The less obvious complaints matter more. The eero exposes no VLAN support — Amazon keeps the platform deliberately closed — and no prosumer controls (QoS, granular port forwarding, static routing). That closure is tolerable today only because the architecture routes around it: external traffic terminates at NGINX on Heimdall behind Cloudflare, remote access goes over Tailscale, and there is no direct port forwarding to any node (→ [ADR 004](./004-no-direct-port-forwarding.md)). The router is not doing security work, so its inability to do security work well has not yet cost anything.

Replacement hardware was evaluated: TP-Link BE9700 and BE600, ASUS RT-BE92U and RT-BE96U. The BE9700 is the preferred unit if and when an upgrade happens.

## Decision

**No network upgrade now.** Stay on the eero 6 Pro mesh and the existing 1GbE switches. Revisit when a concrete requirement appears rather than on the strength of the unused ISP headroom.

The named revisit triggers:

- **Camera VLAN isolation.** A future Frigate NVR should sit on a segment with no internet access, reachable only by the NVR host. That is not expressible on the eero and is the single strongest argument for replacement.
- **Sustained NAS-to-server traffic.** If the Odin ↔ Muninn path becomes heavy enough to feel the 1 Gbps ceiling, a direct 10GbE link between those two hosts solves it without touching the router.
- **A meaningful population of 2.5G+ devices.** Today only the phone and Thor could use more than 1 Gbps.

## Alternatives considered

- **Replace the router with the TP-Link BE9700 now.** The evaluated favourite: VLANs, real QoS, 2.5G ports. Rejected because the router alone does not lift the ceiling — every unmanaged switch between it and the wired nodes would need replacing with 2.5G+ hardware too. The upgrade is a whole-layer project priced and scheduled as if it were a single box, and it delivers throughput that almost nothing on the network can consume.
- **Keep the eero as the router, add a managed switch for VLANs.** Cheaper and partially effective, but VLANs enforced at the switch without a cooperating router leave inter-VLAN routing and the internet-deny rule unsolved — precisely the properties the camera segment needs. Half the work for none of the benefit. Rejected.
- **Replace only the switches with 2.5G units.** Lifts host-to-host throughput on the wired segment while leaving the eero in place. Rejected for now as a solution to a problem no workload currently has; kept in reserve as the cheaper first half of a future upgrade.
- **Run a dedicated 10GbE link between Odin and Muninn.** Two NICs and a cable, bypassing the switched network entirely for the one path that might justify the bandwidth. Not rejected — deferred, and listed above as its own trigger. It is the cheapest answer to the throughput complaint and does not require the router question to be settled first.

## Consequences

- **Positive:** No spend, no migration, no re-pointing of DNS or Tailscale, on a network layer that is currently doing its job.
- **Positive:** The decision is trigger-based rather than timed. The camera project cannot quietly proceed on the assumption that VLAN isolation exists — this ADR makes the dependency explicit.
- **Negative:** Roughly two thirds of the ISP pipe stays unreachable. Accepted: no device on the network can currently consume it.
- **Negative:** No VLAN capability means no network-level isolation for any untrusted device. Today that is a hypothetical; the moment cameras arrive it becomes a real gap, which is why the camera project is gated on this decision being revisited.
- **Negative:** Thor reaches the network over the mesh's wireless backhaul rather than a wired run to the upstairs closet. Pulling that cable is an independent improvement available at any time and does not require replacing any hardware.
- **Negative:** Because the eero cannot do meaningful port forwarding or QoS, the architecture's reliance on Tailscale and the authenticated reverse proxy is load-bearing rather than merely preferred. This is consistent with [ADR 002](./002-authelia-at-boundary.md) and [ADR 004](./004-no-direct-port-forwarding.md), but it is a constraint the router is imposing, not purely a design choice.
