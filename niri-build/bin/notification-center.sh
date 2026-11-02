#!/usr/bin/env bash
# Rofi-based browser for dunst's notification history. dunst itself has no
# "list view" of its own - dunstctl history-pop only recalls the single
# latest notification at a time, re-displayed as a live popup - so this
# parses `dunstctl history`'s real JSON (confirmed structure: .data[0] is
# an array of notification objects, already newest-first) into a rofi
# list. Selecting an entry removes just that one from history
# (dunstctl history-rm); a "Clear all" entry at the top wipes everything.
set -euo pipefail

HIST_JSON="$(dunstctl history)"
mapfile -t IDS < <(jq -r '.data[0][].id.data' <<<"$HIST_JSON")

if [ "${#IDS[@]}" -eq 0 ]; then
  notify-send "Notification Center" "No notification history"
  exit 0
fi

mapfile -t LABELS < <(jq -r '.data[0][] | "\(.appname.data): \(.summary.data)"' <<<"$HIST_JSON")

MENU="Clear all (${#IDS[@]})"
for l in "${LABELS[@]}"; do
  MENU+=$'\n'"$l"
done

CHOSEN_IDX="$(printf '%s\n' "$MENU" | rofi -dmenu -i -p "Notifications" -format i -theme ~/.config/rofi/current.rasi)"
[ -z "$CHOSEN_IDX" ] && exit 0

if [ "$CHOSEN_IDX" -eq 0 ]; then
  dunstctl history-clear
else
  dunstctl history-rm "${IDS[$((CHOSEN_IDX - 1))]}"
fi
