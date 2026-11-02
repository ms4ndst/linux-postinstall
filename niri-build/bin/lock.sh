#!/usr/bin/env bash
# Niri rice lock screen: Catppuccin Mocha scheme (~/.config/swaylock/config,
# seeded from github.com/catppuccin/swaylock) over a blurred live screenshot,
# with a random fortune quote baked in below the indicator - and, when the
# binary is swaylock-effects, a live clock at center. swaylock works under niri.
# Guard against overlapping invocations: swayidle calls this on idle/sleep AND
# Mod+Alt+l calls it directly - flock closes the TOCTOU gap so a second
# swaylock never starts on top of one already holding the session.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lock.sh.lock"
flock -n 9 || exit 0

LOCKCFG="$HOME/.config/swaylock/config"

# --with-screensaver (passed by swayidle's idle timeout and the lock keybind)
# runs the block-art screensaver first; any keypress dismisses it straight into
# the real password lock below - dismissing early does NOT cancel the lock.
if [ "$1" = "--with-screensaver" ]; then
  kitty --class Screensaver -e ~/.local/bin/screensaver.sh
fi

# A random short geek quote under the ring, composited into the lock background
# itself (fortune -s: short one-liner fortunes only, folded by caption:).
FORTUNE=""
if command -v fortune >/dev/null 2>&1; then
  FORTUNE="$(fortune -s 2>/dev/null | tr '\t\n' '  ' | tr -s ' ' \
             | sed 's/ *$//' | cut -c1-140)"
fi

# Build the per-output lock backgrounds: a live screenshot of each output,
# blurred + darkened (the fast downscale/upscale blur), with the quote
# centered below the indicator/clock block.
LOCKDIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/lock.XXXXXX")"
trap 'rm -rf "$LOCKDIR"' EXIT
FONT="$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font' 2>/dev/null || true)"
IMAGES=()
while read -r name w h; do
  [ -n "$name" ] || continue
  img="$LOCKDIR/$name.png"
  if ! env -u LD_LIBRARY_PATH grim -o "$name" "$img" 2>/dev/null; then
    continue
  fi
  if [ -n "$FORTUNE" ]; then
    magick "$img" \
      \( -clone 0 -resize 6% -resize 1700% -fill '#1e1e2e' -colorize 35 \) \
      -delete 0 \
      \( -size "$((w * 7 / 12))x" -background none -font "$FONT" \
         -pointsize "$((h / 32))" -fill '#a6adc8' caption:"$FORTUNE" \) \
      -gravity center -geometry "+0+$((h / 5))" -composite \
      "$img" 2>/dev/null && IMAGES+=(-i "$name:$img")
  else
    magick "$img" -resize 6% -resize 1700% \
      -fill '#1e1e2e' -colorize 35 "$img" 2>/dev/null \
      && IMAGES+=(-i "$name:$img")
  fi
done < <(niri msg --json outputs 2>/dev/null | \
         jq -r 'to_entries[] | .value | select(.logical) |
                "\(.name) \(.logical.width) \(.logical.height)"')

# swaylock-effects (the fork with the live --clock) takes priority when the
# binary supports it; plain swaylock uses the same backgrounds, just without
# the clock.
if swaylock --help 2>&1 | grep -q -- "--effect-blur"; then
  swaylock -C "$LOCKCFG" "${IMAGES[@]}" \
    --indicator-idle-visible \
    --clock \
    --timestr '%H:%M:%S' \
    --datestr '%a, %d/%m/%Y'
elif command -v swaylock >/dev/null 2>&1; then
  if [ "${#IMAGES[@]}" -gt 0 ]; then
    swaylock -C "$LOCKCFG" "${IMAGES[@]}"
  else
    # no fortune-possible backgrounds (grim/magick failed): flat Mocha lock
    swaylock -C "$LOCKCFG"
  fi
else
  echo "lock.sh: swaylock is not installed" >&2
  exit 1
fi
