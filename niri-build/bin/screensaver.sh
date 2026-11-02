#!/usr/bin/env bash
# Block-art screensaver, inspired by Omarchy's built-in one - same underlying
# tool (Terminal Text Effects / `tte`, pipx-installed) AND the same logo
# style Omarchy itself ships (its logo.txt is a solid Unicode half-block
# render, not typed ASCII letters - see omarchy-transcode-ascii --mode
# block), just run in a plain fullscreen kitty window instead of Omarchy's
# Astal/AGS shell (which this rice doesn't have an equivalent of). Exits on any
# keypress OR mouse movement.
# tte is pipx-installed into ~/.local/bin - which the swayidle context's
# PATH (inherited from sway's login-time snapshot) does NOT include, so a
# bare-name call failed with "tte not found" whenever the screensaver was
# triggered by the idle timeout. Re-add it here so both entry paths work:
# the idle lock and the on-demand Mod+Escape bind.
export PATH="$HOME/.local/bin:$PATH"
LOGO="$HOME/.config/screensaver/logo.txt"
FEDORA_SVG="/usr/share/fedora-logos/fedora_logo.svg"
if [ ! -f "$LOGO" ]; then
  mkdir -p "$(dirname "$LOGO")"
  if command -v magick >/dev/null 2>&1 && [ -f "$FEDORA_SVG" ]; then
    # Two source pixel rows -> one terminal row, using a half-block glyph
    # (█ both on, ▀ top only, ▄ bottom only, space neither) to double the
    # effective vertical resolution - the same trick Omarchy's own
    # transcoder uses. The alpha channel (not color/threshold) is the mask,
    # since the SVG's logo shape is opaque on a transparent background.
    magick -background none "$FEDORA_SVG" -auto-orient \
      -alpha extract -alpha off -bordercolor black -border 1 -trim +repage \
      -resize 80x52 -threshold 50% -negate -compress none pbm:- 2>/dev/null \
      | awk '
        BEGIN { block["11"]="█"; block["10"]="▀"; block["01"]="▄"; block["00"]=" " }
        { sub(/#.*/, ""); for (i = 1; i <= NF; i++) token[++n] = $i }
        END {
          w = token[2]; h = token[3]; off = 4
          for (y = 0; y < h; y += 2) {
            line = ""
            for (x = 0; x < w; x++) {
              top = token[off + (y * w) + x]
              bottom = (y + 1 < h) ? token[off + ((y + 1) * w) + x] : 0
              line = line block[top bottom]
            }
            sub(/[ ]+$/, "", line)
            print line
          }
        }' > "$LOGO"
  fi
  # Fall back to the old typed-letter banner if ImageMagick or the Fedora
  # logo SVG isn't present (non-standard install) or the pipeline above
  # produced nothing.
  [ -s "$LOGO" ] || fastfetch --logo Fedora -s none > "$LOGO"
fi

# A plain fullscreen terminal only sees mouse movement as input if it typed
# something into stdin (it doesn't, by default) - polling the pointer
# position via xdotool is what actually catches "moved the mouse" as a
# dismiss trigger, not just keypresses.
mouse_pos() { xdotool getmouselocation --shell 2>/dev/null | awk -F= '/^X=/{x=$2} /^Y=/{y=$2} END{print x, y}'; }
LAST_POS="$(mouse_pos)"

while true; do
  # tte plays one effect to completion (several seconds) before returning,
  # so waiting for it to finish before checking for input meant dismissing
  # could take as long as the current animation - background it instead and
  # poll for either dismiss condition every 0.2s, killing it the instant
  # either fires, instead of waiting for it to finish on its own.
  #
  # tte's canvas defaults to the size of the input text itself (--canvas-*
  # -1), which is why effects were confined to a small box in the corner -
  # canvas-width/height 0 matches the actual terminal size instead, and the
  # anchor flags center both the canvas in the terminal and the logo within
  # that canvas, so effects (rain, fireworks, etc.) spread across the whole
  # screen rather than staying cramped around the logo's own bounding box.
  tte --random-effect --frame-rate 60 --input-file "$LOGO" \
    --canvas-width 0 --canvas-height 0 \
    --anchor-canvas c --anchor-text c &
  TTE_PID=$!

  while kill -0 "$TTE_PID" 2>/dev/null; do
    if read -t 0.2 -n 1 -s; then
      kill "$TTE_PID" 2>/dev/null
      exit 0
    fi
    CUR_POS="$(mouse_pos)"
    if [ -n "$CUR_POS" ] && [ "$CUR_POS" != "$LAST_POS" ]; then
      kill "$TTE_PID" 2>/dev/null
      exit 0
    fi
  done
done
