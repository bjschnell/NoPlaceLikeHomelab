#!/bin/bash

pkill -USR1 hyprlock

# Get client resolution from Sunshine env vars
WIDTH=${SUNSHINE_CLIENT_WIDTH:-1920}
HEIGHT=${SUNSHINE_CLIENT_HEIGHT:-1080}
FPS=${SUNSHINE_CLIENT_FPS:-60}

hyprctl output create headless sunshine
sleep 1

# Configure the virtual monitor
hyprctl keyword monitor sunshine,${WIDTH}x${HEIGHT}@${FPS},auto,1

hyprctl dispatch workspace name:streaming
hyprctl keyword workspace "name:streaming,monitor:sunshine"
hyprctl dispatch moveworkspacetomonitor "name:streaming sunshine"
hyprctl dispatch workspace name:streaming

xrandr --output sunshine --primary
