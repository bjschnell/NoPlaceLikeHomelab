# Sunshine bare-metal scripts

Hyprland virtual-display scripts invoked by [Sunshine](https://app.lizardbyte.dev/Sunshine/) on Ragnarok (the daily-driver gaming desktop) when a Moonlight client connects. They create a headless monitor sized to the client's resolution and tear it down on disconnect, so streamed sessions get their own dedicated workspace without disturbing what's on the physical displays.

> **Background:** Sunshine runs bare metal on the desktop rather than in a container or on a server node. Reasoning is in [ADR 003](../decisions/003-moonlight-bare-metal.md).

## Files

| Script | Sunshine hook | Purpose |
|---|---|---|
| `sunshine-hyprland-virtual.sh` | per-app `do` (prep) | Creates the headless `sunshine` output, configures it to the client's `WIDTH x HEIGHT @ FPS` (from `SUNSHINE_CLIENT_*` env vars), pins a `streaming` workspace to it, and sets it as the X11 primary so XWayland apps (e.g. Steam Big Picture) land on the streamed display. |
| `sunshine-virtual-backup.sh` | (fallback) | Older `hyprctl keyword`-based version of the above, kept as a fallback. The current script targets the post-Lua-API Hyprland (`hyprctl eval "hl.monitor(...)"`); this one works against older releases. |
| `cleanup-virtual.sh` | per-app `undo` (teardown) | `hyprctl output remove sunshine` — drops the headless monitor when the client disconnects. |

## Wiring

In Sunshine's per-application config:

- **Do** (prep): `bash /path/to/sunshine-hyprland-virtual.sh`
- **Undo** (teardown): `bash /path/to/cleanup-virtual.sh`

Sunshine passes the negotiated client resolution to the prep script via `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS`. The script falls back to 1920x1080 @ 60 if those are unset.

The `pkill -USR1 hyprlock` at the top of the prep script asks any active hyprlock instance to refresh — useful when a stream session starts while the desk is locked.
