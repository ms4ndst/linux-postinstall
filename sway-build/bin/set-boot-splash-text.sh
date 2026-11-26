#!/usr/bin/env bash
# Set the boot-splash (Plymouth) text - the wordmark you see while the machine
# boots and at the LUKS decrypt prompt (stock Fedora shows the "Fedora" logo
# there; OpenMandriva its own). This renders your text to the watermark of a
# self-contained "rice-splash" Plymouth theme - a spinner-based theme that keeps
# the firmware/OEM logo (UseFirmwareBackground) and the boot spinner, and only
# swaps the bottom wordmark - then makes it the active theme and rebuilds the
# initramfs so it shows on the NEXT boot.
#
# Needs root: Plymouth themes live under /usr/share and the text is baked into
# the initramfs (dracut), so this calls sudo - run it from a terminal so the
# password prompt works. The super+alt+space app menu launches it in kitty for
# exactly that reason.
#
# Usage:
#   set-boot-splash-text.sh                  # interactive menu
#   set-boot-splash-text.sh "My Laptop"      # set this exact text
#   set-boot-splash-text.sh --default        # revert the text to the distro name
#   set-boot-splash-text.sh --stock          # restore the stock boot splash
#
# Reverting (--default) keeps the rice-splash theme but re-renders the wordmark
# from /etc/os-release (PRETTY_NAME, e.g. "Fedora Linux"). --stock instead points
# Plymouth back at the distro's own default theme and rebuilds, undoing this tool
# entirely.
set -euo pipefail

THEMES=/usr/share/plymouth/themes
RICE="rice-splash"
RICE_DIR="$THEMES/$RICE"
CONF=/etc/plymouth/plymouthd.conf
STATE="$HOME/.config/rice/boot-splash-text"   # last text we rendered (for display)
# Catppuccin Mocha, matching the rest of the rice.
FG="#cdd6f4"; BG="0x1e1e2e"

note()  { printf '\033[1;35m[boot-splash]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[boot-splash]\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m[boot-splash]\033[0m %s\n' "$*" >&2; exit 1; }

# ImageMagick 7 is `magick`; 6 is `convert`.
if command -v magick >/dev/null 2>&1; then IM=(magick)
elif command -v convert >/dev/null 2>&1; then IM=(convert)
else die "ImageMagick not found (need 'magick' or 'convert'). Install it and retry."; fi

command -v plymouth-set-default-theme >/dev/null 2>&1 \
  || die "plymouth-set-default-theme not found - is Plymouth installed?"

