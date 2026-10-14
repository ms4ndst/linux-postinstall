#!/usr/bin/env bash
# Grab any on-screen pixel's color as hex and copy it to the clipboard - Sway
# rice port of the i3 rice's slop+import+xclip colorpicker. slurp -p picks a
# single point, grim captures just that pixel, ImageMagick samples it, wl-copy
# puts the hex on the Wayland clipboard. A small solid swatch PNG is generated
# as the notification icon so the popup shows the picked color, not just text.
set -uo pipefail

for dep in slurp grim magick wl-copy; do
  if ! command -v "$dep" &>/dev/null; then
    notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "'$dep' is not installed"
    exit 1
  fi
done

# slurp -p: point mode, outputs "x,y 1x1". A plain cancel (Escape) exits slurp
# non-zero -> stay silent, same as the i3 rice's user-cancel path.
GEOM=$(slurp -p 2>/dev/null) || exit 0
[ -n "$GEOM" ] || exit 0

# Capture the single pixel and ask ImageMagick for its sRGB triplet.
PIX=$(grim -g "$GEOM" -t ppm - 2>/dev/null | magick - -format '%[pixel:p{0,0}]' txt:- 2>/dev/null | tail -n1)
if [ -z "$PIX" ]; then
  notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "failed to sample pixel"
  exit 1
fi

# Parse "srgb(r,g,b)" / "srgba(r,g,b,a)" decimals into #RRGGBB (0-255 range;
# magick's txt: output is 8-bit decimals here, not Q16 scaled).
RGB=$(printf '%s' "$PIX" | grep -oE 'srgba?\([0-9]+,[0-9]+,[0-9]+' | head -1 | grep -oE '[0-9]+' | head -3)
read -r R G B <<< "$(printf '%s ' $RGB)"
if [ -z "${R:-}" ] || [ -z "${G:-}" ] || [ -z "${B:-}" ]; then
  notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "could not parse color: $PIX"
  exit 1
fi
HEX=$(printf '#%02X%02X%02X' "$R" "$G" "$B")

printf '%s' "$HEX" | wl-copy
SWATCH="$(mktemp --suffix=.png)"
magick -size 64x64 xc:"$HEX" "$SWATCH" 2>/dev/null || true
notify-send -h string:x-dunst-stack-tag:colorpicker -i "$SWATCH" "Colorpicker" "$HEX copied to clipboard"
( sleep 5; rm -f "$SWATCH" ) &
disown || true
