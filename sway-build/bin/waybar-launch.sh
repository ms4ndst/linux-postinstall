#!/usr/bin/env bash
# Kill any running waybar and relaunch it against the current theme
# (~/.config/waybar/config.jsonc + style.css). Unlike polybar on X11, waybar
# draws on every connected output from one process and each instance gets its
# own working SNI tray, so there's no primary/secondary split or single-tray-
# owner dance to manage here - one relaunch covers all monitors.
set -u
# waybar links against the system libstdc++; a stale LD_LIBRARY_PATH (e.g.
# a tool session exporting an editor's bundled libraries) makes it die
# with GLIBCXX errors the moment it starts. Strip it before launching.
unset LD_LIBRARY_PATH
# The adapted HANCORE themes exec helper scripts by bare name (wttrbar,
# hancore-update-check, ...) - make sure ~/.local/bin is on the bar's PATH.
export PATH="$HOME/.local/bin:$PATH"
# Waybar is a GTK app: unstyled text falls back to the GTK theme's
# foreground. The session env can carry a STALE GTK_THEME (e.g. a theme
# name from a previous rice that no longer exists), which makes GTK fall
# back to its light default and render module values near-black. Point
# the bar at the current theme's generated Rice-* GTK theme instead.
CURRENT_THEME="$(cat "$HOME/.config/waybar/current-theme-name" 2>/dev/null || true)"
if [ -n "$CURRENT_THEME" ] && [ -d "$HOME/.themes/Rice-$CURRENT_THEME/gtk-3.0" ]; then
  export GTK_THEME="Rice-$CURRENT_THEME"
fi
pkill -x waybar 2>/dev/null
# give it a moment to release its layer-shell surfaces before relaunching
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x waybar >/dev/null 2>&1 || break
  sleep 0.1
done
pkill -9 -x waybar 2>/dev/null || true
waybar >/dev/null 2>&1 &
disown || true
