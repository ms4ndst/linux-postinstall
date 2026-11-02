#!/usr/bin/env bash
# Prints this rice's keybinding cheat sheet in a floating kitty window, in the
# terminal's own palette (kitty follows the desktop theme, so this does too).
# Dismisses on any keypress. Reachable from the app menu and Mod+I. Niri also
# has its own built-in overlay on Mod+Shift+/ (show-hotkey-overlay).
MAUVE=$'\033[35m'    # magenta (color5) - key column
TEXT=$'\033[39m'     # default foreground - descriptions
SUBTEXT=$'\033[90m'  # bright black (color8) - divider
RESET=$'\033[0m'

# binding|action - curated display list (not parsed from config.kdl), kept in
# sync with the binds in ~/.config/niri/config.kdl. Sorted by key.
ROWS=(
  "Mod+1..9|Switch to workspace 1-9"
  "Mod+shift+1..9|Move column to workspace 1-9"
  "Mod+a|AI window (Mistral Vibe CLI), summon/stash"
  "Mod+shift+a|Mistral Vibe web app, summon/stash"
  "Mod+c|Center the focused column"
  "Mod+shift+c|Toggle caffeine (inhibit screen-lock/sleep)"
  "Mod+comma / Mod+period|Consume / expel window into/out of the column"
  "Mod+bracketleft/right|Consume-or-expel window left / right"
  "Mod+e|File manager (Strata)"
  "Mod+shift+e|Exit niri (with confirm)"
  "Mod+Escape|Block-art screensaver, on demand"
  "Mod+f|Maximize column"
  "Mod+shift+f|Fullscreen toggle"
  "Mod+shift+backslash|Toggle floating for the focused window"
  "Mod+ctrl+space|Switch focus between floating and tiling"
  "Mod+shift+g|Colorpicker (click a pixel, hex copied to clipboard)"
  "Mod+h / Mod+l|Focus column left / right"
  "Mod+j / Mod+k|Focus window down / up"
  "Mod+shift+h/l|Move column left / right"
  "Mod+shift+j/k|Move window down / up"
  "Mod+ctrl+h / Mod+ctrl+l|Focus monitor left / right"
  "Mod+ctrl+shift+h/l|Move column to the monitor left / right"
  "Mod+i|Show this keybinding help"
  "Mod+alt+l|Lock screen"
  "Mod+m|CLIamp terminal music player, summon/stash"
  "Mod+shift+m|CLIamp first-time setup"
  "Mod+minus / Mod+equal|Shrink / grow column width"
  "Mod+shift+minus/equal|Shrink / grow window height"
  "Mod+n|Toggle Do Not Disturb"
  "Mod+p|Printer setup"
  "Mod+shift+p|Power menu"
  "Mod+Page_Down / Up|Focus workspace below / above"
  "Mod+shift+Page_Down/Up|Move column to workspace below / above"
  "Print|Screenshot (slurp+grim+satty, or Greenshot via App Menu)"
  "Ctrl+Print / Alt+Print|Niri screenshot of screen / window"
  "Mod+r|Cycle preset column widths"
  "Mod+Return|Open kitty"
  "Mod+shift+q|Close focused window"
  "Mod+s (shift)|Niri settings (NiriMod)"
  "Mod+space|Rofi app launcher (drun)"
  "Mod+alt+space|App menu"
  "Mod+shift+space|Rofi run launcher"
  "Mod+Tab|Overview (all workspaces)"
  "Mod+shift+v|Clipboard history (copyq)"
  "Mod+shift+w|Wallpaper picker"
  "Mod+shift+F23|Claude Desktop, summon/stash (Copilot key)"
  "Mod+shift+/|Niri's built-in hotkey overlay"
  "XF86Audio Play/Next/Prev|Media control (playerctl)"
  "XF86Audio Raise/Lower/Mute|Volume, with a dunst level popup"
  "XF86MonBrightness Up/Down|Brightness, with a dunst level popup"
)

WIDTH=0
for row in "${ROWS[@]}"; do
  binding="${row%%|*}"
  [ "${#binding}" -gt "$WIDTH" ] && WIDTH="${#binding}"
done

clear
echo "${MAUVE}Keybinding Cheat Sheet${RESET}  ${SUBTEXT}(Mod = Super/Windows key)${RESET}"
echo "${SUBTEXT}$(printf '%.0s─' $(seq 1 78))${RESET}"
echo
for row in "${ROWS[@]}"; do
  binding="${row%%|*}"
  action="${row#*|}"
  printf "  ${MAUVE}%-${WIDTH}s${RESET}   ${TEXT}%s${RESET}\n" "$binding" "$action"
done
echo
echo "${SUBTEXT}Press any key to close...${RESET}"
read -r -n 1 -s
