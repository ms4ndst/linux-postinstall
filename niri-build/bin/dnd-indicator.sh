#!/usr/bin/env bash
# Waybar custom/notification-silencing-indicator backend: reports dunst's
# pause state as waybar JSON so the bar always shows a small bell -
# normal text color while notifications flow, the theme accent while
# muted (Mod+N / dnd-toggle.sh), however the toggle was triggered -
# keybind, widget click, or a bare dunstctl. The themes' CSS (plus the
# installer-appended accent rule) paints .active.
if [ "$(dunstctl is-paused)" = "true" ]; then
  printf '{"text":"","class":"active","tooltip":"Do Not Disturb: notifications muted (Mod+N or click to unmute)"}\n'
else
  printf '{"text":"","class":"","tooltip":"Notifications: on (Mod+N or click to mute)"}\n'
fi
