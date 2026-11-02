#!/usr/bin/env bash
# blueman-manager (opened via the polybar bluetooth widget's click action)
# unconditionally auto-spawns blueman-applet as its own backend on open -
# there's no flag to stop this, and it's what puts the redundant bluetooth
# tray icon right back after we deliberately disabled its autostart entry.
# Reap it if it ever reappears instead of fighting blueman's own code.
while true; do
  pkill -x blueman-applet 2>/dev/null
  sleep 3
done
