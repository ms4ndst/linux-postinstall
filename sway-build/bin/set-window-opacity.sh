#!/usr/bin/env bash
# Set global window transparency for the sway rice. Rewrites the catch-all
# `for_window [app_id|class=".*"] opacity` lines in ~/.config/sway/config so the
# value persists, and applies it live to every open window via swaymsg criteria.
# No `swaymsg reload` is issued on purpose - reload re-runs the exec_always lines
# (waybar, swaybg, swayidle) and would flash the bar/wallpaper. Existing windows
# update instantly; windows opened later in THIS session keep the previous value
# until the next sway restart, after which everything is uniform again.
# Reachable from the App Menu ("Set Window Transparency") and bindable directly.
#   set-window-opacity.sh            # rofi picker
#   set-window-opacity.sh <percent>  # set directly, no prompt (100 = opaque)
set -u
export PATH="$HOME/.local/bin:$PATH"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/sway/config"
ROFI_THEME="$HOME/.config/rofi/current.rasi"

[ -r "$CONF" ] || { notify-send "Window opacity" "sway config not found" 2>/dev/null; exit 1; }

# Current opacity (default 1.00 if no line yet) -> percent for the prompt hint.
cur_dec=$(grep -oE 'for_window \[app_id="\.\*"\] opacity [0-9.]+' "$CONF" \
            | grep -oE '[0-9.]+$' | head -n1)
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

# Persist to the config (both matchers) for future sessions / new windows.
if grep -qE 'for_window \[(app_id|class)="\.\*"\] opacity [0-9.]+' "$CONF"; then
  tmp=$(mktemp) || exit 1
  sed -E 's|(for_window \[(app_id|class)="\.\*"\] opacity )[0-9.]+|\1'"$dec"'|' "$CONF" > "$tmp"
  cat "$tmp" > "$CONF"   # in-place rewrite (cp is aliased to cp -i)
  rm -f "$tmp"
fi

# Apply to every currently-open window right now (no reload, so no bar flash).
swaymsg "[app_id=\".*\"] opacity $dec" >/dev/null 2>&1 || true
swaymsg "[class=\".*\"] opacity $dec" >/dev/null 2>&1 || true
# Re-assert the opaque exclusions: Chromium/Electron apps (VSCode, Vivaldi) paint
# an opaque buffer, so the blanket apply above only tints them (accent/pink wash).
# Keep this list in sync with the `opacity 1.0` for_window rules in the config.
swaymsg '[app_id="^(com\.microsoft\.VSCode|vivaldi.*)$"] opacity 1.0' >/dev/null 2>&1 || true
swaymsg '[class="^([Cc]ode|[Vv]ivaldi.*)$"] opacity 1.0' >/dev/null 2>&1 || true

notify-send -h string:x-dunst-stack-tag:opacity \
  "Window opacity" "Set to ${pct}% (100 = opaque)" 2>/dev/null || true
