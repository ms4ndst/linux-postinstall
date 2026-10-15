#!/usr/bin/env bash
# Sway rice lock screen (swaylock) in the Catppuccin Mocha indicator scheme
# (github.com/catppuccin/swaylock, themes/mocha.conf): subtle dark ring at
# rest, green keypress dots, blue while verifying, maroon on wrong password.
# All colors live in ~/.config/swaylock/config, seeded by the installer, and
# swaylock reads them via -C - so both branches below share one scheme.
# Guard against overlapping invocations: swayidle calls this on idle/sleep AND
# Mod+l calls it directly - flock closes the TOCTOU gap so a second swaylock
# never starts on top of one already holding the session.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lock.sh.lock"
flock -n 9 || exit 0

LOCKCFG="$HOME/.config/swaylock/config"

# --with-screensaver (passed by swayidle's idle timeout and the Mod+l keybind)
# runs the block-art screensaver first; any keypress dismisses it straight into
# the real password lock below - dismissing early does NOT cancel the lock.
if [ "$1" = "--with-screensaver" ]; then
  kitty --class Screensaver -e ~/.local/bin/screensaver.sh
fi

# NOTE: do NOT blank the displays with an explicit sway power-off:
# `swaymsg "output * power off"` has NO wake-on-input (only swayidle's
# resume hook re-powers displays, and it only fires for swayidle's own
# 50-min display timeout) - locking would leave a black screen with no
# way back in. swayidle's 50-min timeout (with its resume hook) handles
# display power-off; swaylock itself covers the visual lock.

# swaylock-effects (the fork with --screenshots/--effect-* effects and a
# live --clock) takes priority when available.
if swaylock --help 2>&1 | grep -q -- "--effect-blur"; then
  # Cycle a different look each lock - all layered over a live screenshot of
  # the screen being locked (swaylock-effects applies its --effect-* flags
  # on top of the previous, so combos stack). NOTE: this fork (jirutka
  # v1.7.0.0) has no --time-color/--date-color - the clock renders in the
  # config's text-color (Catppuccin cdd6f4) instead of the preview's
  # lavender; a deliberate trade for a maintained binary.
  case $((RANDOM % 4)) in
    0) EFFECTS=(--effect-blur 8x3 --effect-vignette 0.4:0.4) ;;
    1) EFFECTS=(--effect-pixelate 12 --effect-blur 2x2 --effect-vignette 0.4:0.4) ;;
    2) EFFECTS=(--effect-greyscale --effect-blur 10x4 --effect-vignette 0.5:0.5) ;;
    3) EFFECTS=(--effect-scale 0.75 --effect-blur 6x3 --effect-vignette 0.4:0.4) ;;
  esac
  swaylock -C "$LOCKCFG" \
    --screenshots \
    "${EFFECTS[@]}" \
    --clock \
    --timestr '%H:%M:%S' \
    --datestr '%a, %d/%m/%Y' &
  LOCK_PID=$!
  wait "$LOCK_PID"
elif command -v swaylock >/dev/null 2>&1; then
  # Plain swaylock: this IS the catppuccin/swaylock preview look - a flat
  # Mocha background (color=1e1e2e from the config) with the subtle
  # indicator and its state colors. Nothing else; the screenshot on the
  # project page is exactly this command.
  swaylock -C "$LOCKCFG"
else
  echo "lock.sh: swaylock is not installed" >&2
  exit 1
fi
