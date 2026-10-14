#!/usr/bin/env bash
# Switches the mouse cursor theme between the 6 real Qogir variants
# installed during setup (see the Qogir cursor theme step) - the -Light
# suffix variants aren't offered since they're cursor-identical aliases of
# their non-Light counterpart. Applies live: sway's own root cursor
# updates immediately via `swaymsg seat seat0 xcursor_theme`, the sway
# config's include file is rewritten so a reload keeps the pick, and
# environment.d + GTK settings carry it to newly started apps.
#
# Usage:
#   cursor-theme.sh          # prompts via rofi
#   cursor-theme.sh <name>   # applies directly, no prompt
set -euo pipefail

THEMES=(Qogir Qogir-Dark Qogir-Manjaro Qogir-Manjaro-Dark Qogir-Ubuntu Qogir-Ubuntu-Dark)

CHOSEN="${1:-}"
if [ -z "$CHOSEN" ]; then
  CHOSEN="$(printf '%s\n' "${THEMES[@]}" | rofi -dmenu -i -p "Cursor Theme" -theme ~/.config/rofi/current.rasi)"
  [ -z "$CHOSEN" ] && exit 0
fi

valid=0
for t in "${THEMES[@]}"; do [ "$t" = "$CHOSEN" ] && valid=1; done
if [ "$valid" -ne 1 ]; then
  notify-send "Cursor Theme" "Unknown theme: $CHOSEN"
  exit 1
fi

mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/cursor-theme.conf" <<CONF
XCURSOR_THEME=$CHOSEN
XCURSOR_SIZE=24
CONF

# Sway, not X11: the compositor's own pointer comes from the seat's
# xcursor_theme setting, which the main sway config re-applies from this
# include file on every reload (the old hardcoded "xcursor_theme Adwaita"
# line in the config re-pinned Adwaita on each reload, silently undoing
# the switch).
mkdir -p "$HOME/.config/sway"
printf 'seat seat0 xcursor_theme %s 24\n' "$CHOSEN" > "$HOME/.config/sway/cursor-theme.conf"

for gtk_settings in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  [ -f "$gtk_settings" ] && sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CHOSEN/" "$gtk_settings"
done
gsettings set org.gnome.desktop.interface cursor-theme "$CHOSEN" 2>/dev/null || true

# Apply live: sway's seat command retints the pointer immediately, no
# reload needed; reload stays as the belt-and-braces path via the include
# file above.
swaymsg "seat seat0 xcursor_theme $CHOSEN 24" >/dev/null 2>&1 || true
swaymsg reload >/dev/null 2>&1 || true
# Make apps launched via systemd/dbus (portals, search providers) pick up
# the new theme without a re-login too.
systemctl --user set-environment XCURSOR_THEME="$CHOSEN" XCURSOR_SIZE=24 2>/dev/null || true

notify-send "Cursor Theme" "Switched to $CHOSEN"
