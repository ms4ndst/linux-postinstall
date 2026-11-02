#!/usr/bin/env bash
# Volume control + a dunst OSD popup for the Niri rice. Uses wpctl (PipeWire's
# WirePlumber control); the stacked-tag notification replaces itself so repeated
# key presses update one popup instead of stacking.
set -u
SINK="@DEFAULT_AUDIO_SINK@"
STEP="5%"

case "${1:-}" in
  up)   wpctl set-mute "$SINK" 0; wpctl set-volume -l 1.5 "$SINK" "${STEP}+" ;;
  down) wpctl set-mute "$SINK" 0; wpctl set-volume "$SINK" "${STEP}-" ;;
  mute) wpctl set-mute "$SINK" toggle ;;
  *)    echo "usage: osd-volume.sh up|down|mute" >&2; exit 1 ;;
esac

read -r _ VOL MUTED < <(wpctl get-volume "$SINK" 2>/dev/null)
PCT=$(awk -v v="${VOL:-0}" 'BEGIN{printf "%d", v*100}')
if [ "${MUTED:-}" = "[MUTED]" ] || [ "$PCT" -eq 0 ]; then
  ICON="audio-volume-muted"; TEXT="Muted"
elif [ "$PCT" -lt 34 ]; then
  ICON="audio-volume-low"; TEXT="${PCT}%"
elif [ "$PCT" -lt 67 ]; then
  ICON="audio-volume-medium"; TEXT="${PCT}%"
else
  ICON="audio-volume-high"; TEXT="${PCT}%"
fi

notify-send -h string:x-dunst-stack-tag:osd-volume \
  -h "int:value:$PCT" -i "$ICON" "Volume" "$TEXT" 2>/dev/null || true
