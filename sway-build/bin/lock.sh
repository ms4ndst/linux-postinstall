#!/usr/bin/env bash
# Sway rice lock screen (swaylock) - port of the i3 rice's i3lock-color lock.sh.
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
ACCENT="${ACCENTS[$ACCENT_IDX]}"
KEYHL="${ACCENTS[$(( (ACCENT_IDX + 7) % ${#ACCENTS[@]} ))]}"

# Blank the displays immediately on lock rather than waiting for swayidle's own
# DPMS timer - any key/mouse wakes them straight into the running swaylock.
blank() { swaymsg "output * power off" >/dev/null 2>&1 || true; }

# swaylock-effects adds --screenshots/--effect-blur (the equivalent of the i3
# rice's i3lock-color blur); plain swaylock lacks them. Detect by grepping
# --help for effect-blur (swaylock DOES list its flags in --help, unlike
# i3lock), same spirit as the i3 rice's i3lock-color package check. NOTE:
# swaylock has no custom greeter/wrong-text flags, so the i3 rice's witty
# lock messages have no equivalent here and are intentionally dropped.
if swaylock --help 2>&1 | grep -q -- "--effect-blur"; then
  swaylock \
    --screenshots \
    --effect-blur 8x3 \
    --effect-vignette 0.4:0.4 \
    --clock --indicator \
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
  blank
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
  blank
  wait "$LOCK_PID"
else
  echo "lock.sh: swaylock is not installed" >&2
  exit 1
fi
