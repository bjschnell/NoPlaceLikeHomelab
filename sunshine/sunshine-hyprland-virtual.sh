#!/bin/bash
pkill -USR1 hyprlock

WIDTH=${SUNSHINE_CLIENT_WIDTH:-1920}
HEIGHT=${SUNSHINE_CLIENT_HEIGHT:-1080}
FPS=${SUNSHINE_CLIENT_FPS:-60}

# Create the headless output
hyprctl output create headless sunshine

# Wait for it to appear
for i in {1..50}; do
  hyprctl monitors -j | jq -e '.[] | select(.name=="sunshine")' >/dev/null 2>&1 && break
  sleep 0.1
done

# Configure mode via eval (not keyword)
hyprctl eval "hl.monitor({ output = 'sunshine', mode = '${WIDTH}x${HEIGHT}@${FPS}', position = 'auto', scale = 1 })"

# Register workspace rule via eval
hyprctl eval "hl.workspace_rule({ workspace = 'name:streaming', monitor = 'sunshine', default = true })"

# Focus the streaming workspace on the sunshine monitor
hyprctl dispatch "hl.dsp.focus({ workspace = 'name:streaming' })"
hyprctl dispatch "hl.dsp.focus({ monitor = 'sunshine' })"

# Set X11 primary so XWayland apps (Steam Big Picture) land on sunshine
xrandr --output sunshine --primary
