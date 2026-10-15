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
  # on top of the previous, so combos stack).
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
    --timestr '%H:%M' \
    --datestr '%A, %d %B' &
  LOCK_PID=$!
  wait "$LOCK_PID"
elif command -v swaylock >/dev/null 2>&1; then
  # Plain swaylock: replicate swaylock-effects' signature look with tools the
  # rice already ships - grim takes a live screenshot of each output,
  # ImageMagick blurs + darkens it and bakes a clock/date on top, and swaylock
  # -i displays the result per output. Trade-off vs the effects fork: the
  # clock is frozen at lock time instead of ticking.
  LOCKDIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/lock.XXXXXX")"
  trap 'rm -rf "$LOCKDIR"' EXIT
  FONT="$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font' 2>/dev/null || true)"
  IMAGES=()
  while read -r name _w h; do
    img="$LOCKDIR/$name.png"
    if env -u LD_LIBRARY_PATH grim -o "$name" "$img" 2>/dev/null; then
      magick "$img" \
        -resize 6% -resize 1700% \
        -fill '#1e1e2e' -colorize 35 \
        -font "$FONT" \
        -gravity north -fill '#f5f0ee' \
        -pointsize "$(( h / 6 ))" -annotate "+0+$(( h / 6 ))" "$(date +%H:%M)" \
        -pointsize "$(( h / 24 ))" -annotate "+0+$(( h / 6 + h / 5 ))" "$(date '+%A, %d %B')" \
        "$img" 2>/dev/null && IMAGES+=(-i "$name:$img")
    fi
  done < <(swaymsg -t get_outputs 2>/dev/null | \
           jq -r '.[] | select(.active) | "\(.name) \(.current_mode.width) \(.current_mode.height)"')
  if [ "${#IMAGES[@]}" -gt 0 ]; then
    swaylock -C "$LOCKCFG" "${IMAGES[@]}" &
    LOCK_PID=$!
    wait "$LOCK_PID"
  else
    # no grim/magick or screenshot failed: the flat-color lock still works
    swaylock -C "$LOCKCFG" &
    LOCK_PID=$!
    wait "$LOCK_PID"
  fi
else
  echo "lock.sh: swaylock is not installed" >&2
  exit 1
fi
