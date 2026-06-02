# 003 — Game streaming (Sunshine) runs bare metal on the gaming desktop, not on a server node

**Status:** Accepted

## Context

The household game-streams to a Steam Deck and other clients via Moonlight, which needs a Sunshine host with a capable GPU and low-latency hardware video encoding (NVENC). The question is *where* that host lives.

The GPU that matters already sits in the daily-driver gaming desktop (Ragnarok — Ryzen 9 9950X3D, RTX 5080). The homelab server nodes are headless and either GPU-less or running an ancient card; none is a sensible place to do real-time game encoding. The two tempting "tidier" options — provision a GPU into a server node and containerize Sunshine, or stand up a dedicated streaming box — both add hardware, power, and passthrough complexity in service of a workload whose entire value proposition is *low latency and no overhead*.

## Decision

Run **Sunshine bare metal on Ragnarok**, the gaming desktop, and keep game streaming **off the server nodes entirely**. Moonlight clients (Steam Deck, Odin, iPhone) connect to it directly over the LAN or Tailscale. The "everything in Docker on a server" pattern has an explicit, documented exception here: the GPU workload stays on the machine that already has the GPU, on bare metal.

## Alternatives considered

- **GPU in a server node + containerized Sunshine.** Keeps the stack uniform and centralizes everything on the homelab tier. Costs: a GPU to buy and power in a server, NVIDIA Container Toolkit setup, driver-version coupling between host and container, and extra latency surface — all to relocate a workload off a machine that already has a far better GPU. Complexity with negative payoff. Rejected.
- **Sunshine in a VM with GPU passthrough (VFIO) on a server.** The "proper" isolation answer, and the heaviest. IOMMU config, a GPU bound to the VM, significant tuning — wildly disproportionate for a single-household game-stream host. Rejected.
- **A dedicated streaming box.** Cleanest separation, but it's another always-on machine to buy, power, and maintain for something the gaming desktop already does for free. Rejected on cost/footprint.
- **Containerizing Sunshine on the gaming desktop.** Pointless — it's a single-purpose interactive machine where bare metal is simpler, lower-latency, and avoids any passthrough layer. Rejected.

## Consequences

- **Positive:** The GPU workload lives where the GPU is. Lowest latency, no passthrough layer to debug, no extra hardware or power draw.
- **Positive:** Server nodes stay headless and lean — no GPU, no game-streaming concerns, consistent with the separation-of-responsibilities design.
- **Negative:** Game streaming is only available when the gaming desktop is on, and it sits outside the Docker/Compose management, monitoring, and backup story that covers the server nodes. This is a deliberate, scoped exception — documented here so it's a known seam rather than a surprise.
- **Negative:** Sunshine and GPU-driver updates on Ragnarok are a manual, out-of-band task. Accepted; it's a daily-driver machine that's maintained anyway.

> **Note:** An earlier plan considered moving *remote-desktop* Sunshine duties onto Allfather (7080) using Intel Quick Sync once it takes over more services. That's a possible future change for non-gaming remote access; real-time *game* streaming stays on the dedicated GPU in Ragnarok regardless.
