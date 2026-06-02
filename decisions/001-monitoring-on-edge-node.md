# 001 — Monitoring stack lives on the edge node

**Status:** Accepted

## Context

The stack has three nodes: Heimdall (edge/network), Allfather (primary application host), and Muninn (NAS/media). The observability stack — Prometheus, Grafana, Uptime Kuma, plus the `cAdvisor`/`node_exporter` agents Prometheus scrapes — has to live *somewhere*.

The intuitive placement is Allfather: it's the primary application host (i5-10500T, 32GB) and monitoring a time-series workload likes RAM and a stable home. The problem is what monitoring is *for*. You consult it precisely when something is wrong — and the most common "something is wrong" is a node falling over. A monitoring stack that goes down with the thing it's supposed to be watching is worthless at the exact moment you need it.

Heimdall is the always-on edge node. It carries the lightest, most stable workload by design (DNS, reverse proxy, auth) and is the one node that effectively cannot be down, because if it's down nothing else is reachable anyway.

## Decision

Run the monitoring stack (Prometheus, Grafana, Uptime Kuma, Dockge) on **Heimdall**, the edge node. All three nodes run lightweight exporters (`node_exporter`, `cAdvisor`); Prometheus on Heimdall scrapes them centrally.

## Alternatives considered

- **Monitoring on Allfather (the primary app host).** Most RAM headroom and the newest CPU, but couples observability to the busiest, most change-prone host. If Allfather is the thing that fails — the statistically likely case, since it runs the most services — you lose visibility exactly when you need it. Rejected.
- **Monitoring agent on every node, no central collector.** Resilient, but there's no single pane of glass and no cross-node correlation. You'd be SSH-ing into a possibly-degraded box to read its own metrics. Rejected.
- **External / hosted monitoring (Grafana Cloud, Uptime Kuma on a VPS).** Survives *any* local node failure and is the genuinely correct answer for production. Rejected here because it adds an external dependency, a cost, and egress of metrics off-network for a home setup where the edge node is already a reliable host. Uptime Kuma's external-probe value is partially recovered by also pinging from outside via the public domain.

## Consequences

- **Positive:** Visibility survives failure of either compute node — the single most useful property a monitoring stack can have. The edge node's stability profile matches monitoring's "must stay up" requirement.
- **Positive:** Centralized Prometheus gives cross-node dashboards in one Grafana, and Uptime Kuma gives one availability view.
- **Negative:** Heimdall (a 4th-gen laptop with 8GB RAM) is the weakest machine carrying the time-series workload. Retention windows and scrape cardinality have to stay modest. This is an accepted constraint, not a problem — homelab metrics volume is small.
- **Negative:** A total Heimdall failure still takes monitoring down with it. Mitigated by Heimdall being the lowest-change, highest-stability node; not fully solved without the external-monitoring option above. Revisit if Heimdall's reliability ever proves to be the weak link.
