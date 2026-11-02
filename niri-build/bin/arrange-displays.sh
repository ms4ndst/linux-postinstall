#!/usr/bin/env bash
# Display arrangement for niri. Unlike Sway, niri has no runtime "set output
# position" IPC - monitor layout lives in config.kdl's `output` blocks (niri
# auto-arranges left-to-right by default). So this opens a GUI editor when one
# is available (nwg-displays supports niri and writes the output blocks for
# you), and otherwise points at NiriMod + prints the current outputs.
set -u
if command -v nwg-displays >/dev/null 2>&1; then
  exec nwg-displays
fi
if command -v niri-mod.sh >/dev/null 2>&1 || command -v nirimod >/dev/null 2>&1; then
  notify-send "Displays" "Open NiriMod (Mod+Shift+S) to arrange monitors, or install nwg-displays for a drag-and-drop editor." 2>/dev/null
  exec ~/.local/bin/niri-mod.sh
fi
# Last resort: list outputs so the user can hand-edit config.kdl output blocks.
OUT="$(niri msg outputs 2>/dev/null)"
notify-send "Displays" "Install nwg-displays (drag-and-drop) or use NiriMod. Outputs:\n$OUT" 2>/dev/null \
  || printf '%s\n' "$OUT"
