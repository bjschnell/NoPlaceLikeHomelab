# Scripts

Standalone operational scripts that don't belong to a larger subsystem. The backup system lives in [`homelab-backup/`](../homelab-backup/) and the game-streaming scripts in [`sunshine/`](../sunshine/).

| Script | Runs on | Purpose |
|---|---|---|
| `startup-qwen` / `stop-qwen` | Thor | Run a local Qwen3.6-35B model through `llama-server`, detached so it survives an SSH disconnect. `startup-qwen status`, `logs`, `restart` and `fg` cover the rest of the lifecycle. |
| `qwen-common.sh` | Thor | Shared config and stop logic sourced by both Qwen scripts, so start and stop can never disagree about paths or PIDs. Set `LLAMA_SERVER` to override the binary location. |
| `add-samba-user.sh` | Muninn | Create a Linux user (if needed), add it to `sambausers`, and set up and enable its Samba password. Run as root. |
| `panic-reboot.sh` | Any | Emergency sync → remount read-only → reboot through the kernel's magic SysRq interface, for when a node is wedged but still takes a shell. Run as root. |
| `bootstrap_services.sh` | — | **Legacy.** Checks systemd services, Docker Compose stacks and the Home Assistant VM, starting whatever is down. Written for the single-host layout that predates the three-node split, so its service list (Plex, NGINX, Authelia on one box) no longer matches [SERVICES.md](../SERVICES.md). |
