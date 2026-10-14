#!/usr/bin/env bash
# Idle management for the Sway rice - replaces the i3 rice's xss-lock + `xset s
# 1200 dpms 3000 3000 3000` stack. Mirrors those timings exactly:
#   - 20min (1200s): show the screensaver and lock (lock.sh --with-screensaver,
#     which blanks immediately on lock via its own logic)
#   - 50min (3000s): power the displays off; power back on when activity resumes
#   - before sleep: lock first so resume lands on the lock screen
# Kept later than the screensaver mark on purpose (same reasoning as the i3
# rice: DPMS/display-power is a separate subsystem from the idle screensaver).
# exec_always re-runs this on reload, so single-instance it first.
set -u
pkill -x swayidle 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swayidle >/dev/null 2>&1 || break; sleep 0.1; done

exec swayidle -w \
  timeout 1200 "$HOME/.local/bin/lock.sh --with-screensaver" \
  timeout 3000 'swaymsg "output * power off"' \
    resume     'swaymsg "output * power on"' \
  before-sleep "$HOME/.local/bin/lock.sh"
