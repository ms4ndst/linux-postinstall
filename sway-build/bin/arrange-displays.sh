#!/usr/bin/env bash
# Lay out every ACTIVE output left-to-right at its best mode, so multiple
# monitors EXTEND instead of mirroring. When a monitor is toggled (wdisplays,
# swaymsg, hotplug) sway drops it back to position (0,0), overlapping the others
# = a mirror, sometimes in a junk fallback mode - this fixes both. Bound to
# Mod+Shift+o and the app menu's "Arrange Displays"; run it after enabling or
# disabling a monitor. Disabled outputs are left off (this only arranges the
# ones that are on).
set -u
if ! command -v jq >/dev/null 2>&1; then
  command -v notify-send >/dev/null && notify-send "Displays" "jq is required for arrange-displays"
  exit 1
fi

x=0
# name  bestWidth  bestHeight  bestRefreshHz  for each active output, widest first
while read -r name w h r; do
  # try the best mode + position; fall back to position-only if the mode string
  # is rejected (keeps the current mode but still de-mirrors)
  swaymsg output "$name" mode "${w}x${h}@${r}Hz" position "$x" 0 >/dev/null 2>&1 \
    || swaymsg output "$name" position "$x" 0 >/dev/null 2>&1
  x=$((x + w))
done < <(swaymsg -t get_outputs | jq -r '
  .[] | select(.active)
  | (.modes | max_by([.width * .height, .refresh])) as $m
  | "\(.name) \($m.width) \($m.height) \(($m.refresh / 1000))"')

n="$(swaymsg -t get_outputs | jq '[.[] | select(.active)] | length')"
command -v notify-send >/dev/null && notify-send "Displays" "Arranged $n active output(s) left-to-right"
