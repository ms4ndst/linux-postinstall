#!/usr/bin/env bash
# Region screenshot for the Sway rice. flameshot is X11-oriented and does NOT
# capture on sway/wlroots (its portal path hangs), so this uses the Wayland
# tools: slurp selects a region, grim captures it. If swappy (a flameshot-style
# annotation editor) is installed, the shot is piped to it for arrows/text/blur
# + save/copy; otherwise it's saved to ~/Pictures/Screenshots and copied to the
# clipboard directly. Pass `full` to capture the whole output instead of a region.
set -u
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
OUT="$DIR/shot-$(date +%Y%m%d-%H%M%S).png"

if [ "${1:-region}" = "full" ]; then
  GEO=""
else
  GEO="$(slurp 2>/dev/null)" || exit 0   # Escape/cancel -> exit quietly
  [ -n "$GEO" ] || exit 0
fi

if command -v swappy >/dev/null 2>&1; then
  # flameshot-style editor (save/copy from inside swappy's UI). Swappy's
  # Save button (or Ctrl+S) writes silently to its save_path - NO dialog
  # - which defaults to ~/Pictures/Screenshots. Detect the new file and
  # announce where it went, so the silent save is not a mystery.
  __before="$(ls -1 "$DIR" 2>/dev/null | sort)"
  if [ -n "$GEO" ]; then grim -g "$GEO" - | swappy -f -; else grim - | swappy -f -; fi
  __new="$(comm -13 <(printf '%s\n' "$__before") <(ls -1 "$DIR" 2>/dev/null | sort) | head -1)"
  [ -n "$__new" ] && notify-send "Screenshot" "Saved to $DIR/$__new"
else
  if [ -n "$GEO" ]; then grim -g "$GEO" "$OUT" || exit 1; else grim "$OUT" || exit 1; fi
  wl-copy --type image/png < "$OUT" 2>/dev/null || true
  command -v notify-send >/dev/null && notify-send "Screenshot" "Saved to $OUT and copied to clipboard"
fi
