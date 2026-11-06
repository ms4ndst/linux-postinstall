#!/usr/bin/env bash
# Set the idle screensaver/lock timeout. Writes the chosen number of minutes to
# ~/.config/rice/screensaver-timeout (0 = never) and re-runs swayidle-launch.sh
# so the new timeout applies immediately - no re-login needed. Reachable from
# the App Menu ("Set Screensaver Timeout") and bindable directly.
#   set-screensaver-timeout.sh            # rofi picker
#   set-screensaver-timeout.sh <minutes>  # set directly, no prompt (0 = never)
set -u
export PATH="$HOME/.local/bin:$PATH"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rice"
CONF="$CONF_DIR/screensaver-timeout"
ROFI_THEME="$HOME/.config/rofi/current.rasi"

# Current value (default 20) for the prompt hint.
cur=20
if [ -r "$CONF" ]; then
  v=$(tr -dc '0-9' < "$CONF" | head -c 4)
  [ -n "$v" ] && cur=$((10#$v))
fi

sanitize() { printf '%s' "$1" | tr -dc '0-9' | head -c 4; }

if [ "$#" -ge 1 ]; then
  # Non-interactive: minutes given as an argument.
  mins=$(sanitize "$1")
  [ -z "$mins" ] && { echo "usage: $(basename "$0") <minutes>  (0 = never)" >&2; exit 1; }
  mins=$((10#$mins))
else
  OPTS=$'  1 minute\n  2 minutes\n  5 minutes\n  10 minutes\n  15 minutes\n  20 minutes\n  30 minutes\n  45 minutes\n  1 hour\n  Never (disable)\n  Custom…'
  CHOSEN=$(printf '%b' "$OPTS" | rofi -dmenu -i -p "Screensaver after" \
            -mesg "Idle time before the screensaver locks. Currently: ${cur} min (0 = never)." \
            -theme "$ROFI_THEME")
  [ -z "$CHOSEN" ] && exit 0
  case "$CHOSEN" in
    *"Never"*)  mins=0 ;;
    *"1 hour"*) mins=60 ;;
    *"Custom"*)
      raw=$(printf '' | rofi -dmenu -p "Minutes (0 = never)" -theme "$ROFI_THEME")
      raw=$(sanitize "$raw")
      [ -z "$raw" ] && exit 0
      mins=$((10#$raw))
      ;;
    *) raw=$(sanitize "$CHOSEN"); mins=$((10#$raw)) ;;
  esac
fi

mkdir -p "$CONF_DIR"
printf '%s\n' "$mins" > "$CONF"

# Re-arm swayidle so the new timeout takes effect now (it re-reads the file).
if [ -x "$HOME/.local/bin/swayidle-launch.sh" ]; then
  "$HOME/.local/bin/swayidle-launch.sh" >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

if [ "$mins" -gt 0 ]; then
  notify-send -h string:x-dunst-stack-tag:screensaver \
    "Screensaver" "Locks after ${mins} min idle" 2>/dev/null || true
else
  notify-send -h string:x-dunst-stack-tag:screensaver \
    "Screensaver" "Idle auto-lock disabled" 2>/dev/null || true
fi
