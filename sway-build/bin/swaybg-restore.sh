#!/usr/bin/env bash
# Restore the saved wallpaper with swaybg (replaces nitrogen --restore). The
# chosen image path lives in ~/.config/sway/wallpaper-saved; the fallback is
# ~/.config/sway/wallpaper.png (seeded by the installer). exec_always re-runs
# this on reload, so kill any previous swaybg first to avoid stacking.
set -u
CFG="$HOME/.config/sway"
SAVED="$CFG/wallpaper-saved"
IMG=""
[ -f "$SAVED" ] && IMG="$(cat "$SAVED")"
# Fall back to the sway wallpaper, then the installer's seeded i3 path.
[ -n "$IMG" ] && [ -f "$IMG" ] || IMG="$CFG/wallpaper.png"
[ -f "$IMG" ] || IMG="$HOME/.config/i3/wallpaper.png"
[ -f "$IMG" ] || exit 0

pkill -x swaybg 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swaybg >/dev/null 2>&1 || break; sleep 0.1; done
swaybg -i "$IMG" -m fill >/dev/null 2>&1 &
disown || true
