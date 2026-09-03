#!/usr/bin/env bash
# Set the screensaver logo (~/.config/screensaver/logo.txt) from either
# typed text or an image file - both converted to the same solid Unicode
# half-block art (█▀▄) the Fedora logo uses in screensaver.sh. Matches
# Omarchy's own screensaver branding (`omarchy branding screensaver
# text|image`), just as one plain script instead of a subcommand.
#
# Usage:
#   set-screensaver-text.sh                  # prompts for text or an image path
#   set-screensaver-text.sh "some text"      # renders that text directly
#   set-screensaver-text.sh path/to/logo.png # converts that image directly (png/svg/jpg/...)
#
# Image mode is a monochrome silhouette render (1-bit threshold, no
# grayscale/color survives) - great for logos/icons/simple line art, same
# as Omarchy's own transcoder; a detailed photo will come out as a crude
# blob, not something with real detail. Assumes a dark subject on a light
# background (or real transparency, like an icon's alpha channel) - there's
# no --invert equivalent here for a light-subject-on-dark-photo yet.
#
# Overwrites $LOGO every run - that's intentional here (unlike
# screensaver.sh's own lazy Fedora-logo generation, which only writes if
# missing).
set -euo pipefail

LOGO="$HOME/.config/screensaver/logo.txt"
FONT="/usr/share/fonts/truetype/nerd-fonts/JetBrainsMonoNerdFont-Bold.ttf"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick (magick) is not installed." >&2
  echo "  Ubuntu/Debian: sudo apt install imagemagick" >&2
  echo "  Fedora:        sudo dnf install ImageMagick" >&2
  echo "  Arch:          sudo pacman -S imagemagick" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOGO")"

INPUT="${1:-}"
if [ -z "$INPUT" ]; then
  read -r -p "Screensaver text (or a path to an image): " INPUT
fi
if [ -z "$INPUT" ]; then
  echo "Nothing entered, leaving $LOGO unchanged." >&2
  exit 1
fi

TMP_PNG="$(mktemp --suffix=.png)"
trap 'rm -f "$TMP_PNG"' EXIT

# Two source pixel rows -> one terminal row, using a half-block glyph
# (█ both on, ▀ top only, ▄ bottom only, space neither) - identical to the
# conversion screensaver.sh runs on the Fedora logo SVG.
to_block_art() {
  awk '
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
    }'
}

if [ -f "$INPUT" ]; then
  # Image mode. Real transparency (an icon/logo on a clear background) is
  # the mask if present - dark pixels are already threshold-negated
  # correctly the same way the Fedora SVG is in screensaver.sh. Otherwise
  # (a flattened PNG/JPG/photo with no alpha channel) fall back to
  # grayscale + threshold with NO negate, since dark-subject-on-light-
  # background needs the opposite polarity from the alpha-mask case -
  # verified against a real black-shape-on-white test image, not assumed.
  read -r ALPHA_MIN ALPHA_MAX <<<"$(magick -background none "$INPUT" -alpha extract -format '%[fx:minima] %[fx:maxima]' info: 2>/dev/null)"
  USE_ALPHA=false
  if awk -v min="${ALPHA_MIN:-1}" -v max="${ALPHA_MAX:-0}" 'BEGIN { exit !(min < 0.999 && max > min) }'; then
    USE_ALPHA=true
  fi
  if [ "$USE_ALPHA" = true ]; then
    magick -background none "$INPUT" -auto-orient \
      -alpha extract -alpha off -bordercolor black -border 1 -trim +repage \
      -resize 80x52 -threshold 50% -negate -compress none pbm:- 2>/dev/null \
      | to_block_art >"$LOGO"
  else
    magick -background none "$INPUT" -auto-orient \
      -alpha remove -alpha off -colorspace Gray \
      -bordercolor black -border 1 -trim +repage \
      -resize 80x52 -threshold 50% -compress none pbm:- 2>/dev/null \
      | to_block_art >"$LOGO"
  fi
else
  # Text mode. Point size is tuned so short phrases end up roughly the same
  # visual scale as the block Fedora logo (which targets an 80-column
  # canvas) once resized below - longer text just shrinks further to fit,
  # same tradeoff arbitrarily-sized source images have above.
  FONT_ARGS=()
  [ -f "$FONT" ] && FONT_ARGS=(-font "$FONT") # else ImageMagick's own default
  magick -background none -fill white "${FONT_ARGS[@]}" -pointsize 120 \
    label:"$INPUT" "$TMP_PNG"
  magick "$TMP_PNG" -auto-orient \
    -alpha extract -alpha off -bordercolor black -border 1 -trim +repage \
    -resize 80x52 -threshold 50% -negate -compress none pbm:- 2>/dev/null \
    | to_block_art >"$LOGO"
fi

if [ ! -s "$LOGO" ]; then
  echo "Block-art conversion produced nothing." >&2
  exit 1
fi

echo
echo "Preview:"
cat "$LOGO"
echo
echo "Saved to $LOGO — screensaver.sh will pick it up on next run."
