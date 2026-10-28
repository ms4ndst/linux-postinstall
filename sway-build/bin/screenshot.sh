#!/usr/bin/env bash
# Region screenshot for the Sway rice. flameshot is X11-oriented and does NOT
# capture on sway/wlroots (its portal path hangs), so this uses the Wayland
# tools: slurp selects a region, grim captures it. If satty (a flameshot-style
# annotation editor, github.com/gabm/Satty) is installed, the shot is piped to
# it for arrows/text/blur + save/copy; satty's config.toml sets the save dir
# (~/Pictures/Screenshots), wl-copy as the copy command, and Enter = copy. If
# satty is missing, the shot is saved to ~/Pictures/Screenshots and copied to
# the clipboard directly. Pass `full` to capture the whole output.
set -u
# sway's exec PATH is bare (/usr/local/bin:/usr/bin) and omits ~/.local/bin,
# so a satty installed there (rather than system-wide) would be invisible and
# screenshot.sh would silently fall back to a plain save. Search both.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# The App Menu's "Screenshot Tool" item (screenshot-tool.sh) stores the chosen
# default in ~/.config/sway/screenshot-tool. "greenshot" hands the Print key
# to the full Wayland Greenshot (github.com/ms4ndst/greenshot_for_linux - its
# own region picker with magnifier, its own annotation editor, tray and
# save/copy/destination handling; `greenshot capture ...` starts the single
# instance on demand). Any other value (or no file yet) keeps this script's
# built-in grim+slurp pipeline below.
if grep -qx greenshot "$HOME/.config/sway/screenshot-tool" 2>/dev/null \
  && command -v greenshot >/dev/null 2>&1; then
  if [ "${1:-region}" = "full" ]; then
    exec greenshot capture fullscreen
  else
    exec greenshot capture region
  fi
fi

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"

if [ "${1:-region}" = "full" ]; then
  GEO=""
else
  GEO="$(slurp 2>/dev/null)" || exit 0   # Escape/cancel -> exit quietly
  [ -n "$GEO" ] || exit 0
fi

if command -v satty >/dev/null 2>&1; then
  # satty reads its save path (output-filename), copy command (wl-copy) and
  # key actions from ~/.config/satty/config.toml, so just pipe the capture in.
  # grim's ppm output is lossless and fast over the pipe (satty's own docs).
  if [ -n "$GEO" ]; then grim -g "$GEO" -t ppm - | satty --filename -; else grim -t ppm - | satty --filename -; fi
else
  OUT="$DIR/shot-$(date +%Y%m%d-%H%M%S).png"
  if [ -n "$GEO" ]; then grim -g "$GEO" "$OUT" || exit 1; else grim "$OUT" || exit 1; fi
  wl-copy --type image/png < "$OUT" 2>/dev/null || true
  command -v notify-send >/dev/null && notify-send "Screenshot" "Saved to $OUT and copied to clipboard"
fi
