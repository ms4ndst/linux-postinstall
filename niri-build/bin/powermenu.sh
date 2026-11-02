#!/usr/bin/env bash
# Icon-only menu (green=lock, cyan=suspend, yellow=logout, magenta=reboot,
# red=shutdown) - no labels, so there's no text to wrap/clip in a narrow
# column. rofi echoes back the exact line it displayed, so matching on the
# icon glyph itself (rather than a label string) is what identifies the
# selection here. Colors are read from kitty's current.conf (color1/2/3/5/6
# - the same ANSI palette ~/.local/bin/waybar-theme.sh keeps in sync with
# the active polybar/rofi theme) rather than hardcoded, so this menu
# retints along with everything else instead of always showing Catppuccin
# Mocha's own hex values regardless of the active theme.
KITTY_CURRENT="$HOME/.config/kitty/current.conf"
color() { awk -v c="$1" '$1==c {print $2}' "$KITTY_CURRENT"; }
GREEN="$(color color2)"
CYAN="$(color color6)"
YELLOW="$(color color3)"
MAGENTA="$(color color5)"
RED="$(color color1)"
choice=$(printf '<span foreground="%s" font="JetBrainsMono Nerd Font 26"></span>\n<span foreground="%s" font="JetBrainsMono Nerd Font 26"></span>\n<span foreground="%s" font="JetBrainsMono Nerd Font 26"></span>\n<span foreground="%s" font="JetBrainsMono Nerd Font 26"></span>\n<span foreground="%s" font="JetBrainsMono Nerd Font 26"></span>' \
  "$GREEN" "$CYAN" "$YELLOW" "$MAGENTA" "$RED" \
  | rofi -dmenu -markup-rows -i -p "" -theme ~/.config/rofi/current-powermenu.rasi)
case "$choice" in
  *""*)     ~/.local/bin/lock.sh --with-screensaver ;;
  *""*)  systemctl suspend ;;
  *""*)   niri msg action quit ;;
  *""*)   systemctl reboot ;;
  *""*) systemctl poweroff ;;
esac
