#!/usr/bin/env bash
# Idle management for the Niri rice via swayidle (it speaks the wayland idle
# protocol niri implements). Timings:
#   - screensaver+lock after SS_MIN minutes idle (lock.sh --with-screensaver)
#   - power the displays off 30min after that; power back on when activity resumes
#   - before sleep: lock first so resume lands on the lock screen
# SS_MIN is read from ~/.config/rice/screensaver-timeout (a single integer, in
# minutes; 0 = never auto-lock). Default 20 when the file is missing/empty.
# Change it from the App Menu ("Set Screensaver Timeout") or
# ~/.local/bin/set-screensaver-timeout.sh, which rewrites that file and re-runs
# this script to apply the new timeout immediately.
# niri does not re-run startup spawns on reload, but this is also callable
# directly, so single-instance it first.
# The idle context inherits niri's login-time PATH, which may not include
# ~/.local/bin - the tools the lock/screensaver chain needs live there, so
# re-add it before exec.
export PATH="$HOME/.local/bin:$PATH"
set -u

# --- read the configurable screensaver timeout (minutes) ---
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/rice/screensaver-timeout"
SS_MIN=20
if [ -r "$CONF" ]; then
  v=$(tr -dc '0-9' < "$CONF" | head -c 4)
  [ -n "$v" ] && SS_MIN=$((10#$v))
fi

pkill -x swayidle 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swayidle >/dev/null 2>&1 || break; sleep 0.1; done

# Build the argument list so a timeout of 0 cleanly disables the screensaver/
# lock while still keeping display power-off and lock-before-sleep.
args=( -w )
if [ "$SS_MIN" -gt 0 ]; then
  args+=( timeout "$((SS_MIN * 60))" "$HOME/.local/bin/lock.sh --with-screensaver" )
  off=$(( (SS_MIN + 30) * 60 ))
else
  off=3000
fi
args+=( timeout "$off" 'niri msg action power-off-monitors' \
          resume 'niri msg action power-on-monitors' )
args+=( before-sleep "$HOME/.local/bin/lock.sh" )

exec swayidle "${args[@]}"
