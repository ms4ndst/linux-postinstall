#!/usr/bin/env bash
# Rofi-based wifi picker - scans nearby networks and connects, unlike
# nm-connection-editor (which only edits already-saved connection
# profiles, and has no "browse nearby networks" view at all). Reuses
# current.rasi, the same rofi theme ~/.local/bin/waybar-theme.sh already
# keeps in sync with the active desktop theme, so this menu retints for
# free instead of needing its own GTK-theming project the way
# nm-connection-editor itself would (a real, ~6000-line, 156-color GTK3
# stylesheet - a much bigger job for a rarely-opened settings dialog than
# reusing rofi's own already-switchable theme here).
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/current.rasi"

# Best-effort rescan - a scan already in progress (e.g. NetworkManager's
# own periodic one) makes this fail with a harmless "Scanning not allowed
# immediately following previous scan" error; the list below just falls
# back to whatever NetworkManager already has cached from that scan.
nmcli device wifi rescan >/dev/null 2>&1 || true

# IN-USE/SSID/SECURITY/SIGNAL, sorted by signal descending (nmcli's own
# default sort) - dedupe by SSID keeping the first (=strongest) row seen,
# since the same network's multiple access points/bands all share one
# SSID and only need one menu entry. Skip blank SSIDs (hidden networks -
# nothing meaningful to connect to by name).
mapfile -t ROWS < <(
  nmcli -t -f IN-USE,SSID,SECURITY,SIGNAL device wifi list 2>/dev/null \
    | awk -F: '
        $2 == "" { next }
        !seen[$2]++ { print }
      '
)

if [ "${#ROWS[@]}" -eq 0 ]; then
  notify-send "Wi-Fi" "No networks found."
  exit 0
fi

declare -A SECURITY_OF SIGNAL_OF
MENU=""
CONNECTED_SSID=""
for row in "${ROWS[@]}"; do
  IFS=':' read -r inuse ssid security signal <<< "$row"
  SECURITY_OF["$ssid"]="$security"
  SIGNAL_OF["$ssid"]="$signal"
  if [ "$inuse" = "*" ]; then
    CONNECTED_SSID="$ssid"
    MENU+="${ssid} (connected)"$'\n'
  elif [ -z "$security" ] || [ "$security" = "--" ]; then
    MENU+="${ssid}"$'\n'
  else
    MENU+="${ssid} 󰌾"$'\n'
  fi
done

CHOSEN_LINE="$(printf '%s' "$MENU" | rofi -dmenu -i -p "Wi-Fi" -theme "$ROFI_THEME")"
[ -z "$CHOSEN_LINE" ] && exit 0

# Strip the decorations added above to recover the real SSID for lookup.
SSID="${CHOSEN_LINE%% 󰌾}"
SSID="${SSID%% (connected)}"

if [ "$SSID" = "$CONNECTED_SSID" ]; then
  notify-send "Wi-Fi" "Already connected to \"$SSID\"."
  exit 0
fi

# A saved connection profile (from a previous successful connect) already
# has whatever credentials it needs - reuse it directly rather than
# prompting for a password NetworkManager doesn't actually need again.
if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$SSID"; then
  if nmcli connection up "$SSID" >/dev/null 2>&1; then
    notify-send "Wi-Fi" "Connected to \"$SSID\"."
  else
    notify-send "Wi-Fi" "Failed to connect to \"$SSID\"."
  fi
  exit 0
fi

SECURITY="${SECURITY_OF[$SSID]:-}"
if [ -z "$SECURITY" ] || [ "$SECURITY" = "--" ]; then
  if nmcli device wifi connect "$SSID" >/dev/null 2>&1; then
    notify-send "Wi-Fi" "Connected to \"$SSID\"."
  else
    notify-send "Wi-Fi" "Failed to connect to \"$SSID\"."
  fi
  exit 0
fi

PASSWORD="$(rofi -dmenu -password -i -p "Password for $SSID" -theme "$ROFI_THEME")"
[ -z "$PASSWORD" ] && exit 0

if nmcli device wifi connect "$SSID" password "$PASSWORD" >/dev/null 2>&1; then
  notify-send "Wi-Fi" "Connected to \"$SSID\"."
else
  notify-send "Wi-Fi" "Failed to connect to \"$SSID\" - wrong password?"
fi
