#!/usr/bin/env bash
# Idle management for the Niri rice via swayidle (it speaks the wayland idle
# protocol niri implements). Timings:
#   - 20min (1200s): show the screensaver and lock (lock.sh --with-screensaver)
#   - 50min (3000s): power the displays off; power back on when activity resumes
#   - before sleep: lock first so resume lands on the lock screen
# niri does not re-run startup spawns on reload, but this is also callable
# directly, so single-instance it first.
# The idle context inherits niri's login-time PATH, which may not include
# ~/.local/bin - the tools the lock/screensaver chain needs live there, so
# re-add it before exec.
export PATH="$HOME/.local/bin:$PATH"
set -u
pkill -x swayidle 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swayidle >/dev/null 2>&1 || break; sleep 0.1; done

exec swayidle -w \
  timeout 1200 "$HOME/.local/bin/lock.sh --with-screensaver" \
  timeout 3000 'niri msg action power-off-monitors' \
    resume     'niri msg action power-on-monitors' \
  before-sleep "$HOME/.local/bin/lock.sh"
