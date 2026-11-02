#!/usr/bin/env bash
# Backlight control + a dunst OSD popup for the Niri rice, via brightnessctl.
# The stacked-tag notification replaces itself so repeated key presses update
# one popup instead of stacking.
set -u
STEP="5%"

command -v brightnessctl >/dev/null 2>&1 || {
  notify-send -h string:x-dunst-stack-tag:osd-brightness "Brightness" "brightnessctl is not installed" 2>/dev/null
  exit 1
}

case "${1:-}" in
  up)   brightnessctl set "${STEP}+" >/dev/null ;;
  down) brightnessctl set "${STEP}-" >/dev/null ;;
  *)    echo "usage: osd-brightness.sh up|down" >&2; exit 1 ;;
esac

CUR=$(brightnessctl get 2>/dev/null)
MAX=$(brightnessctl max 2>/dev/null)
PCT=0
[ -n "${MAX:-}" ] && [ "${MAX:-0}" -gt 0 ] && PCT=$(( CUR * 100 / MAX ))

notify-send -h string:x-dunst-stack-tag:osd-brightness \
  -h "int:value:$PCT" -i "display-brightness-symbolic" "Brightness" "${PCT}%" 2>/dev/null || true
