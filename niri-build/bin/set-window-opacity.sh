#!/usr/bin/env bash
# Set global window transparency for the niri rice. Rewrites the `opacity` line
# in the catch-all window-rule of ~/.config/niri/config.kdl; niri hot-reloads on
# save and applies the new value to every window (existing + new) immediately -
# no re-login. Reachable from the App Menu ("Set Window Transparency") and
# bindable directly.
#   set-window-opacity.sh            # rofi picker
#   set-window-opacity.sh <percent>  # set directly, no prompt (100 = opaque)
set -u
export PATH="$HOME/.local/bin:$PATH"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
ROFI_THEME="$HOME/.config/rofi/current.rasi"

[ -r "$CONF" ] || { notify-send "Window opacity" "niri config not found" 2>/dev/null; exit 1; }

# Current opacity (default 1.00 if no line yet) -> percent for the prompt hint.
cur_dec=$(grep -oE '^[[:space:]]*opacity[[:space:]]+[0-9.]+' "$CONF" \
            | grep -oE '[0-9.]+' | head -n1)
[ -z "$cur_dec" ] && cur_dec=1.0
cur_pct=$(awk "BEGIN{printf \"%d\", ($cur_dec*100)+0.5}")

sanitize_pct() {
  local v; v=$(printf '%s' "$1" | tr -dc '0-9' | head -c 3)
  [ -z "$v" ] && { printf ''; return; }
  v=$((10#$v)); [ "$v" -gt 100 ] && v=100; printf '%s' "$v"
}

if [ "$#" -ge 1 ]; then
  pct=$(sanitize_pct "$1")
  [ -z "$pct" ] && { echo "usage: $(basename "$0") <percent 0-100>  (100 = opaque)" >&2; exit 1; }
else
  OPTS=$'  100%  (opaque / off)\n  98%\n  95%\n  92%\n  90%\n  85%\n  80%\n  Custom…'
  CHOSEN=$(printf '%b' "$OPTS" | rofi -dmenu -i -p "Window opacity" \
            -mesg "Transparency applied to every window. Currently: ${cur_pct}% (100 = opaque)." \
            -theme "$ROFI_THEME")
  [ -z "$CHOSEN" ] && exit 0
  case "$CHOSEN" in
    *"Custom"*)
      raw=$(printf '' | rofi -dmenu -p "Opacity % (0-100)" -theme "$ROFI_THEME")
      pct=$(sanitize_pct "$raw")
      [ -z "$pct" ] && exit 0
      ;;
    *) pct=$(sanitize_pct "$CHOSEN") ;;
  esac
fi

dec=$(awk "BEGIN{printf \"%.2f\", $pct/100}")

# Edit a temp copy, validate it, then swap it in (the swap is what niri reloads).
# The temp MUST live next to the real config: niri's `include "themes/..."` is a
# RELATIVE path resolved against the config's own directory, so validating a copy
# in /tmp would fail looking for /tmp/themes/current.kdl. A leading dot keeps the
# temp out of niri's way (it only loads config.kdl + its includes).
tmp=$(mktemp "$(dirname "$CONF")/.set-opacity.XXXXXX") || exit 1
if grep -qE '^[[:space:]]*opacity[[:space:]]+[0-9.]+' "$CONF"; then
  sed -E 's|^([[:space:]]*)opacity[[:space:]]+[0-9.]+.*|\1opacity '"$dec"'|' "$CONF" > "$tmp"
else
  # No opacity line yet: add one inside the catch-all rule, after clip-to-geometry.
  sed 's|^\([[:space:]]*\)clip-to-geometry true|&\n\1opacity '"$dec"'|' "$CONF" > "$tmp"
fi

if niri validate --config "$tmp" >/dev/null 2>&1; then
  cat "$tmp" > "$CONF"   # in-place rewrite (cp is aliased to cp -i); niri hot-reloads
  rm -f "$tmp"
  notify-send -h string:x-dunst-stack-tag:opacity \
    "Window opacity" "Set to ${pct}% (100 = opaque)" 2>/dev/null || true
else
  rm -f "$tmp"
  notify-send -h string:x-dunst-stack-tag:opacity \
    "Window opacity" "Change rejected (config would be invalid); nothing changed" 2>/dev/null || true
  exit 1
fi
