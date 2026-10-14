#!/usr/bin/env bash
# Waybar custom/caffeine widget backend: reports the rice's caffeine state
# (Mod+C / ~/.local/bin/caffeine-toggle.sh) as waybar JSON, so the bar icon
# reflects the toggle however it was triggered - by the keybind, by clicking
# the widget (which runs the same toggle script), or by anything else. This
# replaces the native idle_inhibitor module, which was an independent
# Wayland inhibitor that never showed caffeine's actual state.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  printf '{"text":"󰛨","class":"activated","tooltip":"Caffeine: ON - screen lock/sleep inhibited (click or Mod+C to release)"}\n'
else
  printf '{"text":"󰛩","class":"deactivated","tooltip":"Caffeine: OFF (click or Mod+C to stay awake)"}\n'
fi
