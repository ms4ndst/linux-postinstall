#!/usr/bin/env bash
# Kill any running waybar and relaunch it against the current theme
# (~/.config/waybar/config.jsonc + style.css). Unlike polybar on X11, waybar
# draws on every connected output from one process and each instance gets its
# own working SNI tray, so there's no primary/secondary split or single-tray-
# owner dance to manage here - one relaunch covers all monitors.
set -u
pkill -x waybar 2>/dev/null
# give it a moment to release its layer-shell surfaces before relaunching
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x waybar >/dev/null 2>&1 || break
  sleep 0.1
done
pkill -9 -x waybar 2>/dev/null || true
waybar >/dev/null 2>&1 &
disown || true
