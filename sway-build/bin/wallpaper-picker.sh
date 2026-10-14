#!/usr/bin/env bash
# Rofi-based wallpaper picker. Lists images from
# the usual wallpaper dirs, sets the pick with swaybg, and saves the path so
# swaybg-restore.sh brings it back on the next login/reload. If azote (the
# Wayland-native nitrogen equivalent) is installed, prefer its GUI instead.
set -uo pipefail

if command -v azote >/dev/null 2>&1; then
  exec azote
fi

DIRS=(
  "$HOME/Pictures/wallpapers"
  "$HOME/Pictures/gh0stzk-wallpapers"
  "$HOME/.config/sway"
  "$HOME/Pictures"
)
SAVED="$HOME/.config/sway/wallpaper-saved"
ROFI_CURRENT="$HOME/.config/rofi/current.rasi"

mapfile -t FILES < <(
  for d in "${DIRS[@]}"; do
    [ -d "$d" ] && find "$d" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' \) 2>/dev/null
  done | sort -u
)
if [ "${#FILES[@]}" -eq 0 ]; then
  notify-send "Wallpaper" "No images found in: ${DIRS[*]}"
  exit 1
fi

# Show "basename  (dir)" but map back to the full path on selection.
declare -A MAP
LINES=()
for f in "${FILES[@]}"; do
  label="$(basename "$f")  ($(dirname "$f" | sed "s#$HOME#~#"))"
  MAP["$label"]="$f"
  LINES+=("$label")
done

PICK="$(printf '%s\n' "${LINES[@]}" | rofi -dmenu -i -p "Wallpaper" ${ROFI_CURRENT:+-theme "$ROFI_CURRENT"})"
[ -n "$PICK" ] || exit 0
IMG="${MAP[$PICK]:-}"
[ -n "$IMG" ] && [ -f "$IMG" ] || exit 0

printf '%s' "$IMG" > "$SAVED"
~/.local/bin/swaybg-restore.sh
notify-send "Wallpaper" "Set to $(basename "$IMG")"
