#!/usr/bin/env bash
# icon-theme switcher - the icon-theme counterpart of cursor-theme.sh.
#
# WHY THIS EXISTS: on a bare sway session there is no xsettings daemon, so
# GTK3/GTK4 apps read the icon theme from ~/.config/gtk-3.0/settings.ini and
# gtk-4.0/settings.ini - NOT from gsettings (gsettings only matters when a
# settings daemon bridges dconf into xsettings, which nothing here runs).
# lxappearance only writes ~/.gtkrc-2.0 (GTK2), so picking a theme there
# silently never reaches GTK3/4 apps. This script writes every location
# consistently in one shot: settings.ini (gtk-3 + gtk-4), ~/.gtkrc-2.0 and
# gsettings (for any future daemon/portal consumer).
#
# Usage:
#   icon-theme.sh          # prompts via rofi with the installed themes
#   icon-theme.sh <name>   # applies directly, no prompt
set -euo pipefail

# Real icon themes only: an index.theme with an Icon Theme/Name, from both
# /usr/share/icons and ~/.local/share/icons (user installs), deduped.
ALL_DIRS=("$HOME/.local/share/icons" "/usr/share/icons")
declare -A SEEN
THEMES=()
for d in "${ALL_DIRS[@]}"; do
  [ -d "$d" ] || continue
  for t in "$d"/*/; do
    name="$(basename "$t")"
    [ -f "$t/index.theme" ] && [ "${SEEN[$name]:-}" = "" ] || continue
    grep -q "^\[Icon Theme\]" "$t/index.theme" 2>/dev/null || continue
    SEEN[$name]=1
    THEMES+=("$name")
  done
done
if [ "${#THEMES[@]}" -eq 0 ]; then
  notify-send "Icon Theme" "No icon themes found in /usr/share/icons"
  exit 1
fi

CHOSEN="${1:-}"
if [ -z "$CHOSEN" ]; then
  CHOSEN="$(printf '%s\n' "${THEMES[@]}" | rofi -dmenu -i -p "Icon Theme" -theme ~/.config/rofi/current.rasi)"
  [ -n "$CHOSEN" ] || exit 0
fi

valid=0
for t in "${THEMES[@]}"; do [ "$t" = "$CHOSEN" ] && valid=1; done
if [ "$valid" -ne 1 ]; then
  notify-send "Icon Theme" "Unknown icon theme: $CHOSEN"
  exit 1
fi

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  if [ -f "$f" ] && grep -q '^gtk-icon-theme-name=' "$f"; then
    sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$CHOSEN/" "$f"
  elif [ -f "$f" ]; then
    sed -i "/^\[Settings\]/a gtk-icon-theme-name=$CHOSEN" "$f"
  else
    printf '[Settings]\ngtk-icon-theme-name=%s\n' "$CHOSEN" > "$f"
  fi
done

if [ -f "$HOME/.gtkrc-2.0" ] && grep -q '^gtk-icon-theme-name=' "$HOME/.gtkrc-2.0"; then
  sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=\"$CHOSEN\"/" "$HOME/.gtkrc-2.0"
else
  printf 'gtk-icon-theme-name="%s"\n' "$CHOSEN" >> "$HOME/.gtkrc-2.0"
fi

gsettings set org.gnome.desktop.interface icon-theme "$CHOSEN" 2>/dev/null || true

notify-send "Icon Theme" "Switched to $CHOSEN (newly started apps pick it up)"

# NOTE: already-running apps keep their loaded icon theme until restarted -
# same as every other GTK setting on a session without a settings daemon.
