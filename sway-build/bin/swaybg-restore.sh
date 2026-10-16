#!/usr/bin/env bash
# Restore the saved wallpaper with swaybg (replaces nitrogen --restore).
# Sources, in order (between the first two, whichever pick is newer wins):
#   1. ~/.config/sway/wallpaper-saved     - written by the rofi picker
#   2. ~/.local/share/azote/swaybg.json   - written by azote, one entry per
#      output (azote is the preferred picker when installed)
#   3. ~/.config/sway/wallpaper.png       - seeded by the installer
# exec_always re-runs this on reload, so kill any previous swaybg first to
# avoid stacking.
set -u
CFG="$HOME/.config/sway"
SAVED="$CFG/wallpaper-saved"
AZOTE_JSON="$HOME/.local/share/azote/swaybg.json"

IMG=""
[ -f "$SAVED" ] && IMG="$(cat "$SAVED")"
if [ -n "$IMG" ] && [ -f "$IMG" ]; then
  # A newer azote pick overrides an older rofi pick (and vice versa).
  [ -f "$AZOTE_JSON" ] && [ "$AZOTE_JSON" -nt "$SAVED" ] && IMG=""
else
  IMG=""
fi

ARGS=()
if [ -n "$IMG" ]; then
  ARGS=(-i "$IMG" -m fill)
elif [ -f "$AZOTE_JSON" ] && command -v jq >/dev/null 2>&1; then
  # Drop entries whose file has vanished since the pick (e.g. the wallpapers
  # directory was renamed) so the restore falls through to the next source.
  while IFS=$'\t' read -r out path; do
    [ -n "$out" ] && [ -n "$path" ] && [ -f "$path" ] \
      && ARGS+=(-o "$out" -i "$path" -m fill)
  done < <(jq -r '.[] | select(.name and .path) | [.name, .path] | @tsv' \
             "$AZOTE_JSON" 2>/dev/null)
fi
# Fall back to the sway wallpaper seeded by the installer.
[ "${#ARGS[@]}" -eq 0 ] && [ -f "$CFG/wallpaper.png" ] \
  && ARGS=(-i "$CFG/wallpaper.png" -m fill)
[ "${#ARGS[@]}" -eq 0 ] && exit 0

pkill -x swaybg 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swaybg >/dev/null 2>&1 || break; sleep 0.1; done
swaybg "${ARGS[@]}" >/dev/null 2>&1 &
disown || true
