#!/usr/bin/env bash
# Floating rofi menu for reaching this rice's own utility scripts in one place -
# inspired by Omarchy's Super-key menu, scoped to actions that exist here.
# Actions needing interactive input open in their own floating kitty window
# (see the AppMenuTask window-rule in config.kdl); everything else runs directly.
# Each label carries a leading Nerd Font glyph (Font Awesome PUA, rendered by
# the rofi theme's Nerd Font) + two spaces, so every first-level entry shows an
# icon. LABELS and COMMANDS are index-aligned - keep them in the same order.
LABELS=(
  $'  Desktop Theme'
  $'  Cursor Theme'
  $'  Icon Theme'
  $'  Match GDM Login to Theme'
  $'  Set Screensaver Text/Image'
  $'  Preview Screensaver'
  $'  Set Screensaver Timeout'
  $'  Set AI Window Folder'
  $'  AI API Keys'
  $'  Toggle Caffeine'
  $'  Toggle Do Not Disturb'
  $'  Music Player'
  $'  Clipboard History'
  $'  Colorpicker'
  $'  Screenshot Tool'
  $'  Lock Screen'
  $'  Power Menu'
  $'  Niri Settings (NiriMod)'
  $'  Restart Waybar'
  $'  Keybinding Help'
  $'  Arrange Displays'
)
COMMANDS=(
  "~/.local/bin/waybar-theme.sh"
  "~/.local/bin/cursor-theme.sh"
  "~/.local/bin/icon-theme.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/gdm-theme-sync.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/set-screensaver-text.sh"
  "kitty --class Screensaver -e ~/.local/bin/screensaver.sh"
  "~/.local/bin/set-screensaver-timeout.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/set-ai-window-folder.sh"
  "if [ -x ~/.local/bin/ai-key-manager ]; then ~/.local/bin/ai-key-manager; else ai-key-manager; fi"
  "~/.local/bin/caffeine-toggle.sh"
  "~/.local/bin/dnd-toggle.sh"
  "~/.local/bin/cliamp-toggle.sh"
  "copyq toggle"
  "~/.local/bin/colorpicker.sh"
  "~/.local/bin/screenshot-tool.sh"
  "~/.local/bin/lock.sh --with-screensaver"
  "~/.local/bin/powermenu.sh"
  "~/.local/bin/niri-mod.sh"
  "~/.local/bin/waybar-launch.sh"
  "kitty --class KeybindingsHelp -e ~/.local/bin/keybindings-help.sh"
  "~/.local/bin/arrange-displays.sh"
)

CHOSEN="$(printf '%s\n' "${LABELS[@]}" | rofi -dmenu -i -p "Menu" -theme ~/.config/rofi/current.rasi)"
[ -z "$CHOSEN" ] && exit 0

for i in "${!LABELS[@]}"; do
  if [ "${LABELS[$i]}" = "$CHOSEN" ]; then
    eval "${COMMANDS[$i]}" &
    disown
    exit 0
  fi
done
