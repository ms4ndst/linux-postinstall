#!/usr/bin/env bash
# Region screenshot via grim + slurp (replaces `flameshot gui`). Saves to
# ~/Pictures/Screenshots/ and copies the PNG to the Wayland clipboard. With no
# region selected (Escape), exits cleanly. Pass `full` to capture the whole
# focused output instead of selecting a region.
set -u
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
OUT="$DIR/shot-$(date +%Y%m%d-%H%M%S).png"

if [ "${1:-region}" = "full" ]; then
  grim "$OUT" || exit 1
else
  GEO="$(slurp 2>/dev/null)" || exit 0
  [ -n "$GEO" ] || exit 0
  grim -g "$GEO" "$OUT" || exit 1
fi

wl-copy --type image/png < "$OUT" 2>/dev/null || true
command -v notify-send >/dev/null && notify-send "Screenshot" "Saved to $OUT and copied to clipboard"
