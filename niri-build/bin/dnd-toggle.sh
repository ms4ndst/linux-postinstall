#!/usr/bin/env bash
# Do Not Disturb toggle for dunst. Notify BEFORE pausing (a notification
# sent after wouldn't show - that's the whole point of pausing) rather than
# after, so the confirmation is actually visible either way.
#
# Calendar/task reminders go through dunst too (~/.local/bin/calendar-
# reminder-daemon.py fires them as regular notify-send notifications,
# replacing evolution-alarm-notify's own separate GTK popup window, which
# is disabled entirely) so dunst's own pause state is already the single
# thing that needs toggling - no separate gsettings flip needed anymore.
if [ "$(dunstctl is-paused)" = "true" ]; then
  dunstctl set-paused false
  notify-send -h string:x-dunst-stack-tag:dnd "Do Not Disturb: off" "Notifications resumed"
else
  notify-send -h string:x-dunst-stack-tag:dnd "Do Not Disturb: on" "Notifications silenced until toggled off"
  dunstctl set-paused true
fi
# Flip the waybar DND indicator (custom/notification-silencing-indicator
# listens on signal 10) the moment the state changes.
pkill -SIGRTMIN+10 waybar 2>/dev/null || true