distro_name() { ( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}" ); }

# Resolve the rice font (JetBrainsMono Nerd bold), else any bold monospace.
FONT="$(fc-match -f '%{file}' 'JetBrainsMono Nerd Font:style=Bold' 2>/dev/null || true)"
[ -n "$FONT" ] && [ -f "$FONT" ] || FONT="$(fc-match -f '%{file}' 'monospace:style=Bold' 2>/dev/null || true)"

# Render <text> to a Plymouth watermark PNG at <out> (light text, transparent bg,
# trimmed, capped in size so a long name can't overflow the splash).
render_watermark() {
  local text="$1" out="$2" fontargs=()
  [ -n "$FONT" ] && fontargs=(-font "$FONT")
  "${IM[@]}" -background none "${fontargs[@]}" -fill "$FG" -pointsize 64 \
    label:"$text" -trim +repage \
    -bordercolor none -border 8 \
    -resize '900x120>' \
    "$out" 2>/dev/null || die "ImageMagick failed to render the wordmark."
  [ -s "$out" ] || die "Rendered wordmark is empty."
}

# Create the rice-splash theme (once) from the stock spinner theme, keeping the
# firmware logo + spinner and only owning our own watermark.
ensure_theme() {
  [ -f "$RICE_DIR/$RICE.plymouth" ] && return 0
  note "Creating the rice-splash Plymouth theme (first run)..."
  sudo mkdir -p "$RICE_DIR"
  # Copy the spinner theme's images (spinner/throbber frames, entry/lock/bullet,
  # keymaps) if present, but NOT its watermark - we render our own. If no spinner
  # theme is installed (some distros package it differently), fall back to a
  # watermark-only splash rather than failing.
  if [ -d "$THEMES/spinner" ]; then
    sudo sh -c "cp -f '$THEMES/spinner/'*.png '$RICE_DIR/' 2>/dev/null; rm -f '$RICE_DIR/watermark.png'"
  else
    warn "No 'spinner' theme found - the splash will show the firmware logo + your text, without the boot spinner animation."
  fi
  sudo tee "$RICE_DIR/$RICE.plymouth" >/dev/null <<EOF
[Plymouth Theme]
Name=rice-splash
Description=Rice boot splash - spinner + firmware logo with a customizable wordmark
ModuleName=two-step

[two-step]
Font=Cantarell 12
TitleFont=Cantarell Light 30
ImageDir=$RICE_DIR
DialogHorizontalAlignment=.5
DialogVerticalAlignment=.382
TitleHorizontalAlignment=.5
TitleVerticalAlignment=.382
HorizontalAlignment=.5
VerticalAlignment=.7
WatermarkHorizontalAlignment=.5
WatermarkVerticalAlignment=.96
Transition=none
TransitionDuration=0.0
BackgroundStartColor=$BG
BackgroundEndColor=$BG
ProgressBarBackgroundColor=0x606060
ProgressBarForegroundColor=0xffffff
MessageBelowAnimation=true
UseFirmwareBackground=true
DialogClearsFirmwareBackground=true

[boot-up]
UseEndAnimation=false
UseFirmwareBackground=true

[shutdown]
UseEndAnimation=false

[reboot]
UseEndAnimation=false
EOF
}

apply_theme() {   # <theme-name>
  local theme="$1"
  # plymouthd.conf's [Daemon] Theme= overrides the default symlink; set it so the
  # choice is unambiguous (this machine had a dangling catppuccin-mocha override).
  if [ -f "$CONF" ] && grep -q '^\s*Theme=' "$CONF"; then
    sudo sed -i "s/^\s*Theme=.*/Theme=$theme/" "$CONF"
  else
    sudo sh -c "printf '[Daemon]\nTheme=%s\n' '$theme' >> '$CONF'"
  fi
  note "Activating '$theme' and rebuilding the initramfs (this can take ~30-60s)..."
  sudo plymouth-set-default-theme -R "$theme" >/dev/null 2>&1 \
    || { sudo plymouth-set-default-theme "$theme" >/dev/null 2>&1 || true; sudo dracut -f >/dev/null 2>&1 || warn "dracut -f failed - run it yourself to apply."; }
}

set_text() {   # <text>
  local text="$1" tmp
  [ -n "$text" ] || die "No text given."
  ensure_theme
  tmp="$(mktemp --suffix=.png)"
  render_watermark "$text" "$tmp"
  sudo install -m644 "$tmp" "$RICE_DIR/watermark.png"
  rm -f "$tmp"
  mkdir -p "$(dirname "$STATE")"; printf '%s\n' "$text" > "$STATE" 2>/dev/null || true
  apply_theme "$RICE"
  note "Boot-splash text set to: $text"
  note "It appears on the next boot."
}

restore_stock() {
  local def="bgrt"
  [ -e "$THEMES/bgrt/bgrt.plymouth" ] || def="$(plymouth-set-default-theme --list 2>/dev/null | grep -viE '^rice-splash$' | head -1)"
  [ -n "$def" ] || die "Couldn't determine a stock theme to restore."
  apply_theme "$def"
  rm -f "$STATE" 2>/dev/null || true
  note "Restored the stock boot splash ('$def'). It appears on the next boot."
}

# -------- argument / interactive dispatch --------
case "${1:-}" in
  --default|-d) set_text "$(distro_name)"; exit 0 ;;
  --stock|-s)   restore_stock; exit 0 ;;
  "" )          : ;;                 # fall through to the menu
  * )           set_text "$1"; exit 0 ;;
esac

current="$(cat "$STATE" 2>/dev/null || echo "(stock - $(distro_name))")"
printf '\n  Boot-splash text  —  current: %s\n\n' "$current"
printf '  1) Set custom text\n'
printf '  2) Reset to the distro name (%s)\n' "$(distro_name)"
printf '  3) Restore the stock boot splash\n'
printf '  q) Quit\n\n'
printf '  Choose [1/2/3/q]: '
read -r choice
case "$choice" in
  1) printf '  Enter the boot-splash text: '; read -r t; [ -n "$t" ] && set_text "$t" || warn "Empty - nothing changed." ;;
  2) set_text "$(distro_name)" ;;
  3) restore_stock ;;
  *) note "No change." ;;
esac
