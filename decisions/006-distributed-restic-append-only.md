# 006 — Distributed restic backups, per-host keys, append-only targets

**Status:** Accepted

## Context

The homelab holds data with very different recovery requirements. A Vaultwarden database is small and irreplaceable; an Authelia DB is small and easy to recreate but painful to lose at 2am; nginx and Authelia configs change rarely but are catastrophic to lose; `/etc` and crontabs are large-ish and only meaningfully change weekly. Treating all of this with one cadence either wastes I/O or accepts an RPO that is wrong for the most important data.

The other shape of the problem is *where backups live*. The legacy setup was a single bash script on Archy that pulled everything to one disk on Archy. Two things make that bad: the source host can destroy its own backups (any `restic forget --prune` from a compromised host wipes history), and a single drive failure on Archy means total loss of the backup tier. Both have to be solved together — a "more frequent backups" answer that still lets a compromised host nuke history is not actually a backup story.

## Decision

Run **restic from each source host to two targets**: Archy (primary) and the opposite source host (peer). Targets run `rest-server --append-only`, so a source host can write new snapshots but cannot delete or prune them. Each source host has its **own** encryption password — Allfather's compromise yields Allfather repos only, not Heimdall's. Backups are tiered into three cadences whose names match their intent:

- **Hot** (every 6 hours): only the tiny irreplaceable secrets — Vaultwarden's SQLite DB on Allfather, Authelia's on Heimdall — dumped via `sqlite3 .backup` for application-consistency, shipped to Archy only.
- **Critical** (nightly 03:00): everything needed to rebuild a working homelab — all `/opt/stacks/*`, Dockge stack definitions, SSH keys, restic config, nginx + letsencrypt on Heimdall. Shipped to Archy *and* the peer host.
- **Full** (weekly Sunday 04:00): superset of critical plus full `/etc`, systemd overrides, crontabs. Also to Archy + peer.

Per-source-host repos, not shared. Pruning happens **only** on the target hosts, out-of-band — never from the source.

## Alternatives considered

- **Single shared repo, single password, one target.** What the legacy script did. Simplest, but a compromise of any source host yields plaintext access to every host's backups, and a single drive failure or buggy `forget` kills everything. Rejected — fails both the security and durability requirements.
- **Pull model (target SSHes into sources and pulls).** Sources hold no credentials to the target; arguably more secure. Rejected because it makes application-consistent dumps awkward (the target would have to drive `sqlite3 .backup` over SSH on the source) and inverts the natural "the host knows its own quiesce procedure" boundary. Append-only on the target gives us the security property without the inversion.
- **Borg instead of restic.** Comparable feature set; restic's HTTP rest-server transport is what unlocks `--append-only` cleanly without per-host SSH plumbing into the targets. Restic chosen for that operational property.
- **One uniform cadence (nightly everything).** Loses up to 24 hours of Vaultwarden writes in a crash. Unacceptable for a password store; fine for `/etc`. The tiered split costs one extra systemd timer and earns a 6-hour RPO on the data that warrants it.
- **Off-site / cloud (B2, etc.) from day one.** The right long-term answer and listed as outstanding work — but treating it as a prerequisite would have blocked the security and tiering improvements above. Local 3-host distribution first; offsite layered on later.

## Consequences

- **Positive:** A compromised source host can write garbage snapshots but cannot destroy history. Pruning requires shell access on the target, which an attacker on the source does not have.
- **Positive:** A compromise of one source host's password does not decrypt the other's repos. Blast radius is one host.
- **Positive:** RPO matches data criticality without over-running the cheap-but-bulky data on a 6-hour timer.
- **Positive:** Peer replication means losing any single host (including Archy) still leaves a recent copy of the critical+full tiers on a second host.
- **Negative:** Hot tier is on Archy only; if Archy is down, the worst case fallback is the previous night's critical snapshot from the peer (acceptable, explicitly traded).
- **Negative:** Archy's `/Tres` is still a single 1.8 TB drive. The peer copies cover critical+full; hot is exposed. A proper dedicated backup drive (or ZFS mirror) on Archy is acknowledged tech debt, not a solved problem.
- **Negative:** Append-only means repos grow unbounded between manual prunes on the targets. Needs a scheduled monthly maintenance window per target — currently a runbook step, not yet automated.
- **Negative:** No offsite copy yet. Local-only protects against drive failure and host compromise but not site loss (theft, fire). On the outstanding-work list.

Operational detail (scripts, systemd units, restore + rotation runbooks, the "what is not backed up by design" list) lives in [`homelab-backup/`](../homelab-backup/).
