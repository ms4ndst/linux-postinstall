#!/usr/bin/env bash
# Sway rice lock screen (swaylock), with a random Mocha accent per lock.
# Guard against overlapping invocations: swayidle calls this on idle/sleep AND
# Mod+l calls it directly - flock closes the TOCTOU gap so a second swaylock
# never starts on top of one already holding the session.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lock.sh.lock"
flock -n 9 || exit 0

# --with-screensaver (passed by swayidle's idle timeout and the Mod+l keybind)
# runs the block-art screensaver first; any keypress dismisses it straight into
# the real password lock below - dismissing early does NOT cancel the lock.
if [ "$1" = "--with-screensaver" ]; then
  kitty --class Screensaver -e ~/.local/bin/screensaver.sh
fi

# A different Catppuccin Mocha accent for the ring every lock - cosmetic variety
# only; the ver/wrong colors below stay fixed so feedback always reads the same.
# The keypress highlight picks the accent half the array away (opposite-ish hue).
ACCENTS=(f5e0dc f2cdcd f5c2e7 cba6f7 f38ba8 eba0ac fab387 f9e2af a6e3a1 94e2d5 89dceb 74c7ec 89b4fa b4befe)
ACCENT_IDX=$((RANDOM % ${#ACCENTS[@]}))

# Prefer the ACTIVE desktop theme's own accent for the ring (read straight
# from the borders file waybar-theme.sh keeps in step with the theme pick) -
# the lock then always matches whatever theme is running. Falls back to a
# random Mocha accent when it can't be read.
ACCENT="$(awk '/^client\.focused /{print $2; exit}' \
           "$HOME/.config/sway/current-borders.conf" 2>/dev/null || true)"
case "$ACCENT" in
  \#*) ACCENT="${ACCENT#\#}" ;;
  *) ACCENT="${ACCENTS[$ACCENT_IDX]}" ;;
esac
KEYHL="${ACCENTS[$(( (ACCENT_IDX + 7) % ${#ACCENTS[@]} ))]}"

# NOTE: do NOT blank the displays with an explicit sway power-off:
# `swaymsg "output * power off"` has NO wake-on-input (only swayidle's
# resume hook re-powers displays, and it only fires for swayidle's own
# 50-min display timeout) - locking would leave a black screen with no
# way back in. swayidle's 50-min timeout (with its resume hook) handles
# display power-off; swaylock itself covers the visual lock.

# swaylock-effects adds --screenshots/--effect-blur; plain swaylock lacks
# them. Detect by grepping --help for effect-blur (swaylock lists its flags
# in --help). NOTE: swaylock has no custom greeter/wrong-text flags, so no
# custom lock messages here.
if swaylock --help 2>&1 | grep -q -- "--effect-blur"; then
  # Cycle a different look each lock - all layered over a live screenshot of
  # the screen being locked (one of swaylock-effects' effects is applied on
  # top of the previous, so combos stack).
  case $((RANDOM % 4)) in
    0) EFFECTS=(--effect-blur 8x3 --effect-vignette 0.4:0.4) ;;
    1) EFFECTS=(--effect-pixelate 12 --effect-blur 2x2 --effect-vignette 0.4:0.4) ;;
    2) EFFECTS=(--effect-greyscale --effect-blur 10x4 --effect-vignette 0.5:0.5) ;;
    3) EFFECTS=(--effect-scale 0.75 --effect-blur 6x3 --effect-vignette 0.4:0.4) ;;
  esac
  swaylock \
    --screenshots \
    "${EFFECTS[@]}" \
    --clock \
    --timestr '%H:%M' \
    --datestr '%A, %d %B' \
    --font 'JetBrainsMono Nerd Font' \
    --indicator \
    --indicator-radius 110 \
    --indicator-thickness 14 \
    --inside-color 1e1e2ecc \
    --ring-color "${ACCENT}ff" \
    --line-uses-ring \
    --key-hl-color "${KEYHL}ff" \
    --bs-hl-color f38ba8ff \
    --ring-ver-color f9e2afff \
    --inside-ver-color 1e1e2ecc \
    --ring-wrong-color f38ba8ff \
    --inside-wrong-color 1e1e2ecc \
    --separator-color 313244ff \
    --text-color cdd6f4ff \
    --text-ver-color cdd6f4ff \
    --text-wrong-color f38ba8ff \
    --text-clear-color cdd6f4ff \
    --text-caps-lock-color f9e2afff &
  LOCK_PID=$!
  wait "$LOCK_PID"
elif command -v swaylock >/dev/null 2>&1; then
  swaylock -c 1e1e2e \
    --inside-color 1e1e2ecc \
    --ring-color "${ACCENT}ff" \
    --key-hl-color "${KEYHL}ff" \
    --ring-ver-color f9e2afff \
    --ring-wrong-color f38ba8ff \
    --text-color cdd6f4ff &
  LOCK_PID=$!
  wait "$LOCK_PID"
else
  echo "lock.sh: swaylock is not installed" >&2
  exit 1
fi
