#!/usr/bin/env bash
# Lists available themes (~/.config/waybar/themes/*/) via rofi and, on
# selection, applies matching waybar + rofi + kitty + starship + dunst + sway
# border-color themes together, so one pick retints the whole desktop instead
# of just the bar. Each is its own COMPLETE, standalone config (a waybar
# config.jsonc + style.css, a rofi .rasi pair, a kitty color .conf, a starship
# .toml, a dunst dunstrc, a sway client.* border fragment) applied with a plain
# file copy. Port of the i3 rice's polybar-theme.sh.
#
# Usage:
#   waybar-theme.sh          # prompts via rofi
#   waybar-theme.sh <name>   # applies themes/<name> directly, no prompt
set -euo pipefail

WAYBAR_THEMES_DIR="$HOME/.config/waybar/themes"
WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"
ROFI_THEMES_DIR="$HOME/.config/rofi/themes"
ROFI_CURRENT="$HOME/.config/rofi/current.rasi"
ROFI_POWERMENU_CURRENT="$HOME/.config/rofi/current-powermenu.rasi"
KITTY_THEMES_DIR="$HOME/.config/kitty/themes"
KITTY_CURRENT="$HOME/.config/kitty/current.conf"
STARSHIP_THEMES_DIR="$HOME/.config/starship/themes"
STARSHIP_CURRENT="$HOME/.config/starship.toml"
DUNST_THEMES_DIR="$HOME/.config/dunst/themes"
DUNST_CURRENT="$HOME/.config/dunst/dunstrc"
# The i3 rice's per-theme border fragments (client.* color lines) are valid
# sway syntax too, so reuse them directly; the sway config includes the written
# current-borders.conf. Keyed by base name (no -square/-numbered/-alt).
SWAY_THEMES_DIR="$HOME/.config/i3/themes"
SWAY_CURRENT="$HOME/.config/sway/current-borders.conf"
mkdir -p "$HOME/.config/sway"
NVIM_COLORS_DIR="$HOME/.config/nvim/colors"
NVIM_CURRENT="$NVIM_COLORS_DIR/current.lua"
# Kept at the polybar path for continuity with the i3 rice's state file name.
CURRENT_THEME_FILE="$HOME/.config/waybar/current-theme-name"
MARK=" "

