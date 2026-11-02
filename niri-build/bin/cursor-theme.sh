#!/usr/bin/env bash
# Switches the mouse cursor theme between the 6 real Qogir variants installed
# during setup (the -Light variants are cursor-identical aliases, so not
# offered). Applies live: niri reads its pointer theme from the `cursor` block
# in config.kdl, so rewriting that line makes niri live-reload the new cursor;
# environment.d + GTK settings carry it to newly started apps.
#
# Usage:
#   cursor-theme.sh          # prompts via rofi
#   cursor-theme.sh <name>   # applies directly, no prompt
set -euo pipefail

THEMES=(Qogir Qogir-Dark Qogir-Manjaro Qogir-Manjaro-Dark Qogir-Ubuntu Qogir-Ubuntu-Dark)
NIRI_CONFIG="$HOME/.config/niri/config.kdl"

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

# Rewrite the xcursor-theme line in the niri config; niri watches the file and
# live-reloads the pointer on save (keeps the pick across reloads/relogin).
if [ -f "$NIRI_CONFIG" ]; then
  sed -i -E "s|(xcursor-theme)[[:space:]]+\"[^\"]*\"|\1 \"$CHOSEN\"|" "$NIRI_CONFIG"
fi

for gtk_settings in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  [ -f "$gtk_settings" ] && sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CHOSEN/" "$gtk_settings"
done
gsettings set org.gnome.desktop.interface cursor-theme "$CHOSEN" 2>/dev/null || true

# Make apps launched via systemd/dbus (portals, search providers) pick up the
# new theme without a re-login too.
systemctl --user set-environment XCURSOR_THEME="$CHOSEN" XCURSOR_SIZE=24 2>/dev/null || true

notify-send "Cursor Theme" "Switched to $CHOSEN"
