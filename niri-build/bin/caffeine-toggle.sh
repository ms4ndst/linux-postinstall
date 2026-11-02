#!/usr/bin/env bash
# "Caffeine" toggle - no packaged equivalent exists for Fedora (neither dnf
# nor Flathub carry one), so this is a small hand-rolled stand-in for the
# classic GNOME Caffeine extension: click to inhibit screen-blank/lock/sleep,
# click again to release. Nothing changes system-wide while it's off.
#
# Two things happen while active:
#   1. swayidle is stopped entirely, so no idle timeout can blank/lock the
#      display while caffeinated.
#   2. A backgrounded `systemd-inhibit` holds idle/sleep/lid-switch locks so
#      systemd-logind won't suspend even on lid close, matching what the
#      screensaver-based inhibition alone wouldn't cover.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
# Toggling OFF must restore the real idle lock/DPMS timing, not a stale
# default: swayidle-launch.sh re-arms exactly what a fresh login gets.

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")" 2>/dev/null
  rm -f "$PIDFILE"
  # restart swayidle to restore idle lock/DPMS timers
  "$HOME/.local/bin/swayidle-launch.sh" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  notify-send -h string:x-dunst-stack-tag:caffeine "Caffeine: off" "Screen lock/sleep restored"
else
  # stop swayidle entirely so nothing blanks/locks while caffeinated
  pkill -x swayidle 2>/dev/null || true
  systemd-inhibit --what=idle:sleep:handle-lid-switch --who="sway-caffeine" \
      --why="User requested via caffeine-toggle.sh" --mode=block \
      sleep infinity &
  disown
  echo "$!" > "$PIDFILE"
  notify-send -h string:x-dunst-stack-tag:caffeine "Caffeine: on" "Screen lock/sleep inhibited until toggled off"
fi