mapfile -t THEME_DIRS < <(find "$WAYBAR_THEMES_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
if [ "${#THEME_DIRS[@]}" -eq 0 ]; then
  notify-send "Desktop Theme" "No themes found in $WAYBAR_THEMES_DIR"
  exit 1
fi

NAMES=()
for d in "${THEME_DIRS[@]}"; do
  NAMES+=("$(basename "$d")")
done

ACTIVE=""
[ -f "$CURRENT_THEME_FILE" ] && ACTIVE="$(cat "$CURRENT_THEME_FILE")"

CHOSEN="${1:-}"
if [ -z "$CHOSEN" ]; then
  DISPLAY_LINES=()
  for n in "${NAMES[@]}"; do
    if [ "$n" = "$ACTIVE" ]; then
      DISPLAY_LINES+=("$MARK$n")
    else
      DISPLAY_LINES+=("  $n")
    fi
  done
  PICKED="$(printf '%s\n' "${DISPLAY_LINES[@]}" | rofi -dmenu -i -p "Desktop Theme" -theme "$ROFI_CURRENT")"
  CHOSEN="${PICKED#??}"
fi
[ -z "$CHOSEN" ] && exit 0

WAYBAR_DIR="$WAYBAR_THEMES_DIR/$CHOSEN"
ROFI_FILE="$ROFI_THEMES_DIR/$CHOSEN.rasi"
ROFI_POWERMENU_FILE="$ROFI_THEMES_DIR/$CHOSEN-powermenu.rasi"
KITTY_FILE="$KITTY_THEMES_DIR/$CHOSEN.conf"
STARSHIP_FILE="$STARSHIP_THEMES_DIR/$CHOSEN.toml"
DUNST_FILE="$DUNST_THEMES_DIR/$CHOSEN.dunstrc"
# -square/-numbered/-alt are bar-only variants - strip to the base rice name
# for the GTK/sway/nvim palettes (no corner-rounding concept in those).
BASE_NAME="${CHOSEN%-square}"
BASE_NAME="${BASE_NAME%-numbered}"
BASE_NAME="${BASE_NAME%-alt}"
SWAY_FILE="$SWAY_THEMES_DIR/$BASE_NAME.conf"

if [ ! -d "$WAYBAR_DIR" ]; then
  notify-send "Desktop Theme" "No such theme: $CHOSEN"
  exit 1
fi

# Record the pick up front (not at the end): a mid-switch failure under
# set -e would otherwise leave the name file pointing at the previous
# theme while the bar already runs the new one.
echo "$CHOSEN" > "$CURRENT_THEME_FILE"

# GTK3/GTK4 theme - "-square" variants share the base rice's palette, so a real
# GTK theme only ever exists as Rice-<base-name>. Export before relaunching the
# bar so freshly-forked apps inherit it immediately (no logout).
GTK_BASE="$BASE_NAME"
if [ -d "$HOME/.themes/Rice-$GTK_BASE/gtk-3.0" ]; then
  export GTK_THEME="Rice-$GTK_BASE"
  gsettings set org.gnome.desktop.interface gtk-theme "Rice-$GTK_BASE"
  [ -f "$HOME/.config/gtk-3.0/settings.ini" ] && sed -i "s/^gtk-theme-name=.*/gtk-theme-name=Rice-$GTK_BASE/" "$HOME/.config/gtk-3.0/settings.ini"
  [ -f "$HOME/.config/gtk-4.0/settings.ini" ] && sed -i "s/^gtk-theme-name=.*/gtk-theme-name=Rice-$GTK_BASE/" "$HOME/.config/gtk-4.0/settings.ini"
  if [ -f "$HOME/.config/environment.d/gtk-theme.conf" ]; then
    sed -i "s/^GTK_THEME=.*/GTK_THEME=Rice-$GTK_BASE/" "$HOME/.config/environment.d/gtk-theme.conf"
    systemctl --user set-environment GTK_THEME="Rice-$GTK_BASE" 2>/dev/null || true
  fi
else
  notify-send "Desktop Theme" "No GTK theme Rice-$GTK_BASE for $CHOSEN, keeping previous"
fi

cp "$WAYBAR_DIR/config.jsonc" "$WAYBAR_CONFIG"
cp "$WAYBAR_DIR/style.css" "$WAYBAR_STYLE"
# The HANCORE theme styles @import "../omarchy/current/theme/waybar.css"
# for their @background/@foreground/@transparent - copy this theme's own
# palette there too, so the bar follows the switch (a theme without a
# palette.css - e.g. one of the old rice's own - is skipped, no breakage).
if [ -f "$WAYBAR_DIR/palette.css" ]; then
  mkdir -p "$HOME/.config/omarchy/current/theme"
  cp "$WAYBAR_DIR/palette.css" "$HOME/.config/omarchy/current/theme/waybar.css"
fi
~/.local/bin/waybar-launch.sh

if [ -f "$ROFI_FILE" ]; then
  cp "$ROFI_FILE" "$ROFI_CURRENT"
else
  notify-send "Desktop Theme" "No rofi theme for $CHOSEN, keeping previous"
fi
if [ -f "$ROFI_POWERMENU_FILE" ]; then
  cp "$ROFI_POWERMENU_FILE" "$ROFI_POWERMENU_CURRENT"
else
  notify-send "Desktop Theme" "No rofi powermenu theme for $CHOSEN, keeping previous"
fi

if [ -f "$KITTY_FILE" ]; then
  cp "$KITTY_FILE" "$KITTY_CURRENT"
  for sock in /tmp/kitty-mgns-*; do
    [ -S "$sock" ] || continue
    kitty @ --to "unix:$sock" set-colors -a "$KITTY_CURRENT" >/dev/null 2>&1 || true
  done
else
  notify-send "Desktop Theme" "No kitty theme for $CHOSEN, keeping previous"
fi

if [ -f "$STARSHIP_FILE" ]; then
  cp "$STARSHIP_FILE" "$STARSHIP_CURRENT"
else
  notify-send "Desktop Theme" "No starship theme for $CHOSEN, keeping previous"
fi

if [ -f "$DUNST_FILE" ]; then
  cp "$DUNST_FILE" "$DUNST_CURRENT"
  dunstctl reload >/dev/null 2>&1 || true
else
  notify-send "Desktop Theme" "No dunst theme for $CHOSEN, keeping previous"
fi

if [ -f "$SWAY_FILE" ]; then
  cp "$SWAY_FILE" "$SWAY_CURRENT"
  # sway re-reads the whole config (incl. the `include current-borders.conf`
  # line) on reload without disturbing the current layout or scratchpad state.
  swaymsg reload >/dev/null 2>&1 || true
  # Floating-bar themes (gh0stzk-*) can reserve room with `gaps top/bottom`;
  # sway applies config gaps only to workspaces created AFTER reload, so set
  # them on existing workspaces at runtime too. A theme without them gets the
  # config's own outer gap back.
  outer="$(sed -n 's/^gaps outer \([0-9]*\).*/\1/p' "$HOME/.config/sway/config" | head -1)"
  top="$(sed -n 's/^gaps top \([0-9]*\).*/\1/p' "$SWAY_CURRENT" | tail -1)"
  bottom="$(sed -n 's/^gaps bottom \([0-9]*\).*/\1/p' "$SWAY_CURRENT" | tail -1)"
  swaymsg "gaps top all set ${top:-${outer:-0}}; gaps bottom all set ${bottom:-${outer:-0}}" >/dev/null 2>&1 || true
else
  notify-send "Desktop Theme" "No sway border theme for $CHOSEN, keeping previous"
fi

# cliamp (Mod+m) and Mistral Vibe (Mod+a) draw their own colors on top of
# kitty's - bring them in line with the kitty/border files just applied.
~/.local/bin/app-theme-sync.sh || true

NVIM_FILE="$NVIM_COLORS_DIR/rice-$BASE_NAME.lua"
if [ -f "$NVIM_FILE" ]; then
  cp "$NVIM_FILE" "$NVIM_CURRENT"
  for sock in /tmp/nvim-mgns-*; do
    [ -S "$sock" ] || continue
    nvim --server "$sock" --remote-expr 'v:lua.vim.cmd("colorscheme current")' >/dev/null 2>&1 || true
  done
else
  notify-send "Desktop Theme" "No neovim theme for $BASE_NAME, keeping previous"
fi

notify-send "Desktop Theme" "Switched to $CHOSEN"
