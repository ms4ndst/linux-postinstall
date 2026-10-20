#!/usr/bin/env bash
# ============================================================================
# Sway "hackerbox" post-install script - Fedora 44 (HANCORE waybar themes)
# Theme collection: HANCORE-linux/waybar-themes (github.com/HANCORE-linux/
#           waybar-themes, MIT), fetched at install time, adapted from
#           their Omarchy/Hyprland home to plain Sway on Fedora, and wired
#           into this rice's theme switcher so one pick retints waybar,
#           rofi, kitty, dunst, starship, sway borders, GTK, Neovim and
#           VS Code together - the same mechanism the old embedded
#           Catppuccin collection used.
# Installs: sway, swaybg, swayidle, swaylock, waybar, kanshi, rofi, dunst,
#           kitty, swappy, ImageMagick, brightnessctl, playerctl,
#           fastfetch, Nerd Font, tray helpers, GTK/icon/cursor themes,
#           rofi power menu, copyq clipboard history, udiskie USB
#           automount, pcmanfm file manager, gammastep night light,
#           volume/brightness OSD popups, cava + btop for the HANCORE
#           themes' audio/system widgets, CLIamp terminal music player
#           (Mod+m), an Omarchy-style app menu (Mod+alt+space) for this
#           rice's own utility scripts (including a floating on-screen
#           keybinding cheat sheet), + always-visible window borders and
#           tightened gaps.
# Idempotent-ish: safe to re-run, but back up existing configs first if you
# have your own dotfiles - this OVERWRITES the files listed below.
# ===============================================================================
set -euo pipefail

log()  { echo -e "\e[1;35m[sway-setup]\e[0m $*"; }
warn() { echo -e "\e[1;33m[sway-setup]\e[0m $*"; }

if ! command -v dnf >/dev/null 2>&1; then
  echo "This script targets Fedora (dnf not found). Aborting." >&2
  exit 1
fi
# Run as your own user, never under sudo/root: the script calls sudo where
# needed and installs into $HOME - under sudo, $HOME is root's and every
# config would land in the wrong place.
if [ "$(id -u)" = "0" ]; then
  echo 'Do not run this with sudo - run it as your own user; it calls sudo itself and installs into $HOME.' >&2
  exit 1
fi
# Keep sudo warm for the whole run (prevents a mid-install credential
# timeout from aborting a later sudo step under set -e).
sudo -v || true
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

CONF="$HOME/.config"
BIN="$HOME/.local/bin"
FONTS="$HOME/.local/share/fonts"
mkdir -p "$CONF" "$BIN" "$FONTS"

# Default cursor theme - MUST be defined before the sway config is written:
# the config's cursor include file is seeded from it (section 4), long
# before the Qogir cursor section (13) that re-derives it. A previous
# version had this assignment only in section 13 and the script aborted
# with "CURSOR_THEME_NAME: unbound variable" at the seeding line.
CURSOR_THEME_NAME="Qogir"

# Theme replacement: this script installs the HANCORE-linux/waybar-themes
# collection in place of this rice's old embedded theme collection. Answer
# y here to wipe every existing desktop theme first (waybar/rofi/kitty/
# dunst/starship/sway-border themes, rice-* Neovim colors, Rice-* GTK
# themes); answer n to keep them and just add the new ones alongside.
CLEAN_THEMES=0
printf '\nThis script will install the HANCORE waybar theme collection.\n'
read -r -p 'Clean out ALL existing desktop themes first, then install the new ones? [y/N] ' reply || true
case "$reply" in
  [yY]|[yY][eE][sS]) CLEAN_THEMES=1 ;;
esac
unset reply
# Remove stale i3-only bar scripts from a previous i3-rice install so the
# Wayland switcher/app-menu can never invoke polybar (which cannot use
# layer-shell and floats as a broken window on sway), and stop any X11
# bar/compositor/tray left running from an i3 session.
rm -f "$BIN/polybar-launch.sh" "$BIN/polybar-theme.sh"
pkill -x polybar 2>/dev/null || true
pkill -x picom 2>/dev/null || true
pkill -x snixembed 2>/dev/null || true

# ----------------------------------------------------------------------------
# 0. Safety net: snapper snapshot of / before touching anything
# ----------------------------------------------------------------------------
# Needs Btrfs + an existing "root" snapper config (Fedora's Btrfs-by-default
# installer sets this up automatically on recent releases) - best-effort,
# never blocks the rest of the script if it's not available.
if command -v snapper >/dev/null 2>&1 \
    && sudo snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx root; then
  log "Taking a snapper snapshot of / before starting (rollback point)..."
  if SNAP_NUM="$(sudo snapper -c root create --type single --print-number \
      --description "before fedora-sway-setup.sh" 2>/dev/null)"; then
    log "Snapshot #$SNAP_NUM created. Roll back with: sudo snapper -c root undochange ${SNAP_NUM}..0"
  else
    warn "snapper snapshot failed — proceeding without a rollback point."
  fi
else
  warn "snapper not found (or no 'root' config) — skipping pre-install snapshot. Set up Btrfs + snapper first if you want one."
fi

# ----------------------------------------------------------------------------
# 1. Packages
# ----------------------------------------------------------------------------
log "Installing Wayland stack + Sway + rice toolkit via dnf..."
sudo dnf install -y \
  sway swaybg swayidle swaylock waybar kanshi \
  cava btop \
  grim slurp swappy wl-clipboard \
  rofi-wayland dunst kitty \
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  network-manager-applet pasystray blueman lxqt-policykit pipewire-pulseaudio \
  copyq udiskie pcmanfm gammastep libnotify gnome-calendar \
  azote \
  system-config-printer hplip \
  lxappearance papirus-icon-theme \
  fastfetch git curl unzip jq ImageMagick fortune-mod \
  brightnessctl playerctl dex-autostart \
  dnf-utils \
  solaar solaar-udev \
  pipx \
  jetbrains-mono-fonts \
  plymouth-plugin-script

# power-profiles-daemon backs the waybar power-profiles-daemon module in
# the HANCORE themes - but tuned-ppd (Fedora's tuned-based power-profiles
# provider, a common default) conflicts with it, so this is best-effort:
# with tuned-ppd installed the module is simply inert.
if ! sudo dnf install -y power-profiles-daemon >/dev/null 2>&1; then
  warn "power-profiles-daemon not installable (tuned-ppd conflict?) - the bar's power-profile widget will be inert; swap tuned-ppd out for power-profiles-daemon manually if you want it."
fi

# network-manager-applet/pasystray/blueman/udiskie are still installed above -
# their tray-icon *applets* (nm-applet, pasystray, blueman-applet) are
# deliberately never autostarted (see the sway config below); waybar's own
# wifi/volume/bluetooth widgets replace that display, but the underlying
# packages (NetworkManager, PulseAudio, bluetoothd, umount automation) still
# need to be present. udiskie IS autostarted, just in --tray mode.
#
# vala/gtk3-devel/libdbusmenu(-gtk3)-devel are build-only dependencies for
# snixembed (section 6e below) - not runtime deps of anything else here.

# brightnessctl's udev rules gate /sys/class/backlight writes behind the
# "video" group - without this, the brightness keys below silently no-op.
log "Adding $USER to the 'video' group (needed for brightnessctl)..."
sudo usermod -aG video "$USER" 2>/dev/null \
  || warn "Could not add $USER to 'video' group - brightness keys may not work until you do this manually."

# Lock screen: swaylock is installed above. swaylock-effects (the live
# clock and screenshot effects, used by lock.sh when present) is built
# from source in section 11 - no usable Fedora package or COPR exists;
# lock.sh falls back to plain swaylock automatically if that build fails.

# ----------------------------------------------------------------------------
# 2. Nerd Font (JetBrainsMono) — official Fedora repos don't ship patched fonts
# ----------------------------------------------------------------------------
if [ ! -d "$FONTS/JetBrainsMonoNerd" ]; then
  log "Downloading JetBrainsMono Nerd Font..."
  TMPZIP="$(mktemp --suffix=.zip)"
  # Best-effort: under set -e, an unguarded curl failure here (flaky network,
  # GitHub rate limit, renamed release asset) would abort the WHOLE script
  # before any sway/waybar/rofi/dunst/kitty config below ever gets
  # written - the font is cosmetic, it shouldn't be able to take those down.
  if curl -fLo "$TMPZIP" \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" 2>/dev/null; then
    mkdir -p "$FONTS/JetBrainsMonoNerd"
    unzip -o "$TMPZIP" -d "$FONTS/JetBrainsMonoNerd" >/dev/null
    fc-cache -f "$FONTS/JetBrainsMonoNerd"
  else
    warn "Nerd Font download failed (network issue?) - configs below still reference 'JetBrainsMono Nerd Font'; install it manually later or edit the font name in ~/.config/{sway,rofi,kitty}."
  fi
  rm -f "$TMPZIP"
else
  log "JetBrainsMono Nerd Font already present, skipping download."
fi

# ----------------------------------------------------------------------------
# 4. Sway config
# ----------------------------------------------------------------------------
log "Writing Sway config..."
mkdir -p "$CONF/sway"
cat > "$CONF/sway/config" <<'SWAY_EOF'
set $mod Mod4
font pango:JetBrainsMono Nerd Font 10

# gaps
gaps inner 8
gaps outer 2
default_border pixel 2
default_floating_border pixel 2
hide_edge_borders none

# Catppuccin Mocha border colors
# class                 border   bground  text     indicator child_border
client.focused          #cba6f7  #1e1e2e  #cdd6f4  #cba6f7   #cba6f7
client.unfocused        #313244  #1e1e2e  #6c7086  #313244   #313244
client.focused_inactive #45475a  #1e1e2e  #a6adc8  #45475a   #45475a
client.urgent           #f38ba8  #1e1e2e  #f38ba8  #f38ba8   #f38ba8

# Per-theme border colors: waybar-theme.sh writes the active theme's client.*
# palette here on every switch. A missing file is a silent no-op (the colors
# above stay in effect), so this is safe before the first theme switch.
include ~/.config/sway/current-borders.conf

floating_modifier $mod

# --- input ---
# numlock on at login; set your own layout here.
input type:keyboard {
    xkb_numlock enabled
    # @@XKB_LAYOUT@@ is filled from the system layout (localectl) at install time.
    xkb_layout "@@XKB_LAYOUT@@"
}
# Cursor theme on the desktop and in every app. The include file is
# rewritten live by cursor-theme.sh on every switch; Adwaita/24 here is
# filled in by the installer from the cursor theme it installs.
include ~/.config/sway/cursor-theme.conf

# --- window rules ---
# Keep a visible 2px border on every window regardless of what the app asks
# for (Electron/CSD apps self-decorate). app_id covers native Wayland clients,
# class covers XWayland ones.
for_window [app_id=".*"] border pixel 2
for_window [class=".*"] border pixel 2
# Settings-style dialogs: float + center + shrink. Native Wayland clients
# report app_id; XWayland clients (Electron/Chromium app-mode) report class, so
# the AI/web-app windows are matched on both to be safe.
for_window [app_id="nm-connection-editor"] floating enable, resize set 550 450, move position center
for_window [app_id="blueman-manager"] floating enable, resize set 500 400, move position center
for_window [app_id="(com.github.hluk.copyq|copyq)"] floating enable, resize set 450 500, move position center
for_window [class="copyq"] floating enable, resize set 450 500, move position center
# cliamp music player scratchpad (mark on its OWN line - a chained `mark`
# silently never applies (confirmed to carry over).
for_window [app_id="Cliamp"] floating enable, resize set 700 500, move position center
for_window [app_id="Cliamp"] mark cliamp-scratch
for_window [app_id="CliampSetup"] fullscreen enable
# Polkit authentication dialogs (lxqt-policykit-agent): on X11 these are
# dialog-type windows that float small automatically (i3); Wayland has
# no window type, so float them here - e.g. "Authenticate to unlock
# 1Password" after the screensaver locks the vault.
for_window [app_id="lxqt-policykit-agent"] floating enable, move position center
# Generic dialog handling for XWayland apps: they still carry the X11
# window-type property that i3 auto-floated on; match it here. Native
# Wayland apps have no window type (only a parent), so windows like
# LibreOffice's CSV import dialog need their own rules if they bother.
for_window [shell="xwayland" window_type="dialog"] floating enable
for_window [shell="xwayland" window_type="utility"] floating enable
for_window [app_id="AIVibe"] floating enable, resize set 900 650, move position center
for_window [app_id="AIVibe"] mark ai-window-scratch
for_window [app_id="AppMenuTask"] floating enable, resize set 600 400, move position center
for_window [app_id="KeybindingsHelp"] floating enable, resize set 950 850, move position center
for_window [app_id="UpdatesTask"] floating enable, resize set 1000 550, move position center
for_window [app_id="WeatherFloat"] floating enable, resize set 765 600, move position center

# A window opened via an xdg-activation token (clicking a link that opens
# a new tab/window on ANOTHER workspace, chat notifications, etc.) flags
# that workspace URGENT instead of stealing focus - waybar's
# sway/workspaces module then highlights the workspace number on the bar
# (accent pill, via the installer-appended workspace-state CSS), and the
# window border takes the client.urgent color above.
focus_on_window_activation urgent
for_window [app_id="org.gnome.Calendar"] floating enable, resize set 700 550, move position center
for_window [app_id="system-config-printer"] floating enable, resize set 750 550, move position center
for_window [class="System-config-printer.py"] floating enable, resize set 750 550, move position center
for_window [app_id="(org.pulseaudio.pavucontrol|pavucontrol)"] floating enable, resize set 1100 650, move position center
# Claude Desktop (Electron) - app_id under native Wayland, class under XWayland.
for_window [app_id="(com.anthropic.Claude|claude)"] floating enable, resize set 1200 850, move position center
for_window [app_id="(com.anthropic.Claude|claude)"] mark claude-desktop-scratch
for_window [class="com.anthropic.Claude"] floating enable, resize set 1200 850, move position center
for_window [class="com.anthropic.Claude"] mark claude-desktop-scratch
# Mistral Vibe (chat.mistral.ai in a Chromium app-mode window, class MistralVibe)
for_window [app_id="MistralVibe"] floating enable, resize set 1200 850, move position center
for_window [app_id="MistralVibe"] mark mistral-vibe-scratch
for_window [class="MistralVibe"] floating enable, resize set 1200 850, move position center
for_window [class="MistralVibe"] mark mistral-vibe-scratch
for_window [app_id="Screensaver"] fullscreen enable

# --- launch ---
bindsym $mod+Return exec kitty
bindsym $mod+space exec ~/.local/bin/fresh-env rofi -show drun -theme ~/.config/rofi/current.rasi
bindsym $mod+shift+space exec ~/.local/bin/fresh-env rofi -show run -theme ~/.config/rofi/current.rasi
bindsym $mod+e exec ~/.local/bin/fresh-env ~/.local/bin/strata
# Wayland wallpaper picker (azote is nitrogen's Wayland-native equivalent;
# falls back to the rice's own rofi picker if azote isn't installed).
bindsym $mod+shift+w exec ~/.local/bin/fresh-env ~/.local/bin/wallpaper-picker.sh
bindsym $mod+p exec ~/.local/bin/fresh-env system-config-printer
bindsym $mod+c exec ~/.local/bin/caffeine-toggle.sh
bindsym $mod+n exec ~/.local/bin/dnd-toggle.sh
bindsym $mod+Escape exec kitty --class Screensaver -e ~/.local/bin/screensaver.sh
bindsym $mod+shift+q kill
bindsym $mod+shift+c reload
bindsym $mod+shift+r reload
bindsym $mod+shift+e exec swaynag -t warning -m 'Exit sway?' -B 'Yes' 'swaymsg exit'

# --- lock / screenshot / power ---
bindsym $mod+l exec ~/.local/bin/lock.sh --with-screensaver
bindsym $mod+shift+p exec ~/.local/bin/fresh-env ~/.local/bin/powermenu.sh
# grim + slurp replace flameshot gui (region select -> save + copy).
bindsym Print exec ~/.local/bin/fresh-env ~/.local/bin/screenshot.sh

# --- colorpicker (grab any on-screen pixel's color as hex) ---
bindsym $mod+shift+g exec ~/.local/bin/colorpicker.sh

# --- clipboard history (copyq) ---
bindsym $mod+shift+v exec copyq toggle

# --- music (cliamp) ---
bindsym $mod+m exec ~/.local/bin/cliamp-toggle.sh
bindsym $mod+shift+m exec ~/.local/bin/cliamp-setup.sh

# --- AI window (Mistral Vibe CLI, `vibe`) ---
bindsym $mod+a exec ~/.local/bin/ai-window-toggle.sh

# --- keybinding help ---
bindsym $mod+i exec kitty --class KeybindingsHelp -e ~/.local/bin/keybindings-help.sh

# --- app menu (rofi utility menu) ---
# Mod1 (= Alt); "Mod1" and "alt" are both fine in sway.
bindsym $mod+Mod1+space exec ~/.local/bin/app-menu.sh

# --- volume / brightness / media ---
bindsym XF86AudioRaiseVolume exec ~/.local/bin/osd-volume.sh up
bindsym XF86AudioLowerVolume exec ~/.local/bin/osd-volume.sh down
bindsym XF86AudioMute exec ~/.local/bin/osd-volume.sh mute
bindsym XF86MonBrightnessUp exec ~/.local/bin/osd-brightness.sh up
bindsym XF86MonBrightnessDown exec ~/.local/bin/osd-brightness.sh down
bindsym XF86AudioPlay exec playerctl play-pause
bindsym XF86AudioNext exec playerctl next
bindsym XF86AudioPrev exec playerctl previous

# --- AI assistant key ---
# Copilot/AI key: Wayland reports it as Super+Shift+F23 (Microsoft Copilot-key
# standard); XF86Assistant was the X11 keysym. Bind both for portability.
bindsym $mod+Shift+F23 exec ~/.local/bin/claude-desktop-toggle.sh
bindsym $mod+shift+XF86Assistant exec ~/.local/bin/claude-desktop-toggle.sh
bindsym $mod+shift+a exec ~/.local/bin/mistral-vibe-toggle.sh

# --- focus / movement ---
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+semicolon focus right
bindsym $mod+shift+h move left
bindsym $mod+shift+j move down
bindsym $mod+shift+k move up
bindsym $mod+shift+semicolon move right

# --- multi-monitor ---
bindsym $mod+ctrl+h focus output left
bindsym $mod+ctrl+l focus output right
bindsym $mod+ctrl+shift+h move workspace to output left
bindsym $mod+ctrl+shift+l move workspace to output right

# --- split / layout ---
bindsym $mod+v split v
bindsym $mod+b split h
bindsym $mod+t layout toggle split
bindsym $mod+f fullscreen toggle
bindsym $mod+shift+f floating toggle
bindsym $mod+ctrl+space focus mode_toggle

# --- workspaces ---
# Pin workspaces to outputs for predictable multi-monitor placement - uncomment
# and edit to match `swaymsg -t get_outputs` names (eDP-1/HDMI-A-1/DP-1), e.g.:
#   workspace 1 output eDP-1
#   workspace 4 output HDMI-A-1
#   workspace 7 output DP-1
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+shift+1 move container to workspace number 1
bindsym $mod+shift+2 move container to workspace number 2
bindsym $mod+shift+3 move container to workspace number 3
bindsym $mod+shift+4 move container to workspace number 4
bindsym $mod+shift+5 move container to workspace number 5
bindsym $mod+shift+6 move container to workspace number 6
bindsym $mod+shift+7 move container to workspace number 7
bindsym $mod+shift+8 move container to workspace number 8
bindsym $mod+shift+9 move container to workspace number 9

# --- resize ---
mode "resize" {
    bindsym h resize shrink width 10px
    bindsym j resize grow height 10px
    bindsym k resize shrink height 10px
    bindsym l resize grow width 10px
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# --- autostart ---
# sway imports its own environment into the systemd --user / D-Bus activation
# environment, but do it explicitly too so late-started user services see
# WAYLAND_DISPLAY (keeps xdg-desktop-portal, etc. working).
exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
# xdg-desktop-portal + the wlr and gtk backends (file pickers, screenshots).
# wlr handles screencast/screenshot on wlroots; gtk handles the file chooser.
exec sh -c 'busctl --user status org.freedesktop.portal.Desktop >/dev/null 2>&1 || systemd-run --user --unit=xdg-desktop-portal-manual --collect /usr/libexec/xdg-desktop-portal'
exec sh -c 'busctl --user status org.freedesktop.impl.portal.desktop.wlr >/dev/null 2>&1 || systemd-run --user --unit=xdg-desktop-portal-wlr-manual --collect /usr/libexec/xdg-desktop-portal-wlr'
exec sh -c 'busctl --user status org.freedesktop.impl.portal.desktop.gtk >/dev/null 2>&1 || systemd-run --user --unit=xdg-desktop-portal-gtk-manual --collect /usr/libexec/xdg-desktop-portal-gtk'
# Bar: waybar, one per output, with kill-before-relaunch (see the script).
exec_always ~/.local/bin/waybar-launch.sh
# Wallpaper: swaybg restoring the saved pick (replaces nitrogen --restore).
exec_always ~/.local/bin/swaybg-restore.sh
# No picom (sway composites natively) and no snixembed (waybar has a native
# SNI tray) - both dropped.
exec ~/.local/bin/blueman-applet-guard.sh
exec /usr/libexec/lxqt-policykit-agent
exec copyq
exec udiskie --tray
exec gammastep
exec sh -c 'pgrep -x dunst >/dev/null || dunst'
exec sh -c 'pgrep -x playerctld >/dev/null || playerctld'
exec ~/.local/bin/calendar-reminder-daemon-launch.sh
exec ~/.local/bin/battwatch.sh
exec dex-autostart -a -e sway
exec ~/.local/bin/fix-mx-scroll.sh
# Idle/lock: swayidle replaces the xss-lock + xset s/dpms stack. Screensaver +
# lock at 20min; display off at 50min (strictly later, screensaver first);
# lock before sleep. Kept in a script so the timeouts are easy to tune.
exec_always ~/.local/bin/swayidle-launch.sh
SWAY_EOF
__xkb="$(localectl status 2>/dev/null | sed -n 's/.*X11 Layout: *//p' | head -1)"
sed -i "s/@@XKB_LAYOUT@@/${__xkb:-us}/" "$CONF/sway/config"
printf 'seat seat0 xcursor_theme %s 24\n' "$CURSOR_THEME_NAME" > "$CONF/sway/cursor-theme.conf"

# ----------------------------------------------------------------------------
# 5. picom
# ----------------------------------------------------------------------------
log "Writing picom config..."
mkdir -p "$CONF/picom"

# ----------------------------------------------------------------------------
# 6. Desktop theme collection - HANCORE-linux/waybar-themes
# ----------------------------------------------------------------------------
# This replaces the old embedded Catppuccin/polybar-port collection: the
# bar themes now come from github.com/HANCORE-linux/waybar-themes (MIT),
# fetched at install time and adapted from their Omarchy/Hyprland home to
# plain Sway on Fedora:
#   - hyprland/workspaces + hyprland/window -> sway/*; modules with no
#     equivalent here (omarchy logo, voxtype voice typing, the
#     $OMARCHY_PATH indicators, pacman update checker, gpu-usage) drop out
#   - omarchy-*/hyprctl/hyprpicker/alacritty/ghostty/wttrbar commands are
#     rewritten to this rice's own tools (app-menu, powermenu, wifi-menu,
#     colorpicker, osd-volume, caffeine/dnd toggles, software-update,
#     kitty, swaymsg) plus three shims written below (~/.local/bin)
#   - 85 of the styles @import ../omarchy/current/theme/waybar.css for
#     @background/@foreground/@transparent - hancore-theme-gen.py derives
#     a palette from each theme's own CSS and writes both that import
#     target and everything else the rice's switcher applies per theme:
#     rofi (.rasi + powermenu), kitty, dunst, starship and sway border
#     fragments, at the same paths the old collection used, so
#     ~/.local/bin/waybar-theme.sh switches the whole desktop per pick
#     exactly as before
#   - a [colors] ini per theme feeds the repo's GTK/Neovim/VS Code
#     generators (section 15); the clock module gets the old rice's
#     matching-GTK gnome-calendar click back
# The first theme (sorted) is seeded as active everywhere.
if [ "$CLEAN_THEMES" = "1" ]; then
  log "Cleaning out existing desktop themes (waybar/rofi/kitty/dunst/starship/borders/nvim/GTK)..."
  rm -rf "$CONF/waybar/themes" "$CONF/rofi/themes" "$CONF/kitty/themes" \
         "$CONF/dunst/themes" "$CONF/starship/themes" "$CONF/sway/themes" \
         "$CONF/polybar/themes"
  rm -f "$CONF/rofi/current.rasi" "$CONF/rofi/current-powermenu.rasi" \
         "$CONF/kitty/current.conf" "$CONF/dunst/dunstrc" \
         "$CONF/sway/current-borders.conf" "$CONF/starship.toml" \
         "$CONF/waybar/current-theme-name"
  if [ -d "$HOME/.themes" ]; then
    find "$HOME/.themes" -mindepth 1 -maxdepth 1 -type d -name 'Rice-*' -exec rm -rf {} + 2>/dev/null || true
  fi
  if [ -d "$CONF/nvim/colors" ]; then
    find "$CONF/nvim/colors" -maxdepth 1 -name 'rice-*.lua' -delete 2>/dev/null || true
  fi
  log "Old themes removed."
fi

log "Fetching HANCORE waybar themes (github.com/HANCORE-linux/waybar-themes)..."
HANCORE_TMP="$(mktemp -d)"
if git clone --depth 1 -q https://github.com/HANCORE-linux/waybar-themes.git "$HANCORE_TMP"; then
  log "Adapting themes for Sway + generating matching rofi/kitty/dunst/starship/border themes..."
  cat > "$HANCORE_TMP/hancore-theme-gen.py" <<'HANCOREGEN_EOF'
#!/usr/bin/env python3
"""Adapt HANCORE-linux/waybar-themes to this rice's Sway/Fedora setup.

For each theme dir in the clone's config/ (excluding "test"):
  1. Parse config.jsonc (JSONC: //- and /**/-comments, trailing commas,
     BOM/NUL bytes, multi-line escaped strings).
  2. Adapt it: hyprland/* modules -> sway/*, drop modules with no
     equivalent here (omarchy logo, voxtype, the $OMARCHY_PATH
     indicators, pacman updates, gpu-usage), rewrite omarchy-*/hyprctl/
     alacritty/ghostty/wttrbar/hyprpicker commands to this rice's own
     tools (shims live in ~/.local/bin), repoint bundled-script exec
     paths at the theme's own install dir, and give the clock a matching
     GTK gnome-calendar click like the old rice's bars had.
  3. Extract a role palette from style.css (+ locally-imported css like
     rose-pine.css + the config's calendar spans) by classifying every
     color against the 26 canonical Catppuccin Mocha roles in HLS space
     (same algorithm as the repo's generate-gtk-themes.py), falling back
     to canonical Mocha for roles a theme doesn't define.
  4. Write, into $DEST (an install root - normally $HOME):
       .config/waybar/themes/<n>/{config.jsonc,style.css,palette.css,+bundled scripts}
       .config/rofi/themes/<n>.rasi + <n>-powermenu.rasi
       .config/kitty/themes/<n>.conf
       .config/dunst/themes/<n>.dunstrc
       .config/starship/themes/<n>.toml
       .config/sway/themes/<n>.conf           (sway client.* borders)
       .config/polybar/themes/<n>.ini       ([colors] block - feeds the
         repo's generate-gtk/nvim/vscode-themes.py, exactly like the old
         rice's own themes)
     and seed the first theme (sorted) as the active one everywhere the
     switcher (~/.local/bin/waybar-theme.sh) looks for "current" files,
     including the Omarchy-format palette import at
     .config/omarchy/current/theme/waybar.css that 85 of the styles
     @import for @background/@foreground/@transparent.

Never aborts the whole run on one bad theme: each theme is wrapped, a
parse/rewrite failure just logs a skip line.

Usage: hancore-theme-gen.py <hancore-clone-dir> <dest-home>
"""
import colorsys
import json
import os
import pathlib
import re
import shutil
import sys

CLONE = pathlib.Path(sys.argv[1]).resolve()
DEST = pathlib.Path(sys.argv[2]).resolve()
CONF = DEST / ".config"

# ---------------------------------------------------------------- palette --
CANONICAL_MOCHA = {
    "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7", "mauve": "#cba6f7",
    "red": "#f38ba8", "maroon": "#eba0ac", "peach": "#fab387", "yellow": "#f9e2af",
    "green": "#a6e3a1", "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
    "blue": "#89b4fa", "lavender": "#b4befe", "text": "#cdd6f4", "subtext1": "#bac2de",
    "subtext0": "#a6adc8", "overlay2": "#9399b2", "overlay1": "#7f849c", "overlay0": "#6c7086",
    "surface2": "#585b70", "surface1": "#45475a", "surface0": "#313244", "base": "#1e1e2e",
    "mantle": "#181825", "crust": "#11111b",
}
NEUTRAL_ROLES = {
    "text", "subtext1", "subtext0", "overlay2", "overlay1", "overlay0",
    "surface2", "surface1", "surface0", "base", "mantle", "crust",
}


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hex_to_hls(h):
    r, g, b = (c / 255.0 for c in hex_to_rgb(h))
    return colorsys.rgb_to_hls(r, g, b)


def hue_dist(h1, h2):
    d = abs(h1 - h2) % 1.0
    return min(d, 1.0 - d)


_CANON = {role: hex_to_hls(v) for role, v in CANONICAL_MOCHA.items()}
_REVC = {v.lower(): k for k, v in CANONICAL_MOCHA.items()}


def classify(hexval):
    """Closest canonical Mocha role for a color (hue for chromatic,
    lightness-only among the neutral ramp for near-gray)."""
    hexval = hexval.lower()
    if hexval in _REVC:
        return _REVC[hexval]
    h, l, s = hex_to_hls(hexval)
    achromatic = s < 0.15
    best = None
    for role, (ch, cl, cs) in _CANON.items():
        if achromatic and role not in NEUTRAL_ROLES:
            continue
        dist = (abs(l - cl) if achromatic else
                hue_dist(h, ch) * 4.0 + abs(l - cl) + abs(s - cs) * 0.8)
        if best is None or dist < best[0]:
            best = (dist, role)
    return best[1]


def luminance(hexval):
    r, g, b = (c / 255.0 for c in hex_to_rgb(hexval))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def collect_colors(text, weight, acc):
    """Accumulate #hex/#rrggbbaa/rgb()/rgba() colors with a weight."""
    for m in re.findall(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", text):
        acc[m[:7].lower()] = acc.get(m[:7].lower(), 0) + weight
    for r, g, b in re.findall(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", text):
        h = "#{:02x}{:02x}{:02x}".format(int(r), int(g), int(b))
        acc[h] = acc.get(h, 0) + weight


def extract_palette(css_text, imported_texts, config_text):
    """Role -> resolved color for one theme."""
    acc = {}
    # @define-color values matter more (they're the theme's own vocabulary)
    defines = re.findall(r"@define-color\s+[\w-]+\s+(#[0-9a-fA-F]{6})", css_text)
    for d in defines:
        acc[d.lower()] = acc.get(d.lower(), 0) + 5
    collect_colors(css_text, 1, acc)
    for t in imported_texts:
        collect_colors(t, 4, acc)  # rose-pine.css etc. ARE the palette
    collect_colors(config_text, 1, acc)

    by_role = {}
    for hexval, w in acc.items():
        by_role.setdefault(classify(hexval), []).append((w, hexval))

    def pick(role, prefer_saturated=True):
        cands = by_role.get(role)
        if not cands:
            return CANONICAL_MOCHA[role]
        key = (lambda wh: (wh[0], hex_to_hls(wh[1])[2] if prefer_saturated else -hex_to_hls(wh[1])[2]))
        return max(cands, key=key)[1]

    # Neutrals: prefer the most prominent (frequent) representative.
    base = pick("base", prefer_saturated=False)
    mantle = pick("mantle", prefer_saturated=False)
    # Sensible ordering: mantle should be at least as dark as base.
    if luminance(mantle) > luminance(base):
        base, mantle = mantle, base
    text = pick("text", prefer_saturated=False)
    subtext = pick("subtext0", prefer_saturated=False)

    dark = luminance(base) < 0.5
    if dark:
        # Defensive contrast floor: some themes' CSS yields no light
        # neutral at all, and a dark-on-dark palette.css makes every
        # @fg-drawn label invisible except on hover (hover styles
        # invert colors). Guarantee readable text no matter what.
        if luminance(text) < luminance(base) + 0.3:
            lights = [h for h, w in acc.items()
                      if luminance(h) > luminance(base) + 0.3]
            text = max(lights, key=lambda h: acc[h]) if lights else CANONICAL_MOCHA["text"]
        if luminance(subtext) > luminance(text):
            subtext = text
    else:
        if luminance(text) > luminance(base) - 0.3:
            darks = [h for h, w in acc.items()
                     if luminance(h) < luminance(base) - 0.3]
            text = max(darks, key=lambda h: acc[h]) if darks else CANONICAL_MOCHA["crust"]
        if luminance(subtext) < luminance(text):
            subtext = text

    palette = {
        "base": base,
        "mantle": mantle,
        "surface0": pick("surface0", prefer_saturated=False),
        "surface1": pick("surface1", prefer_saturated=False),
        "surface2": pick("surface2", prefer_saturated=False),
        "text": text,
        "subtext": subtext,
        "red": pick("red"),
        "green": pick("green"),
        "yellow": pick("yellow"),
        "blue": pick("blue"),
        "cyan": pick("teal"),
        "teal": pick("teal"),
        "orange": pick("peach"),
        "pink": pick("pink"),
        "lavender": pick("lavender"),
    }
    # accent = the theme's own most prominent saturated color (frequency-
    # weighted), so rofi/kitty/dunst/borders/GTK all follow the accent the
    # bar actually shows - NOT a hardcoded mauve. Colors too close to the
    # base/foreground neutrals are skipped; themes that define no colors
    # of their own keep the canonical Mocha accent (their whole palette
    # IS Mocha then).
    best = None
    for hexval, w in acc.items():
        h, l, s = hex_to_hls(hexval)
        if s < 0.25:
            continue  # neutral ramp, not an accent
        if abs(luminance(hexval) - luminance(base)) < 0.12:
            continue  # too close to the background to read as an accent
        if abs(luminance(hexval) - luminance(text)) < 0.12:
            continue
        key = (w, s)
        if best is None or key > best[0]:
            best = (key, hexval)
    palette["accent"] = best[1] if best else CANONICAL_MOCHA["mauve"]
    return palette, dark, by_role


# ------------------------------------------------------------------ jsonc --
def strip_jsonc(text):
    """Remove //- and /**/-comments (string-aware) and trailing commas,
    plus any BOM/NUL garbage, so json.loads can parse config.jsonc."""
    text = text.replace("\x00", "").lstrip("﻿")
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            out.append(text[i:j + 1])
            i = j + 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    cleaned = "".join(out)
    # trailing commas before ] or }
    cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
    return cleaned


# ----------------------------------------------------------- config adapt --
DROP_MODULES = {
    "custom/omarchy",                       # omarchy logo font glyph + menu
    "custom/voxtype",                       # voice typing (no equivalent)
    "custom/idle-indicator",                # $OMARCHY_PATH indicator script
    "custom/screenrecording-indicator",
    "custom/updatespacman",                 # Arch-only pacman checker
    "custom/gpu-usage",                     # gpu-usage-waybar not on Fedora
}

RENAME_MODULES = {
    "hyprland/workspaces": "sway/workspaces",
    "hyprland/window": "sway/window",
}

CMD_REWRITES = [
    (re.compile(r"^omarchy-menu power$"), "~/.local/bin/powermenu.sh"),
    (re.compile(r"^omarchy-menu( system)?$"), "~/.local/bin/app-menu.sh"),
    (re.compile(r"^omarchy-launch-or-focus-tui (\S+)$"), r"kitty -e \1"),
    (re.compile(r"^omarchy-launch-floating-terminal-with-presentation omarchy-update$"),
     "~/.local/bin/software-update.sh"),
    (re.compile(r"^omarchy-launch-floating-terminal-with-presentation .*$"), "true"),
    (re.compile(r"^omarchy-launch-wifi$"), "~/.local/bin/wifi-menu.sh"),
    (re.compile(r"^omarchy-launch-bluetooth$"), "blueman-manager"),
    (re.compile(r"^omarchy-launch-audio$"), "~/.local/bin/osd-volume.sh"),
    (re.compile(r"^omarchy-toggle-idle$"), "~/.local/bin/caffeine-toggle.sh"),
    (re.compile(r"^omarchy-toggle-notification-silencing$"), "~/.local/bin/dnd-toggle.sh"),
    (re.compile(r"^omarchy-update-available$"), "~/.local/bin/hancore-update-check"),
    (re.compile(r"^omarchy-theme-current$"), "cat ~/.config/waybar/current-theme-name"),
    (re.compile(r"^omarchy-theme-set( \S+)?$"), "~/.local/bin/waybar-theme.sh"),
    (re.compile(r"^omarchy-battery-status$"), "~/.local/bin/hancore-battery-status"),
    (re.compile(r'^notify-send -u low "\$\(omarchy-battery-status\)"$'),
     'notify-send -u low "$(~/.local/bin/hancore-battery-status)"'),
    (re.compile(r"^omarchy-capture-screenrecording$"), "~/.local/bin/screenshot.sh"),
    (re.compile(r"^omarchy-cmd-screenrecord$"), "~/.local/bin/screenshot.sh"),
    (re.compile(r"^omarchy-cmd-tzupdate$"), "true"),
    (re.compile(r"^hyprctl dispatch workspace e\+1$"), "swaymsg workspace next_on_output"),
    (re.compile(r"^hyprctl dispatch workspace e-1$"), "swaymsg workspace prev_on_output"),
    (re.compile(r"^hyprpicker$"), "~/.local/bin/colorpicker.sh"),
    (re.compile(r"^alacritty --class=Impala -e impala$"), "~/.local/bin/wifi-menu.sh"),
    (re.compile(r"^alacritty --class=Wiremix -e wiremix$"), "~/.local/bin/osd-volume.sh"),
    (re.compile(r"^wiremix$"), "~/.local/bin/osd-volume.sh"),
    (re.compile(r"^xdg-terminal-exec$"), "kitty"),
    (re.compile(r"^ghostty -e nvtop$"), "kitty -e btop"),
]

# bundled per-theme scripts referenced by ~/.config/waybar/<file> paths
BUNDLED_SCRIPTS = ("window_pill.py", "cava.sh", "scrolling-mpris.py")

LAYOUT_KEYS = ("modules-left", "modules-center", "modules-right")


def rewrite_cmd(cmd, name):
    """One command string, adapted. Order: bundled-script paths first
    (substring, they appear mid-command too), then exact rewrites."""
    for script in BUNDLED_SCRIPTS:
        cmd = cmd.replace(
            "~/.config/waybar/" + script,
            "~/.config/waybar/themes/%s/%s" % (name, script))
    for pat, repl in CMD_REWRITES:
        if pat.match(cmd):
            return pat.sub(repl, cmd)
    return cmd


def rewrite_value(v, name):
    if isinstance(v, str):
        return rewrite_cmd(v, name)
    if isinstance(v, dict):
        return {k: rewrite_value(x, name) for k, x in v.items()}
    if isinstance(v, list):
        return [rewrite_value(x, name) for x in v]
    return v


def unresolvable(block):
    """A module block that still references Omarchy/Hyprland machinery
    after rewriting has no equivalent here - drop the module."""
    return "omarchy" in block or "$OMARCHY_PATH" in block or "hyprctl" in block


def adapt_config(cfg, name):
    """Restructure one parsed waybar config for this rice. Drops are
    reported, never fatal."""
    dropped = []

    # 1. Rename hyprland/* module blocks to their sway/* equivalents.
    for old, new in RENAME_MODULES.items():
        if old in cfg:
            cfg[new] = cfg.pop(old)

    def fixlist(arr):
        return [RENAME_MODULES.get(m, m) for m in arr]

    for lk in LAYOUT_KEYS:
        if isinstance(cfg.get(lk), list):
            cfg[lk] = fixlist(cfg[lk])
    for block in cfg.values():
        if isinstance(block, dict) and isinstance(block.get("modules"), list):
            block["modules"] = fixlist(block["modules"])

    # 2. Rewrite every command string in every module block.
    for key in list(cfg):
        block = cfg[key]
        if isinstance(block, dict):
            cfg[key] = rewrite_value(block, name)

    # 3b. clock clicks, universal for every theme: left click keeps
    #     waybar's built-in format-alt toggle - defining a module-level
    #     on-click command would make waybar run it AND the toggle, which
    #     is exactly the "format changes AND the calendar opens" bug - so
    #     the clock gets NO on-click command at all. Right click opens
    #     the floating, theme-matched gnome-calendar instead.
    for ck in ("clock", "custom/clock"):
        block = cfg.get(ck)
        if isinstance(block, dict):
            block.pop("on-click", None)
            block.pop("actions", None)
            cal = block.get("calendar")
            if isinstance(cal, dict):
                cal.pop("on-click", None)
                cal.pop("on-click-right", None)
            block["on-click-right"] = "GTK_THEME=Rice-%s gnome-calendar" % name

    # 3b. custom/update: restore the old rice's update widget exactly -
    #     a visible pending-update COUNT (polybar-updates.sh style, incl.
    #     0) and a click that opens software-update.sh in a floating
    #     kitty (the sway config already has the UpdatesTask floating
    #     rule). The upstream module only shows a static omarchy glyph.
    upd = cfg.get("custom/update")
    if isinstance(upd, dict):
        cfg["custom/update"] = {
            "exec": "~/.local/bin/hancore-update-check",
            "format": "{}",
            "tooltip": False,
            "on-click": "kitty --class UpdatesTask -e ~/.local/bin/software-update.sh",
        }

    # 3c. idle_inhibitor -> custom/caffeine: the native module is an
    #     independent Wayland inhibitor that never reflected the rice's
    #     Mod+C caffeine toggle (two mechanisms, no shared state).
    #     Replace it everywhere with a widget backed by
    #     ~/.local/bin/caffeine-state.sh, so one mechanism (caffeine)
    #     drives both the keybind and the bar, and the icon always shows
    #     the real state. Clicking the widget runs the same toggle.
    for lk in ("modules-left", "modules-center", "modules-right"):
        arr = cfg.get(lk)
        if isinstance(arr, list):
            cfg[lk] = ["custom/caffeine" if m == "idle_inhibitor" else m
                       for m in arr]
    for key, block in list(cfg.items()):
        if isinstance(block, dict) and isinstance(block.get("modules"), list):
            block["modules"] = ["custom/caffeine" if m == "idle_inhibitor" else m
                                for m in block["modules"]]
    cfg.pop("idle_inhibitor", None)
    cfg["custom/caffeine"] = {
        "exec": "~/.local/bin/caffeine-state.sh",
        "return-type": "json",
        "interval": 2,
        "on-click": "~/.local/bin/caffeine-toggle.sh",
        "tooltip": True,
    }

    # 3d. mpris: pin interval to 1s. The module is event-driven by default
    #     (interval 0 = refresh only on MPRIS property changes), but the
    #     {dynamic} text (artist/position/length rotation) only advances on
    #     interval ticks - themes shipping interval 5 made the now-playing
    #     widget visibly laggy: its text updated in 5-second jumps. 1s keeps
    #     the position ticking and the rotation smooth; track changes
    #     still arrive instantly via events.
    if isinstance(cfg.get("mpris"), dict):
        cfg["mpris"]["interval"] = 1

    # 3f. custom/weather: clicking the bar's weather widget opens the full
    #     wttr.in 3-day forecast in a floating, theme-colored kitty (the sway
    #     config has the WeatherFloat floating rule). Same wttr.in source the
    #     wttrbar widget already uses, just the whole report instead of today's
    #     temperature.
    wx = cfg.get("custom/weather")
    if isinstance(wx, dict):
        wx["on-click"] = "~/.local/bin/weather-float.sh"

    # 3f2. cpu/memory: raise the "warning" (orange background) threshold from the
    #      upstream 50% to 70%, so the widget only warms up under real sustained
    #      load instead of on routine half-usage. "critical" (red) stays at 80.
    for mk in ("cpu", "memory"):
        blk = cfg.get(mk)
        if isinstance(blk, dict) and isinstance(blk.get("states"), dict) \
                and "warning" in blk["states"]:
            blk["states"]["warning"] = 70

    # 3e. custom/notification-silencing-indicator: keep upstream's DND
    #     indicator module (previously dropped with the other omarchy
    #     modules) so the bar always shows a small bell - normal text
    #     color while notifications flow, the theme accent while muted -
    #     muted via Mod+N / ~/.local/bin/dnd-toggle.sh, on every theme.
    #     Backed by ~/.local/bin/dnd-indicator.sh reading dunst's pause
    #     state; dnd-toggle.sh pings signal 10 so the widget flips
    #     instantly, with a slow interval poll as a safety net in case
    #     the state was changed any other way. Step 7 below guarantees
    #     the module ends up in a layout on every theme.
    cfg["custom/notification-silencing-indicator"] = {
        "exec": "~/.local/bin/dnd-indicator.sh",
        "return-type": "json",
        "signal": 10,
        "interval": 30,
        "tooltip": True,
        "on-click": "~/.local/bin/dnd-toggle.sh",
    }

    # 4. Drop module blocks with no equivalent: the known set, plus any
    #    block that still references omarchy/$OMARCHY_PATH/hyprctl.
    #    Groups (blocks with a "modules" list) are deliberately NOT
    #    evaluated here: their children still name the modules being
    #    dropped, so the group's JSON would look unresolvable and the
    #    whole group - surviving children like clock and weather
    #    included - went away with it. Groups are handled by step 5,
    #    after their children are pruned.
    module_keys = [k for k, v in cfg.items()
                   if isinstance(v, dict) and k not in LAYOUT_KEYS]
    drop = set()
    for key in module_keys:
        block = cfg[key]
        if isinstance(block.get("modules"), list):
            continue
        if key in DROP_MODULES or unresolvable(json.dumps(block)):
            drop.add(key)
            dropped.append(key)
    for key in drop:
        cfg.pop(key, None)

    # 5. Drop them from the layouts, and drop groups whose children all
    #    went away (an empty group renders nothing but may still draw a
    #    background pill in some styles), or that still reference
    #    omarchy/$OMARCHY_PATH/hyprctl in their OWN settings after the
    #    children were pruned. Iterate to a fixpoint so nested groups
    #    are handled whatever order they appear in.
    def prune(arr):
        return [m for m in arr if m not in drop]

    for lk in LAYOUT_KEYS:
        if isinstance(cfg.get(lk), list):
            cfg[lk] = prune(cfg[lk])
    changed = True
    while changed:
        changed = False
        for key in list(cfg):
            block = cfg.get(key)
            if not (isinstance(block, dict)
                    and isinstance(block.get("modules"), list)):
                continue
            block["modules"] = prune(block["modules"])
            if (not block["modules"] or key in DROP_MODULES
                    or unresolvable(json.dumps(block))):
                cfg.pop(key, None)
                drop.add(key)
                dropped.append(key)
                changed = True

    # 6. Sweep the layout lists for any name whose block is gone (e.g.
    #    drawer children removed via DROP_MODULES in step 4's parent).
    present = set(k for k, v in cfg.items() if isinstance(v, dict))
    for lk in LAYOUT_KEYS:
        arr = cfg.get(lk)
        if isinstance(arr, list):
            cfg[lk] = [m for m in arr
                       if not m.startswith(("custom/", "group/")) or m in present]

    # 7. The DND indicator must end up in a layout on every theme. The
    #    upstream module may have been dropped out of its layout as group
    #    collateral (step 4 marks a whole group unresolvable while its
    #    children still name dropped modules), so check AFTER all the
    #    dropping and append to modules-center when nothing survived.
    def _dnd_in(seq):
        return (isinstance(seq, list)
                and "custom/notification-silencing-indicator" in seq)
    if not any(_dnd_in(cfg.get(lk)) for lk in LAYOUT_KEYS) and not any(
            isinstance(b, dict) and _dnd_in(b.get("modules"))
            for b in cfg.values()):
        center = cfg.get("modules-center")
        if not isinstance(center, list):
            center = []
            cfg["modules-center"] = center
        center.append("custom/notification-silencing-indicator")
    return cfg, dropped


# ---------------------------------------------------------------- templates ---
def strip_gtk4_at_rules(css_text):
    """Remove @keyframes blocks (and any other GTK4-only at-rule blocks).
    waybar is GTK3, whose CSS parser has no @keyframes - and it silently
    discards EVERYTHING after the first one in the file: with them left
    in place, every rule below the first @keyframes (including the
    workspace-state block this installer appends) never applied. The
    animations never ran on waybar anyway - dead code even upstream,
    where these themes were built for the same GTK3 waybar."""
    out = []
    skipping = False
    depth = 0
    for ln in css_text.split("\n"):
        stripped = ln.lstrip()
        if not skipping and stripped.startswith("@keyframes"):
            skipping = True
            depth = ln.count("{") - ln.count("}")
            if depth <= 0:  # single-line block
                skipping = False
            continue
        if skipping:
            depth += ln.count("{") - ln.count("}")
            if depth <= 0:
                skipping = False
            continue
        out.append(ln)
    return "\n".join(out)


def mix(h1, h2, t):
    """Linear mix between two hex colors, t in [0, 1]."""
    a = hex_to_rgb(h1)
    b = hex_to_rgb(h2)
    return "#{:02x}{:02x}{:02x}".format(
        *(round(x + (y - x) * t) for x, y in zip(a, b)))


def starship_colors(palette, by_role):
    """The prompt's six segment colors, derived the way the old rice's
    starship theming derived them: the base background stepped toward
    the foreground (lightened on dark themes, darkened on light ones) in
    two further steps for the neutral username/directory/git segments,
    then the theme's own cyan/magenta/blue for the language-icon/
    docker/time segments. A theme that defines none of those three hues
    (most HANCORE styles carry one accent only) falls back to the theme's
    own accent plus two mixes of it, so the prompt still follows the bar
    instead of snapping back to stock Catppuccin pastels."""
    has = lambda *roles: any(r in by_role for r in roles)
    p = dict(palette)
    p["seg_mid"] = mix(p["base"], p["text"], 0.15)
    p["seg_high"] = mix(p["base"], p["text"], 0.30)
    p["star_cyan"] = p["cyan"] if has("teal", "sky") else p["accent"]
    p["star_pink"] = p["pink"] if has("pink", "lavender") else mix(p["accent"], p["text"], 0.30)
    p["star_blue"] = p["blue"] if has("blue", "sapphire") else mix(p["accent"], "#000000", 0.30)
    return p


def extract_design(css_text):
    """Design tokens from the theme's own style.css, so the generated
    rofi/dunst themes follow the bar's look (corner rounding, font) the
    same way the old rice's hand-made per-theme files did. Radius = the
    most common border-radius in the stylesheet (module pills dominate);
    a 50%/pill bar gets generously rounded menus. Font = the first
    font-family the style declares."""
    radii = re.findall(r"border-radius:\s*([\d.]+)px", css_text)
    radius = 12
    if radii:
        radius = int(float(max(set(radii), key=radii.count)))
    elif re.search(r"border-radius:\s*50%", css_text):
        radius = 20
    if radius >= 40:  # pill-style caps - keep menus rounded but sane
        radius = 20
    radius = max(0, min(radius, 20))
    m = re.search(r"font-family:\s*['\"]([^'\"]+)['\"]", css_text)
    font = m.group(1) if m else "JetBrainsMono Nerd Font"
    return radius, font


ROFI_TEMPLATE = """* {{
    base: {base}ff;
    mantle: {mantle}ff;
    text: {text}ff;
    subtext: {subtext}ff;
    accent: {accent}ff;
    surface0: {surface0}ff;

    background-color: @base;
    text-color: @text;
    font: "{font} 11";
}}

window {{
    width: 30%;
    border-radius: {radius}px;
    background-color: @base;
}}

inputbar {{
    padding: 10px;
    background-color: @mantle;
    border-radius: {elem_radius}px;
    children: [prompt, entry];
}}

prompt {{ text-color: @accent; padding: 0 8px 0 0; }}
entry  {{ text-color: @text; }}

listview {{
    lines: 14;
    padding: 8px 0;
}}

element {{
    padding: 6px 10px;
    border-radius: {elem_radius}px;
}}
element-text, element-icon {{
    background-color: inherit;
    text-color: inherit;
}}

element selected {{
    background-color: @surface0;
    text-color: @accent;
}}
"""

ROFI_POWERMENU_TEMPLATE = """* {{
    base: {base}ff;
    mantle: {mantle}ff;
    text: {text}ff;
    subtext: {subtext}ff;
    accent: {accent}ff;
    surface0: {surface0}ff;

    background-color: @base;
    text-color: @text;
    font: "{font} 11";
}}

window {{
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
    border-radius: {radius}px;
    padding: 24px;
}}

mainbox {{
    children: [ listview ];
}}

listview {{
    columns: 5;
    lines: 1;
    spacing: 10px;
    fixed-columns: true;
    scrollbar: false;
}}

element {{
    children: [ element-text ];
    padding: 26px;
    border-radius: {elem_radius}px;
    background-color: @mantle;
}}
element normal.normal {{
    text-color: @text;
}}
element selected {{
    background-color: @surface0;
    border: 2px;
    border-color: @accent;
    border-radius: {elem_radius}px;
}}
element-text {{
    font: "{font} 26";
    background-color: transparent;
    text-color: inherit;
    horizontal-align: 0.32;
    vertical-align: 0.5;
}}
"""

KITTY_TEMPLATE = """# {name}
foreground              {text}
background              {base}
selection_foreground    {base}
selection_background    {text}
cursor                  {accent}
cursor_text_color       {base}

color0  {surface1}
color8  {surface2}
color1  {red}
color9  {red}
color2  {green}
color10 {green}
color3  {yellow}
color11 {yellow}
color4  {blue}
color12 {blue}
color5  {pink}
color13 {pink}
color6  {cyan}
color14 {cyan}
color7  {text}
color15 {subtext}
"""

DUNST_TEMPLATE = """[global]
font = {font} 10
frame_width = 2
frame_color = "{accent}"
corner_radius = {radius}
background = "{base}"
foreground = "{text}"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "{surface1}"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "{base}"
foreground = "{subtext}"
frame_color = "{surface1}"
timeout = 4

[urgency_normal]
background = "{base}"
foreground = "{text}"
frame_color = "{accent}"
timeout = 6

[urgency_critical]
background = "{base}"
foreground = "{red}"
frame_color = "{red}"
timeout = 0
"""

STARSHIP_TEMPLATE = r'''format = """
[]({base})\
$python\
$username\
[](bg:{seg_mid} fg:{base})\
$directory\
[](fg:{seg_mid} bg:{seg_high})\
$git_branch\
$git_status\
[](fg:{seg_high} bg:{star_cyan})\
$c\
$elixir\
$elm\
$golang\
$haskell\
$java\
$julia\
$nodejs\
$nim\
$rust\
[](fg:{star_cyan} bg:{star_pink})\
$docker_context\
[](fg:{star_pink} bg:{star_blue})\
$time\
[ ](fg:{star_blue})\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:{base}"
style_root = "bg:{base}"
format = '[$user ]($style)'

[directory]
style = "bg:{seg_mid}"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = "  "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important  " = "  "

[c]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:{star_pink}"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:{seg_high}"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:{seg_high}"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:{base}"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:{star_blue}"
format = '[ $time ]($style)'
'''

# sway client.* border colors
BORDERS_TEMPLATE = """client.focused          {accent}  {base}  {text}  {accent}   {accent}
client.unfocused        {surface1}  {base}  {subtext}  {surface1}   {surface1}
client.focused_inactive {surface2}  {base}  {subtext}  {surface2}   {surface2}
client.urgent           {red}  {base}  {red}  {red}   {red}
"""

# [colors] ini feeding the repo's generate-{gtk,nvim,vscode}-themes.py.
# Every ROLE_CHAINS key is present so the chains always resolve.
COLORS_INI_TEMPLATE = """[colors]
; Palette extracted from the {name} waybar theme's style.css.
base = {base}
mantle = {mantle}
surface0 = {surface0}
surface1 = {surface1}
surface2 = {surface2}
text = {text}
subtext = {subtext}
red = {red}
green = {green}
yellow = {yellow}
blue = {blue}
purple = {accent}
magenta = {accent}
indigo = {accent}
teal = {cyan}
cyan = {cyan}
sky = {cyan}
peach = {orange}
orange = {orange}
pink = {pink}
lavender = {lavender}
"""

# Omarchy-format palette import: what the themes' own
# @import "../omarchy/current/theme/waybar.css" resolves against.
PALETTE_CSS_TEMPLATE = """/* Generated from the {name} theme's own colors - this is what the
   HANCORE styles' @import "../omarchy/current/theme/waybar.css"
   resolves against on this (non-Omarchy) install. */
@define-color background {base};
@define-color foreground {text};
@define-color accent {accent};
@define-color transparent rgba(0, 0, 0, 0);
@define-color border-inactive {surface1};
@define-color cava-fg {accent};

/* Base text color. Many HANCORE styles never set `color:` on their
   module widgets, leaving value text (module percentages etc.) to the
   GTK fallback foreground - near-black when GTK_THEME doesn't resolve
   (invisible on a dark bar, except on hover where the styles do set
   colors). Set at the window level so unstyled widgets INHERIT it
   (every explicit color rule in the theme's own CSS still wins); a
   bare `*` universal-selector rule was tried here first and KILLS
   every rule after it in GTK3's parser (verified live) - do not use
   a `*` rule in these stylesheets. */
window#waybar {{
  color: @foreground;
}}
"""

# Universal workspace-state colors, appended to EVERY theme's style.css
# with the palette's CONCRETE colors (not @accent references - the four
# rose-pine themes don't import the palette file, and appended rules must
# work in all 89). The HANCORE styles were written for Hyprland's class
# names (.active); sway/workspaces emits .focused/.urgent, so without this
# block most themes show no focused-workspace color at all. Sitting at the
# end of the sheet gives these rules the win at equal specificity, so a
# theme's own (hyprland-named) rules stay harmless where they overlap.
WORKSPACE_STATES_CSS = """/* --- appended by this rice's installer: universal workspace states ---
   The upstream styles target Hyprland's class names; sway/workspaces
   uses .focused/.urgent, so the active desktop and any workspace with an
   attention-needing window (xdg-activation, urgency hints) get explicit
   colors here, derived from this theme's own palette. Note: this
   system's waybar marks the current workspace with .visible (verified
   by probe: the class moves with focus; .focused/.active are never
   emitted by sway/workspaces here) - all three are styled so the block
   also works on waybar builds that do use .focused/.active. Urgent is
   the theme accent as a filled pill (bold, base text) so it reads as
   attention while staying in the theme's own color language - and
   stays distinct from the focused workspace, which is accent TEXT on
   no background. */
window#waybar #workspaces button.focused,
window#waybar #workspaces button.active,
window#waybar #workspaces button.visible {
  color: @ACCENT@;
}
window#waybar #workspaces button.urgent {
  color: @BASE@;
  background-color: @ACCENT@;
  font-weight: bold;
}
/* Caffeine widget (custom/caffeine, replacing the native idle_inhibitor):
   activated = the rice's stay-awake is on (Mod+C or clicking the widget),
   flagged in the theme accent so it reads at a glance. The light-bulb
   glyph is one of the tallest Nerd Font icons - at the themes' base font
   size with their zero padding it overflows the label box and gets
   clipped at the bar edge (verified live on v7.2) - so pin a smaller
   font and side padding for it. */
window#waybar #custom-caffeine {
  font-size: 12px;
  padding: 0 4px;
}
window#waybar #custom-caffeine.activated {
  color: @ACCENT@;
}
/* DND widget (custom/notification-silencing-indicator): a small bell,
   always shown - the theme's normal text color while notifications
   flow, the theme accent while they're muted (Mod+N). This overrides
   the themes' own muted-grey .active rule (specificity: window#waybar
   #id beats #id, and this block sits last in the sheet anyway). */
window#waybar #custom-notification-silencing-indicator.active {
  color: @ACCENT@;
}
"""


# Sway port of the themes' bundled window_pill.py (drops the hyprctl /
# Hyprland-socket2 dependency, takes the pill's two hardcoded text
# colors from the theme's palette).
WINDOW_PILL_TEMPLATE = r"""#!/usr/bin/env python3
# Sway port of HANCORE's bundled window_pill.py (was: hyprctl activewindow +
# Hyprland socket2). Polls swaymsg -t get_tree twice a second; the pill's two
# text colors come from this theme's palette.
import html
import json
import re
import subprocess
import time

MAX_TITLE_LEN = 42
TOP_FG = "@ACCENT@"
BOTTOM_FG = "@TEXT@"


def focused_node(tree):
    if tree.get("focused"):
        return tree
    for node_type in ("nodes", "floating_nodes"):
        for child in tree.get(node_type, []):
            hit = focused_node(child)
            if hit is not None:
                return hit
    return None


def print_status():
    try:
        tree = json.loads(subprocess.check_output(
            ["swaymsg", "-t", "get_tree"], text=True,
            stderr=subprocess.DEVNULL))
    except Exception:
        tree = {}

    node = focused_node(tree)
    if node is not None and (node.get("app_id") or node.get("window_properties", {}).get("class")):
        top_line = node.get("app_id") or node.get("window_properties", {}).get("class")
        title = node.get("name", "") or ""
        app_class = (top_line or "").lower()
        if "discord" in app_class or "vesktop" in app_class:
            title = re.sub(r"^\(\d+\)\s*", "", title)
            title = re.sub(r"^Discord\s*\|\s*", "", title)
        if len(title) > MAX_TITLE_LEN:
            title = title[:MAX_TITLE_LEN - 3] + "..."
        bottom_line = title
    else:
        top_line = "Desktop"
        bottom_line = "\u00A0"
        try:
            workspaces = json.loads(subprocess.check_output(
                ["swaymsg", "-t", "get_workspaces"], text=True,
                stderr=subprocess.DEVNULL))
            for ws in workspaces:
                if ws.get("focused"):
                    top_line = "Workspace %s" % ws.get("name", "?")
        except Exception:
            pass

    top_line = html.escape(top_line or "")
    bottom_line = html.escape(bottom_line)
    text = (
        "<span size='small' foreground='%s' rise='-1000'>%s</span>\n"
        "<span size='7500' weight='bold' foreground='%s'>%s</span>"
        % (TOP_FG, top_line, BOTTOM_FG, bottom_line)
    )
    print(json.dumps({
        "text": text,
        "class": "custom-window",
        "tooltip": "%s: %s" % (top_line, bottom_line),
    }), flush=True)


while True:
    print_status()
    time.sleep(0.5)
"""


def write_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def process_theme(src_dir, name):
    cfg_path = src_dir / "config.jsonc"
    raw = cfg_path.read_bytes().decode("utf-8", errors="replace")
    cfg = json.loads(strip_jsonc(raw))
    cfg, _dropped = adapt_config(cfg, name)

    css_text = (src_dir / "style.css").read_text(errors="replace")
    css_text = strip_gtk4_at_rules(css_text)

    # locally-imported css files (./rose-pine.css)
    imported = []
    for m in re.findall(r'@import\s+"([^"]+)"', css_text):
        p = (src_dir / m).resolve()
        if p.is_file():
            imported.append(p.read_text(errors="replace"))

    palette, dark, by_role = extract_palette(css_text, imported, raw)
    radius, font = extract_design(css_text)
    palette["radius"] = radius
    palette["elem_radius"] = max(0, radius - 4)
    palette["font"] = font

    tdir = CONF / "waybar" / "themes" / name
    tdir.mkdir(parents=True, exist_ok=True)

    out_cfg = json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"
    write_text(tdir / "config.jsonc", out_cfg)
    # Replace the upstream "@import ../omarchy/current/theme/waybar.css"
    # with the palette INLINED: waybar's own css-import preprocessing pass
    # (its "[debug] Parsing imports" step) mangles the rest of the
    # stylesheet when the import is present - every rule after the import
    # line, including the workspace block appended below, silently never
    # applied. Inlining the @define-colors (and the base-text-color rule)
    # sidesteps waybar's importer entirely. Verified live: identical css
    # with the import line removed renders the focused-workspace
    # indicator; with it, nothing after it applies.
    palette_inline = re.sub(r"^/\*.*?\*/\s*", "",
                            PALETTE_CSS_TEMPLATE.format(name=name, **palette),
                            flags=re.S).rstrip("\n")
    css_text = re.sub(r'^@import\s+"[^"]*omarchy[^"]*"\s*;?\s*$',
                      palette_inline, css_text, count=1, flags=re.M)
    ws_css = (WORKSPACE_STATES_CSS
              .replace("@ACCENT@", palette["accent"])
              .replace("@BASE@", palette["base"]))
    write_text(tdir / "style.css", css_text.rstrip("\n") + "\n" + ws_css)
    write_text(tdir / "palette.css", PALETTE_CSS_TEMPLATE.format(name=name, **palette))

    # bundled extras (scripts + imported css), screenshots excluded
    for f in src_dir.iterdir():
        if f.name.endswith(".png") or f.name in ("config.jsonc", "style.css"):
            continue
        if f.is_file():
            if f.name == "window_pill.py":
                write_text(tdir / f.name,
                           WINDOW_PILL_TEMPLATE.replace("@ACCENT@", palette["accent"]).replace("@TEXT@", palette["text"]))
            else:
                shutil.copy2(f, tdir / f.name)
            if f.name.endswith((".py", ".sh")):
                (tdir / f.name).chmod(0o755)

    p = palette
    write_text(CONF / "rofi" / "themes" / (name + ".rasi"),
               ROFI_TEMPLATE.format(**p))
    write_text(CONF / "rofi" / "themes" / (name + "-powermenu.rasi"),
               ROFI_POWERMENU_TEMPLATE.format(**p))
    write_text(CONF / "kitty" / "themes" / (name + ".conf"),
               KITTY_TEMPLATE.format(name=name, **p))
    write_text(CONF / "dunst" / "themes" / (name + ".dunstrc"),
               DUNST_TEMPLATE.format(**p))
    write_text(CONF / "starship" / "themes" / (name + ".toml"),
               STARSHIP_TEMPLATE.format(**starship_colors(palette, by_role)))
    write_text(CONF / "sway" / "themes" / (name + ".conf"),
               BORDERS_TEMPLATE.format(**p))
    write_text(CONF / "polybar" / "themes" / (name + ".ini"),
               COLORS_INI_TEMPLATE.format(name=name, **p))
    return len(json.dumps(cfg)), dark


def main():
    src_conf = CLONE / "config"
    names = []
    for d in sorted(src_conf.iterdir()):
        if not d.is_dir() or d.name == "test" or not (d / "config.jsonc").is_file():
            continue
        names.append(d.name.lower())
    if not names:
        print("no themes found in %s" % src_conf)
        return 1

    ok, failed = [], []
    for d in sorted(src_conf.iterdir()):
        if not d.is_dir() or d.name == "test" or not (d / "config.jsonc").is_file():
            continue
        name = d.name.lower()
        try:
            process_theme(d, name)
            ok.append(name)
            print("theme %s: installed" % name)
        except Exception as e:
            failed.append(name)
            print("theme %s: FAILED (%s)" % (name, e))

    # seed the first theme as active everywhere the switcher looks
    if ok:
        name = ok[0]
        t = CONF / "waybar" / "themes" / name
        shutil.copy2(t / "config.jsonc", CONF / "waybar" / "config.jsonc")
        shutil.copy2(t / "style.css", CONF / "waybar" / "style.css")
        # copy any sibling .css the style.css @imports by relative path (e.g.
        # rose-pine.css / colors.css) so the import resolves from ~/.config/waybar/
        for extra in t.glob("*.css"):
            if extra.name != "style.css":
                shutil.copy2(extra, CONF / "waybar" / extra.name)
        om = CONF / "omarchy" / "current" / "theme"
        om.mkdir(parents=True, exist_ok=True)
        shutil.copy2(t / "palette.css", om / "waybar.css")
        (CONF / "sway").mkdir(parents=True, exist_ok=True)
        shutil.copy2(CONF / "sway" / "themes" / (name + ".conf"),
                     CONF / "sway" / "current-borders.conf")
        shutil.copy2(CONF / "rofi" / "themes" / (name + ".rasi"), CONF / "rofi" / "current.rasi")
        shutil.copy2(CONF / "rofi" / "themes" / (name + "-powermenu.rasi"),
                     CONF / "rofi" / "current-powermenu.rasi")
        shutil.copy2(CONF / "kitty" / "themes" / (name + ".conf"), CONF / "kitty" / "current.conf")
        shutil.copy2(CONF / "dunst" / "themes" / (name + ".dunstrc"), CONF / "dunst" / "dunstrc")
        st_toml = CONF / "starship.toml"
        if st_toml.is_symlink():
            # don't write through e.g. mybash's symlinked starship.toml
            st_toml.unlink()
        shutil.copy2(CONF / "starship" / "themes" / (name + ".toml"), st_toml)
        write_text(CONF / "waybar" / "current-theme-name", name + "\n")
        print("active theme seeded: %s" % name)

    print("done: %d installed, %d failed" % (len(ok), len(failed)))
    return 0 if not failed else 2


if __name__ == "__main__":
    sys.exit(main())
HANCOREGEN_EOF
  HANCORE_OUT="$(python3 -I "$HANCORE_TMP/hancore-theme-gen.py" "$HANCORE_TMP" "$HOME" 2>&1)" \
    || warn "Theme adaptation reported failures:$(printf '%s\n' "$HANCORE_OUT" | tail -5)"
  log "$(printf '%s\n' "$HANCORE_OUT" | tail -2 | head -1)"
  unset HANCORE_OUT
else
  warn "git clone of HANCORE-linux/waybar-themes failed (network issue?) - no bar themes installed; re-run this script later."
fi
rm -rf "$HANCORE_TMP"

# Helper shims the adapted themes' modules exec by name - installed into
# ~/.local/bin, which waybar-launch.sh puts on the bar's PATH.
log "Writing theme helper shims (wttrbar, battery status, update check)..."
cat > "$BIN/wttrbar" <<'HANCORESHIM_EOF'
#!/usr/bin/env python3
"""wttrbar shim for the HANCORE waybar themes.

The real wttrbar (github.com/bcazaux/wttrbar) is a Go binary not packaged
for Fedora. This implements the subset of its CLI the HANCORE configs use
(--nerd, --location <name>, --custom-indicator <json>, --fahrenheit) and
its JSON output shape, so the themes' custom/weather modules work as-is.

fetches wttr.in's ?format=j1 (like the real tool), maps the current
condition to a Nerd Font glyph, and prints one JSON line:
  {"text": "15°", "alt": "Sunny", "tooltip": "Sunny: 15°C (feels 14°)"}

Called by waybar every 60s; a fetch failure prints the last good value
when cached, else an empty placeholder so the module just hides.
"""
import json
import sys
import urllib.request

NERD_ICONS = [
    ("thunder", "󰖝"), ("lightning", "󰖝"), ("storm", "󰖝"),
    ("snow", "󰖜"), ("sleet", "󰖞"), ("blizzard", "󰖜"),
    ("rain", "󰖗"), ("drizzle", "󰖗"), ("shower", "󰖗"), ("pouring", "󰖗"),
    ("fog", "󰖔"), ("mist", "󰖔"), ("haze", "󰖔"),
    ("overcast", "󰖕"), ("cloudy", "󰖒"),
    ("sunny", "󰖳"), ("clear", "󰖳"),
]
FALLBACK_ICON = "󰖒"


def parse_args(argv):
    opts = {"location": None, "nerd": False, "fahrenheit": False,
            "custom_indicator": None, "main-indicator": "weatherDesc"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--nerd":
            opts["nerd"] = True
        elif a == "--fahrenheit":
            opts["fahrenheit"] = True
        elif a in ("--location", "--loc") and i + 1 < len(argv):
            opts["location"] = argv[i + 1]
            i += 1
        elif a.startswith("--location="):
            opts["location"] = a.split("=", 1)[1]
        elif a in ("--custom-indicator", "--custom-indicator-text") and i + 1 < len(argv):
            try:
                opts["custom_indicator"] = json.loads(argv[i + 1])
            except ValueError:
                pass
            i += 1
        elif a == "--main-indicator" and i + 1 < len(argv):
            opts["main_indicator"] = argv[i + 1]
            i += 1
        i += 1
    return opts


def icon_for(desc):
    d = desc.lower()
    for key, glyph in NERD_ICONS:
        if key in d:
            return glyph
    return FALLBACK_ICON


def main():
    opts = parse_args(sys.argv[1:])
    url = "https://wttr.in/" + (opts["location"] or "")
    url += "?format=j1"
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            data = json.load(r)
    except Exception:
        print(json.dumps({"text": "", "alt": "", "tooltip": "weather unavailable"}))
        return

    cur = data.get("current_condition", [{}])[0]
    desc = (cur.get(opts["main-indicator"]) or cur.get("weatherDesc") or [{}])[0].get("value", "")
    temp_key = "temp_F" if opts["fahrenheit"] else "temp_C"
    feels_key = "FeelsLikeF" if opts["fahrenheit"] else "FeelsLikeC"
    unit = "°F" if opts["fahrenheit"] else "°C"
    temp = cur.get(temp_key, "?")

    glyph = icon_for(desc)
    if opts["custom_indicator"]:
        glyph = opts["custom_indicator"].get(desc, glyph)
    if not opts["nerd"]:
        glyph = ""  # non-nerd fonts would show a tofu box for the glyphs

    print(json.dumps({
        "text": "%s %s%s" % (glyph, temp, unit),
        "alt": desc,
        "tooltip": "%s: %s%s (feels %s%s)" % (
            desc, temp, unit, cur.get(feels_key, "?"), unit),
    }))


if __name__ == "__main__":
    main()
HANCORESHIM_EOF
cat > "$BIN/hancore-battery-status" <<'HANCORESHIM_EOF'
#!/usr/bin/env bash
# hancore-battery-status shim: the HANCORE waybar themes' battery modules
# run this for their tooltip text (was: omarchy-battery-status, part of
# Omarchy). Prints a short upower summary of the first battery.
set -u
dev="$(upower -e 2>/dev/null | grep -m1 '_BAT')"
if [ -z "$dev" ]; then
  echo "No battery"
  exit 0
fi
upower -i "$dev" | awk -F: '
  /state|percentage|time to (full|empty)/ {
    gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+/, "", $1);
    printf "%s: %s\n", $1, $2
  }'
HANCORESHIM_EOF
cat > "$BIN/hancore-update-check" <<'HANCORESHIM_EOF'
#!/usr/bin/env bash
# hancore-update-check shim: the HANCORE waybar themes' custom/update
# module execs this (was: omarchy-update-available, which checks for
# Omarchy's own updates). Mirrors the rice's own polybar-updates.sh
# exactly: prints a pending-dnf-update count on every line, including
# "0" when there are none, and loops internally on a 15-minute sleep
# (same tail-script pattern as polybar-updates.sh - waybar just shows the
# most recent line, so the count is visible immediately at bar startup).
#
# The module's on-click opens software-update.sh in a floating kitty
# (UpdatesTask window rule in the sway config).
set -u
while true; do
  count="$(timeout 10 dnf check-update -q 2>/dev/null | grep -cE '^\S+\.(x86_64|noarch|i686|aarch64|s390x|ppc64le)[[:space:]]')"
  printf '󰂪 %s\n' "${count:-0}"
  sleep 900
done
HANCORESHIM_EOF
cat > "$BIN/vscode-theme-sync" <<'HANCORESHIM_EOF'
#!/usr/bin/env bash
# vscode-theme-sync: point VS Code's workbench.colorTheme at this rice's
# generated extension theme for the ACTIVE desktop theme (label = the
# title-cased theme name, exactly how generate-vscode-themes.py
# contributes it) - for VS Code AND any installed forks (Cursor, and
# Antigravity - a Cursor-lineage fork; its data folder is ~/.antigravity,
# verified from its app.asar). Each installed app gets the same
# workbench.colorTheme and a copy of the extension, so their workbench
# chrome - title bar, tab bar, window control buttons - follows the
# desktop theme too instead of the fork's stock default.
# Run by app-theme-sync.sh on every theme switch; the apps watch
# settings.json and apply the new editor theme live.
#
# settings.json is JSONC - comments and trailing commas are legal there
# (jq chokes on both) and the file may have CRLF endings - so the edit is
# a line-level regex swap in python instead of a JSON round-trip.
set -u
name="$(cat "$HOME/.config/waybar/current-theme-name" 2>/dev/null || true)"
[ -n "$name" ] || exit 0
label="$(printf '%s' "$name" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')"

MASTER_EXT="$HOME/.vscode/extensions/linux-postinstall-rice-themes"
MASTER_VER="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$MASTER_EXT/package.json" 2>/dev/null | head -1)"

# config-dir name | extensions dir  (an app counts as installed when
# ~/.config/<name> exists - the forks all create it on first run)
APPS=(
  "Code|$HOME/.vscode/extensions"
  "Cursor|$HOME/.cursor/extensions"
  "Antigravity|$HOME/.antigravity/extensions"
)

ver_of() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1/package.json" 2>/dev/null | head -1; }

for entry in "${APPS[@]}"; do
  conf="${entry%%|*}"
  extdir="${entry#*|}"
  [ -d "$HOME/.config/$conf" ] || continue   # app not installed

  # Keep a copy of the extension in every fork's extensions dir. The
  # master (maintained by generate-vscode-themes.py at section 15) is
  # the VS Code copy itself; forks get refreshed whenever its version
  # moves, so a theme regeneration reaches them on the next switch.
  if [ -n "$MASTER_VER" ] && [ "$extdir" != "$HOME/.vscode/extensions" ]; then
    if [ "$(ver_of "$extdir/linux-postinstall-rice-themes")" != "$MASTER_VER" ]; then
      mkdir -p "$extdir"
      rm -rf "$extdir/linux-postinstall-rice-themes"
      cp -a "$MASTER_EXT" "$extdir/linux-postinstall-rice-themes" 2>/dev/null || true
    fi
  fi

  settings="$HOME/.config/$conf/User/settings.json"
  mkdir -p "$(dirname "$settings")"
  python3 - "$settings" "$label" <<'VSEOF'
import re
import sys

path, label = sys.argv[1], sys.argv[2]
try:
    src = open(path, encoding="utf-8").read()
except OSError:
    src = "{}"

pat = re.compile(r'("workbench[.]colorTheme"\s*:\s*)"[^"]*"')
if pat.search(src):
    out = pat.sub(lambda m: m.group(1) + '"' + label + '"', src, count=1)
else:
    out = '{' + chr(10) + '    "workbench.colorTheme": "%s",' % label + src[1:]
open(path, "w", encoding="utf-8").write(out)
VSEOF
done
HANCORESHIM_EOF
chmod +x "$BIN/wttrbar" "$BIN/hancore-battery-status" "$BIN/hancore-update-check" "$BIN/vscode-theme-sync"

# Nerd Font widget glyphs for the helper scripts the sections below sed
# into $BIN (polybar-bluetooth/caffeine/dnd/layout). These were defined
# by the old theme-collection section that's gone now; carried over
# verbatim so the literal Private-Use-Area glyphs stay byte-exact.
ICO_BT=$''
ICO_COFFEE=$''      # nf-fa-coffee
ICO_BELL=$''      # nf-fa-bell
ICO_BELL_OFF=$''  # nf-fa-bell-slash
ICO_SPLIT_H=$'󰯌'   # nf-md-view_split_vertical (vertical divider -> side-by-side panes = sway splith)
ICO_SPLIT_V=$'󰯋'   # nf-md-view_split_horizontal (horizontal divider -> stacked panes = sway splitv)
ICO_STACKING=$'󰕪'  # nf-md-view_agenda (sway "stacked" layout)
ICO_TABBED=$'󰓩'    # nf-md-tab (sway "tabbed" layout)

# ----------------------------------------------------------------------------
# 6b. Multi-monitor helper script (polybar per output) + autorandr hotplug hook
# ----------------------------------------------------------------------------
log "Writing multi-monitor helper scripts..."
cat > "$BIN/waybar-launch.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Kill any running waybar and relaunch it against the current theme
# (~/.config/waybar/config.jsonc + style.css). Unlike polybar on X11, waybar
# draws on every connected output from one process and each instance gets its
# own working SNI tray, so there's no primary/secondary split or single-tray-
# owner dance to manage here - one relaunch covers all monitors.
set -u
# waybar links against the system libstdc++; a stale LD_LIBRARY_PATH (e.g.
# a tool session exporting an editor's bundled libraries) makes it die
# with GLIBCXX errors the moment it starts. Strip it before launching.
unset LD_LIBRARY_PATH
# The adapted HANCORE themes exec helper scripts by bare name (wttrbar,
# hancore-update-check, ...) - make sure ~/.local/bin is on the bar's PATH.
export PATH="$HOME/.local/bin:$PATH"
# Waybar is a GTK app: unstyled text falls back to the GTK theme's
# foreground. The session env can carry a STALE GTK_THEME (e.g. a theme
# name from a previous rice that no longer exists), which makes GTK fall
# back to its light default and render module values near-black. Point
# the bar at the current theme's generated Rice-* GTK theme instead.
CURRENT_THEME="$(cat "$HOME/.config/waybar/current-theme-name" 2>/dev/null || true)"
if [ -n "$CURRENT_THEME" ] && [ -d "$HOME/.themes/Rice-$CURRENT_THEME/gtk-3.0" ]; then
  export GTK_THEME="Rice-$CURRENT_THEME"
fi
pkill -x waybar 2>/dev/null
# give it a moment to release its layer-shell surfaces before relaunching
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x waybar >/dev/null 2>&1 || break
  sleep 0.1
done
pkill -9 -x waybar 2>/dev/null || true
waybar >/dev/null 2>&1 &
disown || true
RICE_EOF
chmod +x "$BIN/waybar-launch.sh"

# fresh-env: exec wrapper for the sway binds above - re-reads the CURRENT
# GTK_THEME from environment.d (waybar-theme.sh keeps it in step with the
# active desktop theme). Sway's own environment is a login-time snapshot,
# so apps launched from its binds would otherwise carry a stale theme
# name - and a GTK app whose inherited GTK_THEME no longer exists falls
# all the way back to stock Adwaita, ignoring the correct gsettings value.
cat > "$BIN/fresh-env" <<'EOF'
#!/usr/bin/env bash
set -u
gt="$(sed -n 's/^GTK_THEME=//p' "$HOME/.config/environment.d/gtk-theme.conf" 2>/dev/null || true)"
[ -n "$gt" ] && export GTK_THEME="$gt"
# Same for the cursor theme, so apps launched from sway's binds pick
# up a cursor-theme.sh switch without a re-login.
ct="$(sed -n 's/^XCURSOR_THEME=//p' "$HOME/.config/environment.d/cursor-theme.conf" 2>/dev/null || true)"
[ -n "$ct" ] && export XCURSOR_THEME="$ct"
exec "$@"
EOF
chmod +x "$BIN/fresh-env"

cat > "$BIN/swaybg-restore.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Restore the saved wallpaper with swaybg (replaces nitrogen --restore).
# Sources, in order (between the first two, whichever pick is newer wins):
#   1. ~/.config/sway/wallpaper-saved     - written by the rofi picker
#   2. ~/.local/share/azote/swaybg.json   - written by azote, one entry per
#      output (azote is the preferred picker when installed)
#   3. ~/.config/sway/wallpaper.png       - seeded by the installer
# exec_always re-runs this on reload, so kill any previous swaybg first to
# avoid stacking.
set -u
CFG="$HOME/.config/sway"
SAVED="$CFG/wallpaper-saved"
AZOTE_JSON="$HOME/.local/share/azote/swaybg.json"

IMG=""
[ -f "$SAVED" ] && IMG="$(cat "$SAVED")"
if [ -n "$IMG" ] && [ -f "$IMG" ]; then
  # A newer azote pick overrides an older rofi pick (and vice versa).
  [ -f "$AZOTE_JSON" ] && [ "$AZOTE_JSON" -nt "$SAVED" ] && IMG=""
else
  IMG=""
fi

ARGS=()
if [ -n "$IMG" ]; then
  ARGS=(-i "$IMG" -m fill)
elif [ -f "$AZOTE_JSON" ] && command -v jq >/dev/null 2>&1; then
  # Drop entries whose file has vanished since the pick (e.g. the wallpapers
  # directory was renamed) so the restore falls through to the next source.
  while IFS=$'\t' read -r out path; do
    [ -n "$out" ] && [ -n "$path" ] && [ -f "$path" ] \
      && ARGS+=(-o "$out" -i "$path" -m fill)
  done < <(jq -r '.[] | select(.name and .path) | [.name, .path] | @tsv' \
             "$AZOTE_JSON" 2>/dev/null)
fi
# Fall back to the sway wallpaper seeded by the installer.
[ "${#ARGS[@]}" -eq 0 ] && [ -f "$CFG/wallpaper.png" ] \
  && ARGS=(-i "$CFG/wallpaper.png" -m fill)
[ "${#ARGS[@]}" -eq 0 ] && exit 0

pkill -x swaybg 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swaybg >/dev/null 2>&1 || break; sleep 0.1; done
swaybg "${ARGS[@]}" >/dev/null 2>&1 &
disown || true
RICE_EOF
chmod +x "$BIN/swaybg-restore.sh"
cat > "$BIN/swayidle-launch.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Idle management for the Sway rice via swayidle. Timings:
#   - 20min (1200s): show the screensaver and lock (lock.sh --with-screensaver,
#     which blanks immediately on lock via its own logic)
#   - 50min (3000s): power the displays off; power back on when activity resumes
#   - before sleep: lock first so resume lands on the lock screen
# Kept later than the screensaver mark on purpose (DPMS/display-power is a
# separate subsystem from the idle screensaver).
# exec_always re-runs this on reload, so single-instance it first.
# The idle context inherits sway's login-time PATH, which does NOT include
# ~/.local/bin - the pipx tools the lock/screensaver chain needs (tte) live
# there, so re-add it before exec.
export PATH="$HOME/.local/bin:$PATH"
set -u
pkill -x swayidle 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swayidle >/dev/null 2>&1 || break; sleep 0.1; done

exec swayidle -w \
  timeout 1200 "$HOME/.local/bin/lock.sh --with-screensaver" \
  timeout 3000 'swaymsg "output * power off"' \
    resume     'swaymsg "output * power on"' \
  before-sleep "$HOME/.local/bin/lock.sh"
RICE_EOF
chmod +x "$BIN/swayidle-launch.sh"
cat > "$BIN/weather-float.sh" <<'EOF'
#!/usr/bin/env bash
# Toggle a floating weather window from the waybar weather widget. First click
# opens the full wttr.in report (current conditions + 3-day forecast) in a
# floating, OPAQUE, theme-colored kitty; clicking the widget again closes it
# (q inside the window closes it too). The same wttr.in source the wttrbar
# widget uses, just the whole report instead of today's temperature.
#
# Opaque (background_opacity=1.0) because the rice's kitty is translucent and
# the wallpaper/other windows bleeding through made the report unreadable; a
# smaller font_size so the 4-column forecast table fits the window width.
#
# Location is wttr.in's own IP geolocation (no config). To pin a city, export
# WEATHER_LOCATION (e.g. "Stockholm" or "Gothenburg").
set -u

# --show is the renderer, run inside the kitty window.
if [ "${1:-}" = "--show" ]; then
  loc="${WEATHER_LOCATION:-}"
  url="https://wttr.in/${loc}?FmM"       # F = no footer, m = metric, M = wind in m/s
  if out="$(curl -fsS --max-time 12 "$url" 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s\n' "$out" | less -R       # -R keeps colors; scroll if it overflows
  else
    printf '\n  Weather unavailable - offline, or wttr.in is unreachable.\n'
    printf '  (Set WEATHER_LOCATION to a city name if geo-IP guessed wrong.)\n\n'
    printf '  Press any key to close.\n'
    read -rn1 _
  fi
  exit 0
fi

# Toggle: if a WeatherFloat window is open, close it; otherwise open one.
if swaymsg -t get_tree 2>/dev/null | grep -q '"WeatherFloat"'; then
  swaymsg '[app_id="WeatherFloat"] kill' >/dev/null 2>&1
else
  kitty --class WeatherFloat \
        -o background_opacity=1.0 \
        -o window_padding_width=0 \
        -o font_size=8 \
        -e "$0" --show >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
EOF
chmod +x "$BIN/weather-float.sh"

cat > "$BIN/screenshot.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Region screenshot for the Sway rice. flameshot is X11-oriented and does NOT
# capture on sway/wlroots (its portal path hangs), so this uses the Wayland
# tools: slurp selects a region, grim captures it. If swappy (a flameshot-style
# annotation editor) is installed, the shot is piped to it for arrows/text/blur
# + save/copy; otherwise it's saved to ~/Pictures/Screenshots and copied to the
# clipboard directly. Pass `full` to capture the whole output instead of a region.
set -u
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
OUT="$DIR/shot-$(date +%Y%m%d-%H%M%S).png"

if [ "${1:-region}" = "full" ]; then
  GEO=""
else
  GEO="$(slurp 2>/dev/null)" || exit 0   # Escape/cancel -> exit quietly
  [ -n "$GEO" ] || exit 0
fi

if command -v swappy >/dev/null 2>&1; then
  # flameshot-style editor (save/copy from inside swappy's UI). Swappy's
  # Save button (or Ctrl+S) writes silently to its save_path - NO dialog
  # - which defaults to ~/Pictures/Screenshots. Detect the new file and
  # announce where it went, so the silent save is not a mystery.
  __before="$(ls -1 "$DIR" 2>/dev/null | sort)"
  if [ -n "$GEO" ]; then grim -g "$GEO" - | swappy -f -; else grim - | swappy -f -; fi
  __new="$(comm -13 <(printf '%s\n' "$__before") <(ls -1 "$DIR" 2>/dev/null | sort) | head -1)"
  [ -n "$__new" ] && notify-send "Screenshot" "Saved to $DIR/$__new"
else
  if [ -n "$GEO" ]; then grim -g "$GEO" "$OUT" || exit 1; else grim "$OUT" || exit 1; fi
  wl-copy --type image/png < "$OUT" 2>/dev/null || true
  command -v notify-send >/dev/null && notify-send "Screenshot" "Saved to $OUT and copied to clipboard"
fi
RICE_EOF
chmod +x "$BIN/screenshot.sh"
cat > "$BIN/wallpaper-picker.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Rofi-based wallpaper picker. Lists images from
# the usual wallpaper dirs, sets the pick with swaybg, and saves the path so
# swaybg-restore.sh brings it back on the next login/reload. If azote (the
# Wayland-native nitrogen equivalent) is installed, prefer its GUI instead.
set -uo pipefail

if command -v azote >/dev/null 2>&1; then
  exec azote
fi

DIRS=(
  "$HOME/Pictures/wallpapers"
  "$HOME/Pictures/gh0stzk-wallpapers"
  "$HOME/.config/sway"
  "$HOME/Pictures"
)
SAVED="$HOME/.config/sway/wallpaper-saved"
ROFI_CURRENT="$HOME/.config/rofi/current.rasi"

mapfile -t FILES < <(
  for d in "${DIRS[@]}"; do
    [ -d "$d" ] && find "$d" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' \) 2>/dev/null
  done | sort -u
)
if [ "${#FILES[@]}" -eq 0 ]; then
  notify-send "Wallpaper" "No images found in: ${DIRS[*]}"
  exit 1
fi

# Show "basename  (dir)" but map back to the full path on selection.
declare -A MAP
LINES=()
for f in "${FILES[@]}"; do
  label="$(basename "$f")  ($(dirname "$f" | sed "s#$HOME#~#"))"
  MAP["$label"]="$f"
  LINES+=("$label")
done

PICK="$(printf '%s\n' "${LINES[@]}" | rofi -dmenu -i -p "Wallpaper" ${ROFI_CURRENT:+-theme "$ROFI_CURRENT"})"
[ -n "$PICK" ] || exit 0
IMG="${MAP[$PICK]:-}"
[ -n "$IMG" ] && [ -f "$IMG" ] || exit 0

printf '%s' "$IMG" > "$SAVED"
~/.local/bin/swaybg-restore.sh
notify-send "Wallpaper" "Set to $(basename "$IMG")"
RICE_EOF
chmod +x "$BIN/wallpaper-picker.sh"

# swaybg handles the wallpaper: swaybg-restore.sh fills every connected
# output with the saved pick, so there's no per-monitor tiling logic to
# write here. See section 12 for the initial wallpaper seed.

# autorandr's postswitch hook fires on every profile change (monitor plugged/
# unplugged/reconfigured) - re-run polybar and re-restore the wallpaper so
# both follow the new output layout instead of staying stuck on the old one.
mkdir -p "$CONF/autorandr"

# ----------------------------------------------------------------------------
# 6c. polybar bluetooth widget + blueman-applet guard
# ----------------------------------------------------------------------------
log "Writing polybar bluetooth helper script..."
cat > "$BIN/polybar-bluetooth.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: prints bluetooth adapter power state.
# Reads the adapter's "Powered" D-Bus property directly via busctl instead
# of shelling out to bluetoothctl's interactive client. busctl resolves in
# single-digit-to-low-double-digit milliseconds whether bluez is registered
# yet or not (confirmed live: ~10-35ms either way, success or clean
# failure) - bluetoothctl's own startup is comparatively slow, and right
# after boot/login, while bluetoothd's D-Bus service is still registering,
# it was occasionally slow enough to wedge polybar's custom/script
# executor: the widget then stayed permanently blank until a manual
# polybar reload kicked its refresh timer back into life, since nothing
# else re-triggers a wedged executor. Wrapping the old bluetoothctl call in
# a `timeout` only bounded the hang, it didn't stop the executor from
# getting stuck on a slow tick - going straight to a fast, fail-clean
# D-Bus read avoids that class of bug instead of papering over it.
STATE="off"
adapter=$(busctl tree org.bluez --list 2>/dev/null | grep -m1 '^/org/bluez/hci[0-9]*$')
if [ -n "$adapter" ] && busctl get-property org.bluez "$adapter" org.bluez.Adapter1 Powered 2>/dev/null | grep -q "true"; then
  STATE="on"
fi
printf '  @@ICO_BT@@ %s ' "$STATE"
EOF
chmod +x "$BIN/polybar-bluetooth.sh"
sed -i "s/@@ICO_BT@@/$ICO_BT/" "$BIN/polybar-bluetooth.sh"

log "Writing blueman-applet guard script..."
cat > "$BIN/blueman-applet-guard.sh" <<'EOF'
#!/usr/bin/env bash
# blueman-manager (opened via the polybar bluetooth widget's click action)
# unconditionally auto-spawns blueman-applet as its own backend on open -
# there's no flag to stop this, and it's what puts the redundant bluetooth
# tray icon right back after we deliberately disabled its autostart entry.
# Reap it if it ever reappears instead of fighting blueman's own code.
while true; do
  pkill -x blueman-applet 2>/dev/null
  sleep 3
done
EOF
chmod +x "$BIN/blueman-applet-guard.sh"

log "Writing caffeine (idle/sleep inhibitor) toggle + polybar widget scripts..."
cat > "$BIN/caffeine-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# "Caffeine" toggle - no packaged equivalent exists for Fedora (neither dnf
# nor Flathub carry one), so this is a small hand-rolled stand-in for the
# classic GNOME Caffeine extension: click to inhibit screen-blank/lock/sleep,
# click again to release. Nothing changes system-wide while it's off.
#
# Two things happen while active:
#   1. swayidle is stopped entirely, so no idle timeout can blank/lock the
#      display while caffeinated.
#   2. A backgrounded `systemd-inhibit` holds idle/sleep/lid-switch locks so
#      systemd-logind won't suspend even on lid close, matching what the
#      screensaver-based inhibition alone wouldn't cover.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
# Toggling OFF must restore the real idle lock/DPMS timing, not a stale
# default: swayidle-launch.sh re-arms exactly what a fresh login gets.

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")" 2>/dev/null
  rm -f "$PIDFILE"
  # restart swayidle to restore idle lock/DPMS timers
  "$HOME/.local/bin/swayidle-launch.sh" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  notify-send -h string:x-dunst-stack-tag:caffeine "Caffeine: off" "Screen lock/sleep restored"
else
  # stop swayidle entirely so nothing blanks/locks while caffeinated
  pkill -x swayidle 2>/dev/null || true
  systemd-inhibit --what=idle:sleep:handle-lid-switch --who="sway-caffeine" \
      --why="User requested via caffeine-toggle.sh" --mode=block \
      sleep infinity &
  disown
  echo "$!" > "$PIDFILE"
  notify-send -h string:x-dunst-stack-tag:caffeine "Caffeine: on" "Screen lock/sleep inhibited until toggled off"
fi
EOF
chmod +x "$BIN/caffeine-toggle.sh"
cat > "$BIN/caffeine-state.sh" <<'EOF'
#!/usr/bin/env bash
# Waybar custom/caffeine widget backend: reports the rice's caffeine state
# (Mod+C / ~/.local/bin/caffeine-toggle.sh) as waybar JSON, so the bar icon
# reflects the toggle however it was triggered - by the keybind, by clicking
# the widget (which runs the same toggle script), or by anything else. This
# replaces the native idle_inhibitor module, which was an independent
# Wayland inhibitor that never showed caffeine's actual state.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  printf '{"text":"󰛨","class":"activated","tooltip":"Caffeine: ON - screen lock/sleep inhibited (click or Mod+C to release)"}\n'
else
  printf '{"text":"󰛩","class":"deactivated","tooltip":"Caffeine: OFF (click or Mod+C to stay awake)"}\n'
fi
EOF
chmod +x "$BIN/caffeine-state.sh"

cat > "$BIN/polybar-caffeine.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: prints caffeine (idle/sleep inhibit) state.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  STATE="on"
else
  STATE="off"
fi
printf '  @@ICO_COFFEE@@ %s ' "$STATE"
EOF
chmod +x "$BIN/polybar-caffeine.sh"
sed -i "s/@@ICO_COFFEE@@/$ICO_COFFEE/" "$BIN/polybar-caffeine.sh"

log "Writing polybar media-control widget script..."
cat > "$BIN/polybar-media.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: playerctl-based media control (prev/play-pause/next).
# Empty output entirely when no MPRIS player is active/found - the module then
# takes no bar space at all, matching the wired/wireless network widgets' own
# hide-when-idle behavior (format-disconnected left blank) rather than showing
# dead controls with nothing to control. Three separately-clickable icons in
# one label via inline %{A...} action tags, the same technique already used
# for the wifi widget's click-to-open/toggle actions (module-level
# click-left/right only gives two click zones total, not three independently
# positioned ones). Every literal % below is doubled (%%) because this is a
# printf format string - printf treats a bare % as its own format specifier,
# which collides with polybar's own %{...} action-tag syntax otherwise.
status=$(playerctl status 2>/dev/null)
[ -z "$status" ] && exit 0

if [ "$status" = "Playing" ]; then
  icon=""
else
  icon=""
fi

printf ' %s ' "$icon"
EOF
chmod +x "$BIN/polybar-media.sh"

log "Writing polybar boxed-media-control widget script..."
cat > "$BIN/polybar-media-boxed.sh" <<'EOF'
#!/usr/bin/env bash
# Same icon logic as polybar-media.sh, but WITHOUT inline per-icon %{A...}
# action tags. Needed by themes (Brenda) that put a shared format-background
# behind this module: polybar renders a fragmented, broken-looking
# background behind a label containing multiple action-tag regions instead
# of one continuous chip (confirmed live - a real polybar quirk, not a
# config mistake). The 3 actions move to the module's own click-left/
# click-middle/click-right instead of 3 separately-clickable icon
# positions - same 3 actions, triggered by mouse button instead of X
# position within the label.
status=$(playerctl status 2>/dev/null)
[ -z "$status" ] && exit 0

if [ "$status" = "Playing" ]; then
  icon=""
else
  icon=""
fi

printf '   %s   ' "$icon"
EOF
chmod +x "$BIN/polybar-media-boxed.sh"

log "Writing polybar cliamp-running-state widget script..."
cat > "$BIN/polybar-cliamp.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: prints a note icon whose state text changes
# with whether cliamp (this rice's music player) is currently running -
# same on/off-text convention as polybar-caffeine.sh/polybar-bluetooth.sh.
# Unlike polybar-media.sh (empty whenever no MPRIS player is registered,
# i.e. also empty while cliamp is scratchpad-hidden with nothing loaded),
# this stays visible any time the cliamp process exists at all - a
# constant glance/launch point back to it regardless of playback state or
# whether its window is currently shown or hidden (see cliamp-toggle.sh).
# No leading/trailing padding beyond one space around the icon - the
# "dots" separator module already carries its own space on each side,
# so extra padding here just doubled up the gap around this widget
# specifically (confirmed live, then tightened).
if pgrep -x cliamp >/dev/null; then
  STATE="on"
else
  STATE="off"
fi
printf ' %s' "$STATE"
EOF
chmod +x "$BIN/polybar-cliamp.sh"

log "Writing polybar software-updates widget script..."
cat > "$BIN/polybar-updates.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module (tail=true): shows a count of pending dnf
# package updates, including "0" when there are none - always visible
# rather than hiding when idle, unlike the media/network widgets elsewhere
# in this rice. Loops and sleeps internally instead of relying on polybar's
# own `interval` scheduling for a script this infrequent - confirmed
# empirically (clean restart, no stale process) that polybar does NOT
# execute an interval-based custom/script's first run immediately at bar
# startup the way it does for short-interval widgets elsewhere in this
# rice; with a large interval (900s) nothing appeared for the full 15
# minutes. tail=true hands timing control to the script itself instead:
# check immediately on startup, print, sleep, repeat - polybar just
# displays whatever line the script most recently printed.
#
# Counts only real "name.arch  version  repo" lines - dnf's own "Upgrades"
# section header would otherwise be miscounted as one extra package by a
# naive line count. Relies on Fedora's own dnf-makecache.timer (enabled by
# default) to keep repo metadata fresh in the background, so this just
# reads whatever that cache last had rather than forcing a slow network
# refresh itself.
while true; do
  count=$(timeout 10 dnf check-update -q 2>/dev/null | grep -cE '^\S+\.(x86_64|noarch|i686|aarch64|s390x|ppc64le)[[:space:]]')
  printf ' %s\n' "${count:-0}"
  sleep 900
done
EOF
chmod +x "$BIN/polybar-updates.sh"


log "Writing software-update.sh (dnf upgrade + reboot-required check)..."
cat > "$BIN/software-update.sh" <<'EOF'
#!/usr/bin/env bash
# Runs the actual dnf upgrade (same fully-interactive flow as before -
# dnf's own "Is this ok [y/N]:" prompt is untouched), then checks whether
# it left the system needing a reboot (kernel/glibc/systemd/etc. update)
# via dnf-utils' `needs-restarting -r` and offers to reboot right away.
# Exit code semantics are the inverse of a typical command: 1 means a
# reboot IS required, 0 means it's not (confirmed against the real tool,
# not assumed from the name) - this rice's polybar update-count widget
# only reports pending package counts, not reboot-required state, so
# without this the only other way to notice is by chance days later.
set -uo pipefail
sudo dnf upgrade

echo
if needs-restarting -r >/dev/null 2>&1; then
  echo "No reboot required."
else
  echo "A reboot is required to finish applying these updates."
  read -r -p "Reboot now? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS])
      systemctl reboot
      ;;
    *)
      echo "Not rebooting - remember to reboot later to finish applying updates."
      ;;
  esac
fi
read -r -p "Press Enter to close..." _
EOF
chmod +x "$BIN/software-update.sh"

log "Writing Do Not Disturb toggle + polybar widget scripts..."
cat > "$BIN/dnd-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Do Not Disturb toggle for dunst. Notify BEFORE pausing (a notification
# sent after wouldn't show - that's the whole point of pausing) rather than
# after, so the confirmation is actually visible either way.
#
# Calendar/task reminders go through dunst too (~/.local/bin/calendar-
# reminder-daemon.py fires them as regular notify-send notifications,
# replacing evolution-alarm-notify's own separate GTK popup window, which
# is disabled entirely) so dunst's own pause state is already the single
# thing that needs toggling - no separate gsettings flip needed anymore.
if [ "$(dunstctl is-paused)" = "true" ]; then
  dunstctl set-paused false
  notify-send -h string:x-dunst-stack-tag:dnd "Do Not Disturb: off" "Notifications resumed"
else
  notify-send -h string:x-dunst-stack-tag:dnd "Do Not Disturb: on" "Notifications silenced until toggled off"
  dunstctl set-paused true
fi
# Flip the waybar DND indicator (custom/notification-silencing-indicator
# listens on signal 10) the moment the state changes.
pkill -SIGRTMIN+10 waybar 2>/dev/null || true
EOF
chmod +x "$BIN/dnd-toggle.sh"

log "Writing waybar DND indicator widget script..."
cat > "$BIN/dnd-indicator.sh" <<'EOF'
#!/usr/bin/env bash
# Waybar custom/notification-silencing-indicator backend: reports dunst's
# pause state as waybar JSON so the bar always shows a small bell -
# normal text color while notifications flow, the theme accent while
# muted (Mod+N / dnd-toggle.sh), however the toggle was triggered -
# keybind, widget click, or a bare dunstctl. The themes' CSS (plus the
# installer-appended accent rule) paints .active.
if [ "$(dunstctl is-paused)" = "true" ]; then
  printf '{"text":"@@ICO_BELL@@","class":"active","tooltip":"Do Not Disturb: notifications muted (Mod+N or click to unmute)"}\n'
else
  printf '{"text":"@@ICO_BELL@@","class":"","tooltip":"Notifications: on (Mod+N or click to mute)"}\n'
fi
EOF
chmod +x "$BIN/dnd-indicator.sh"
sed -i "s/@@ICO_BELL@@/$ICO_BELL/" "$BIN/dnd-indicator.sh"

cat > "$BIN/wifi-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Wifi radio on/off toggle for the network-wireless widget's right-click
# action. `nmcli radio wifi` only accepts on/off, not "toggle" - confirmed
# live: `nmcli radio wifi toggle` errors with "invalid 'wifi' argument:
# 'toggle' (use on/off)", and since the click action backgrounds it with
# `&`, that error went nowhere visible - right-click silently never
# toggled anything. Checking the current state first instead.
if [ "$(nmcli radio wifi)" = "enabled" ]; then
  nmcli radio wifi off
  notify-send -h string:x-dunst-stack-tag:wifi "Wi-Fi" "Disabled"
else
  nmcli radio wifi on
  notify-send -h string:x-dunst-stack-tag:wifi "Wi-Fi" "Enabled"
fi
EOF
chmod +x "$BIN/wifi-toggle.sh"

cat > "$BIN/polybar-wifi.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module replacing internal/network for the wireless
# widget - needed to show a distinct "off" state when the radio is
# explicitly disabled (~/.local/bin/wifi-toggle.sh, right-click) WITHOUT
# also showing it any time wireless simply isn't connected (e.g. only
# using the wired connection right now) - internal/network's own
# format-disconnected can't tell those two states apart, and reusing it
# for this would make the indicator appear any time wireless just isn't in
# use, undoing the reason it was left blank in the first place (so only
# the active interface's widget shows - see network-wired/-wireless
# above). Per-theme prefix/suffix spacing and colors come in via
# WIFI_PREFIX/WIFI_SUFFIX/WIFI_CONNECTED_FG/WIFI_OFF_FG env vars set in
# each theme's own exec= line (literal hex, not ${colors.x} - baked in at
# generation time), using polybar's inline %{F#hex}...</span> tag so one
# shared script still renders every theme's own colors without a separate
# copy per theme.
if [ "$(nmcli radio wifi 2>/dev/null)" != "enabled" ]; then
  printf '%s%%{F%s}wifi off%</span>%s' "$WIFI_PREFIX" "$WIFI_OFF_FG" "$WIFI_SUFFIX"
  exit 0
fi
essid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2}' | head -1)
[ -n "$essid" ] && printf '%s%%{F%s}%s%</span>%s' "$WIFI_PREFIX" "$WIFI_CONNECTED_FG" "$essid" "$WIFI_SUFFIX"
EOF
chmod +x "$BIN/polybar-wifi.sh"

cat > "$BIN/polybar-dnd.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: prints notification state (on/off), not
# dunst pause-mode state - "off" / bell-slash means silenced (dunst paused).
# Also prefixes the dunst notification-history count to the left of the
# bell when non-zero, rather than a second separate bell/module for it -
# one shared bell reads cleaner and sidesteps a real polybar layout bug
# (confirmed live) where two custom/script modules placed directly
# adjacent with no separator between them can leave the first one's
# content stuck invisible even though it keeps polling correctly.
# click-left (bound in each theme's .ini) toggles dnd; click-middle opens
# notification-center.sh's rofi browser to see/clear individually;
# click-right clears everything at once via dunstctl history-clear.
n=$(dunstctl count history 2>/dev/null)
[ -z "$n" ] && n=0
count=""
[ "$n" -gt 0 ] && count="$n "
if [ "$(dunstctl is-paused)" = "true" ]; then
  printf '  %s@@ICO_BELL_OFF@@ off ' "$count"
else
  printf '  %s@@ICO_BELL@@ on ' "$count"
fi
EOF
chmod +x "$BIN/polybar-dnd.sh"
sed -i "s/@@ICO_BELL_OFF@@/$ICO_BELL_OFF/; s/@@ICO_BELL@@/$ICO_BELL/" "$BIN/polybar-dnd.sh"

cat > "$BIN/polybar-notifications.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: shows dunst's notification-history count
# with its own bell icon - used only by themes with no dnd module to sit
# next to (float), where there's no existing bell for the count to attach
# to (everywhere else, the count is prefixed onto polybar-dnd.sh's own
# bell instead, see polybar-dnd.sh). Click-left opens
# notification-center.sh's rofi browser to see/clear individually;
# click-right clears everything at once via `dunstctl history-clear`.
n=$(dunstctl count history 2>/dev/null)
[ -z "$n" ] && n=0
if [ "$n" -gt 0 ]; then
  printf "\uf0f3 %s" "$n"
else
  printf "\uf0f3"
fi
EOF
chmod +x "$BIN/polybar-notifications.sh"

cat > "$BIN/notification-center.sh" <<'EOF'
#!/usr/bin/env bash
# Rofi-based browser for dunst's notification history. dunst itself has no
# "list view" of its own - dunstctl history-pop only recalls the single
# latest notification at a time, re-displayed as a live popup - so this
# parses `dunstctl history`'s real JSON (confirmed structure: .data[0] is
# an array of notification objects, already newest-first) into a rofi
# list. Selecting an entry removes just that one from history
# (dunstctl history-rm); a "Clear all" entry at the top wipes everything.
set -euo pipefail

HIST_JSON="$(dunstctl history)"
mapfile -t IDS < <(jq -r '.data[0][].id.data' <<<"$HIST_JSON")

if [ "${#IDS[@]}" -eq 0 ]; then
  notify-send "Notification Center" "No notification history"
  exit 0
fi

mapfile -t LABELS < <(jq -r '.data[0][] | "\(.appname.data): \(.summary.data)"' <<<"$HIST_JSON")

MENU="Clear all (${#IDS[@]})"
for l in "${LABELS[@]}"; do
  MENU+=$'\n'"$l"
done

CHOSEN_IDX="$(printf '%s\n' "$MENU" | rofi -dmenu -i -p "Notifications" -format i -theme ~/.config/rofi/current.rasi)"
[ -z "$CHOSEN_IDX" ] && exit 0

if [ "$CHOSEN_IDX" -eq 0 ]; then
  dunstctl history-clear
else
  dunstctl history-rm "${IDS[$((CHOSEN_IDX - 1))]}"
fi
EOF
chmod +x "$BIN/notification-center.sh"

log "Writing polybar brightness widget script..."
cat > "$BIN/polybar-backlight.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: shows current screen brightness and, via
# scroll-up/scroll-down actions below, changes it - through brightnessctl,
# not polybar's own internal/backlight module (which this replaced).
# internal/backlight writes /sys/class/backlight/*/brightness directly,
# which is root:root 644 on this machine even for a user in the "video"
# group (confirmed via getfacl) - its own enable-scroll silently did
# nothing when scrolled, unlike internal/pulseaudio's scroll (no such
# permission issue, since PulseAudio is a user-session server, not a
# root-owned sysfs file). brightnessctl already works around this
# (probably via logind's D-Bus SetBrightness rather than a raw sysfs
# write - confirmed empirically that it changes brightness successfully
# as this user with no sudo) and is already this rice's own mechanism for
# the XF86MonBrightness keys (osd-brightness.sh), so reusing it here
# instead of polybar's own backlight backend actually works.
pct=$(brightnessctl -m info 2>/dev/null | cut -d, -f4 | tr -d '%')

# Opt-in bar-meter rendering, off by default (every existing theme keeps
# the plain percentage above with no changes needed) - set via env vars
# in a theme's own exec= line, the same "one shared script, per-theme
# look via env vars" convention already used by polybar-wifi.sh's
# WIFI_PREFIX/SUFFIX/FG vars. Uses polybar's inline %{F#hex}...</span> tag
# so one script still renders every theme's own bar colors.
if [ -n "$BACKLIGHT_BAR" ]; then
  width="${BACKLIGHT_BAR_WIDTH:-10}"
  filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled="$width"
  bar=""
  for ((i = 0; i < filled; i++)); do bar+="|"; done
  bar="<span color="${BACKLIGHT_BAR_FILL_FG:-#61C766}">${bar}</span>"
  for ((i = filled; i < width; i++)); do bar+="<span color="${BACKLIGHT_BAR_EMPTY_FG:-#6D8895}">|</span>"; done
  printf '%s\n' "$bar"
  exit 0
fi

printf '%s\n' "$pct"
EOF
chmod +x "$BIN/polybar-backlight.sh"

log "Writing polybar split-layout indicator script..."
cat > "$BIN/polybar-layout.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: shows the focused container's current split
# direction - i.e. what direction the NEXT window opened there will go,
# set via Mod+v/Mod+b (see the sway config) - not visible anywhere else in sway
# itself, since split direction has no on-screen effect until a new window
# is actually opened (unlike fullscreen/floating, which are immediately
# visible on their own). Also shows stacked/tabbed if the container is in
# one of those layouts (Mod+t cycles split h/v; stacked/tabbed reachable via
# swaymsg directly, no dedicated keybinding in this rice).
#
# Polled on a short interval (like caffeine/dnd above) rather than an
# `swaymsg -t subscribe` event loop - simpler, no long-running subprocess to
# manage, and split-direction changes don't need sub-second responsiveness.
layout=$(swaymsg -t get_tree 2>/dev/null | jq -r '
  def emit(pl):
    ( {f: .focused, l: pl} ),
    ( .layout as $mylayout | ((.nodes // []) + (.floating_nodes // []))[]? | emit($mylayout) );
  [emit(null)] | map(select(.f == true)) | .[0].l // "splith"
')

case "$layout" in
  splitv)  printf '@@ICO_SPLIT_V@@\n' ;;
  stacked) printf '@@ICO_STACKING@@\n' ;;
  tabbed)  printf '@@ICO_TABBED@@\n' ;;
  *)       printf '@@ICO_SPLIT_H@@\n' ;;
esac
EOF
chmod +x "$BIN/polybar-layout.sh"
sed -i "s/@@ICO_SPLIT_H@@/$ICO_SPLIT_H/; s/@@ICO_SPLIT_V@@/$ICO_SPLIT_V/; s/@@ICO_STACKING@@/$ICO_STACKING/; s/@@ICO_TABBED@@/$ICO_TABBED/" "$BIN/polybar-layout.sh"

log "Writing MX Anywhere 3S scroll-fix script..."
cat > "$BIN/fix-mx-scroll.sh" <<'EOF'
#!/usr/bin/env bash
# MX Anywhere 3S's "Scroll Wheel Resolution" HID++ feature doesn't reliably
# take effect on a fresh connection - manually toggling it off then on again
# in Solaar is what actually fixes it after every reboot, so this replicates
# that exact off-then-on sequence automatically at login instead of just
# setting it to 1 (which can be a no-op if Solaar's cached state already
# reads true even though the mouse itself isn't honoring it). Retries for up
# to 20s since the mouse may not have finished reconnecting over Bluetooth
# yet by the time sway starts.
DEVICE="MX Anywhere 3S"
for _ in $(seq 1 10); do
  if solaar show 2>/dev/null | grep -q "$DEVICE"; then
    solaar config "$DEVICE" hires-smooth-resolution 0 2>/dev/null
    sleep 1
    solaar config "$DEVICE" hires-smooth-resolution 1 2>/dev/null
    exit 0
  fi
  sleep 2
done
EOF
chmod +x "$BIN/fix-mx-scroll.sh"
log "Writing calendar reminder daemon (replaces evolution-alarm-notify's own popup)..."
cat > "$BIN/calendar-reminder-daemon.py" <<'EOF'
#!/usr/bin/env python3
"""Calendar reminder daemon.

Polls every enabled evolution-data-server calendar for VALARM reminders
that just became due and fires a themed dunst notification for each,
instead of evolution-alarm-notify's own GTK popup window - which is fixed
to Catppuccin Mocha regardless of the active desktop theme (GTK apps in
this rice aren't part of the per-theme switcher the way polybar/rofi/
kitty/starship/dunst are - building 21 full GTK themes to cover it was
judged out of proportion to the payoff), and whose window this rice's own
setup disables (autostart Hidden=true + `systemctl --user mask
evolution-alarm-notify.service`) so it never appears at all. Routing
through dunst instead means calendar reminders automatically pick up
whichever theme is currently active (dunst is themed the same way as
kitty/rofi/starship) and automatically respect Do Not Disturb (dunst's own
pause state already suppresses every notify-send call while DND is on -
no separate gsettings toggle needed the way the old popup required).

Uses the real EDataServer/ECal GObject Introspection API (the same one
evolution-alarm-notify itself is built on) to enumerate calendars and
expand recurring events correctly, rather than re-parsing raw .ics data -
confirmed working against this machine's real calendars (Google, Exchange/
visma.com, local) before writing this, including reading each VALARM's
actual TRIGGER duration (e.g. "10 minutes before"), not a hardcoded lead
time, so a reminder set for a specific event keeps firing at the time that
event's own alarm actually specifies.
"""
import gi
gi.require_version("EDataServer", "1.2")
gi.require_version("ECal", "2.0")
gi.require_version("ICalGLib", "3.0")
from gi.repository import EDataServer, ECal, ICalGLib

import json
import os
import subprocess
import sys
import time

def _local_timezone():
    # Fallback for a genuinely floating ICalTime (get_timezone() returns
    # None) - see floating_safe_as_timet() below for the actual bug this
    # works around. Read /etc/localtime's symlink target rather than
    # hardcoding a zone name, so this keeps working if the system's
    # timezone ever changes.
    try:
        path = os.path.realpath("/etc/localtime")
        name = path.split("/usr/share/zoneinfo/", 1)[1]
        tz = ICalGLib.Timezone.get_builtin_timezone(name)
        if tz:
            return tz
    except Exception:
        pass
    return ICalGLib.Timezone.get_utc_timezone()

LOCAL_TZ = _local_timezone()

def floating_safe_as_timet(ical_time):
    # ICalTime.as_timet() (no zone argument) ALWAYS interprets the wall-
    # clock fields as UTC - confirmed directly against a real event: its
    # DTSTART correctly carried an attached "Europe/Stockholm" tzid
    # (get_timezone() was NOT None) and get_hour()/get_minute() correctly
    # read 13:40, yet as_timet() still returned 15:40 CEST. It simply
    # never consults the attached zone. as_timet_with_zone(that same
    # attached zone) gives the correct 13:40. This had gone unnoticed
    # because Exchange/Google meeting invites almost always store DTSTART
    # in real UTC already (is_utc() true), where the "always assume UTC"
    # behavior happens to be correct by coincidence - it only breaks on
    # events with an explicit local zone or a genuinely floating time
    # (e.g. a quick event added via a calendar app's own popup), silently
    # shifting every alarm by the local UTC offset (here, +2h/CEST).
    if ical_time is None:
        return None
    if ical_time.is_utc():
        return ical_time.as_timet()
    tz = ical_time.get_timezone() or LOCAL_TZ
    return ical_time.as_timet_with_zone(tz)

STATE_FILE = os.path.expanduser("~/.cache/calendar-reminder-notified.json")
POLL_INTERVAL = 30  # seconds between polls
LOOKBACK = 120  # seconds - catches alarms that became due since the last poll, with margin
INSTANCE_WINDOW = 14 * 24 * 3600  # how far ahead to expand recurring instances (14 days)
# How far back generate_instances_sync's own query range has to start -
# separate from LOOKBACK (which only gates which alarms count as "due" once
# instances are already found). Confirmed live: at least some real events
# (e.g. modified occurrences of a recurring meeting) silently vanish from
# generate_instances_sync's results when the query's start time is within
# roughly an hour of the event's own start - passed LOOKBACK's 120s here
# instead, the query missed real alarms every single time regardless of
# polling health (reproduced directly against this account's own real
# calendar data, not assumed). A query starting a full day back reliably
# finds them; LOOKBACK still does the actual narrow due/not-due filtering
# below, so this only widens what gets *considered*, not what fires.
QUERY_LOOKBACK = 24 * 3600
STATE_MAX_AGE = 3 * 24 * 3600  # prune notified-keys older than this

def load_notified():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def save_notified(notified):
    now = time.time()
    pruned = {k: v for k, v in notified.items() if now - v < STATE_MAX_AGE}
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(pruned, f)
    except Exception:
        pass
    return pruned

def notify(summary, location, start_ts):
    when = time.strftime("%H:%M", time.localtime(start_ts))
    body = when if not location else f"{when} — {location}"
    # -t 0 (explicit infinite expire-time) forces dunst to never
    # auto-dismiss this, independent of urgency - confirmed live: it stays
    # displayed indefinitely with plain -u normal too. Deliberately NOT
    # using -u critical for this: this rice's dunstrc hardcodes
    # urgency_critical to red text/frame in every theme, which would make
    # calendar reminders the one thing that ignores whichever theme is
    # actually active. dunst has no clickable close button regardless of
    # urgency - dismissal is still just clicking the notification (dunst's
    # own default left-click action), same as any other notification.
    subprocess.run(
        [
            "notify-send", "-a", "Calendar", "-i", "x-office-calendar",
            "-u", "normal", "-t", "0", "-h", "string:x-dunst-stack-tag:calendar-reminder",
            summary, body,
        ],
        check=False,
    )

def find_due(sources, now):
    due = []
    window_end = now + INSTANCE_WINDOW

    def instance_cb(icalcomp, instance_start, instance_end, user_data, cancellable):
        start_ts = floating_safe_as_timet(instance_start)
        if start_ts is None:
            return True
        uid = icalcomp.get_uid()
        idx = 0
        va = icalcomp.get_first_component(ICalGLib.ComponentKind.VALARM_COMPONENT)
        while va:
            trigger_prop = va.get_first_property(ICalGLib.PropertyKind.TRIGGER_PROPERTY)
            if trigger_prop:
                trig = trigger_prop.get_trigger()
                dur = trig.get_duration()
                if dur:
                    notify_at = start_ts + dur.as_int()
                    if now - LOOKBACK <= notify_at <= now:
                        key = f"{uid}:{int(start_ts)}:{idx}"
                        summary_prop = icalcomp.get_first_property(ICalGLib.PropertyKind.SUMMARY_PROPERTY)
                        location_prop = icalcomp.get_first_property(ICalGLib.PropertyKind.LOCATION_PROPERTY)
                        due.append((
                            key,
                            summary_prop.get_summary() if summary_prop else "(untitled event)",
                            location_prop.get_location() if location_prop else None,
                            start_ts,
                        ))
            idx += 1
            va = icalcomp.get_next_component(ICalGLib.ComponentKind.VALARM_COMPONENT)
        return True

    for src in sources:
        try:
            client = ECal.Client.connect_sync(src, ECal.ClientSourceType.EVENTS, 5, None)
            client.generate_instances_sync(int(now - QUERY_LOOKBACK), int(window_end), None, instance_cb, None)
        except Exception as e:
            print(f"calendar-reminder-daemon: skipping {src.get_display_name()}: {e}", file=sys.stderr)

    return due

def main():
    notified = load_notified()
    while True:
        try:
            registry = EDataServer.SourceRegistry.new_sync(None)
            sources = [
                s for s in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)
                if s.get_enabled()
            ]
            now = time.time()
            due = find_due(sources, now)
            fired = False
            for key, summary, location, start_ts in due:
                if key in notified:
                    continue
                notify(summary, location, start_ts)
                notified[key] = now
                fired = True
            if fired:
                notified = save_notified(notified)
        except Exception as e:
            print(f"calendar-reminder-daemon: error: {e}", file=sys.stderr)
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
EOF
chmod +x "$BIN/calendar-reminder-daemon.py"

log "Writing calendar-reminder-daemon guard-and-launch wrapper..."
cat > "$BIN/calendar-reminder-daemon-launch.sh" <<'EOF'
#!/usr/bin/env bash
# Guard-and-launch wrapper for calendar-reminder-daemon.py, kept as its own
# script rather than inlined in sway's exec line. Inlining it as
# `sh -c 'pgrep -f calendar-reminder-daemon.py >/dev/null || python3
# ~/.local/bin/calendar-reminder-daemon.py'` looked fine but never actually
# worked: pgrep -f matches against a process's FULL command line, and that
# inline sh -c command's own argv literally contains the text
# "calendar-reminder-daemon.py" (twice - once in the pgrep pattern, once in
# the fallback command) - so the guard matched itself every single time,
# always finding a "match" and never falling through to actually launch the
# daemon. Confirmed directly: a real reboot left the daemon never running
# at all, silently, no error anywhere - the exact same shape of bug as the
# xdg-desktop-portal duplication guard, just self-matching instead of
# duplicating. Kept as a separate file so pgrep -f's search text has no
# reason to appear in the checking process's own command line at all.
pgrep -f calendar-reminder-daemon.py >/dev/null || exec python3 ~/.local/bin/calendar-reminder-daemon.py
EOF
chmod +x "$BIN/calendar-reminder-daemon-launch.sh"

# ----------------------------------------------------------------------------
# 6c2. Battery watcher - low-battery and "charger not keeping up" warnings
# ----------------------------------------------------------------------------
# sway has no battery warnings of its own (GNOME/KDE do): the waybar battery
# widget only shows the level, so a battery running down - including while
# plugged in to a charger too weak for the current load - went unnoticed
# until the laptop died. Pop-ups go through dunst; the hard backstop is
# UPower's critical action (see 10b2).
log "Writing battwatch.sh..."
cat > "$BIN/battwatch.sh" <<'EOF'
#!/usr/bin/env bash
# Checks the battery once a minute and warns via notify-send (dunst):
#   - plugged in but still draining (charger not keeping up), after two
#     checks in a row, so plugging in/unplugging doesn't cause false alarms
#   - low at 15%, critical at 8% while discharging
# Each warning fires once per event, not every minute; they share one dunst
# stack tag, so a newer warning replaces an older one. Started once from
# sway's config (exec, not exec_always); the flock makes a second copy exit
# at once, without pgrep and its self-matching pitfalls.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/battwatch.lock"
flock -n 9 || exit 0

# The laptop's own battery (BAT*), not a mouse/keyboard battery such as
# hidpp_battery_* (scope=Device).
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[ -n "$BAT" ] || exit 0   # no battery: a desktop, nothing to watch

on_ac() {  # any external supply (barrel charger or USB-C) delivering power
  local s
  for s in /sys/class/power_supply/*; do
    case "$(cat "$s/type" 2>/dev/null)" in
      Mains|USB|USB_C|USB_PD)
        [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && return 0 ;;
    esac
  done
  return 1
}
notify() { notify-send -u "$1" -h string:x-dunst-stack-tag:battwatch "$2" "$3"; }

drain_count=0 warned_drain=0 warned_low=0 warned_crit=0
while :; do
  cap=$(cat "$BAT/capacity" 2>/dev/null || echo 100)
  st=$(cat "$BAT/status" 2>/dev/null)
  if on_ac; then
    warned_low=0 warned_crit=0
    if [ "$st" = Discharging ]; then
      drain_count=$((drain_count + 1))
      if [ "$drain_count" -ge 2 ] && [ "$warned_drain" = 0 ]; then
        notify critical "Charger not keeping up" "Plugged in but the battery is still draining ($cap%). Check the charger's wattage, or connect it directly instead of through a dock."
        warned_drain=1
      fi
    else
      drain_count=0 warned_drain=0
    fi
  else
    drain_count=0 warned_drain=0
    if [ "$st" = Discharging ]; then
      if [ "$cap" -le 8 ] && [ "$warned_crit" = 0 ]; then
        notify critical "Battery critical" "$cap% left - plug in now. The laptop powers off at 5%."
        warned_crit=1 warned_low=1
      elif [ "$cap" -le 15 ] && [ "$warned_low" = 0 ]; then
        notify normal "Battery low" "$cap% left"
        warned_low=1
      fi
    fi
  fi
  sleep 60
done
EOF
chmod +x "$BIN/battwatch.sh"

# ----------------------------------------------------------------------------
# 6d. Disable the redundant tray applets' own autostart entries
# ----------------------------------------------------------------------------
# network-manager-applet/pasystray/blueman all ship their OWN
# /etc/xdg/autostart/*.desktop entries independent of the sway exec lines
# above - removing those exec lines alone isn't enough, since
# dex-autostart -a -e sway (further up in the sway config) would still pick
# these up and relaunch them. The standard fix for a system-wide autostart
# entry you don't want, without touching the system file itself (which
# would need root and would affect every user), is a per-user override with
# Hidden=true in ~/.config/autostart/ using the same filename.
log "Disabling nm-applet/pasystray/blueman-applet's own autostart entries (polybar's widgets replace their tray icons)..."
mkdir -p "$CONF/autostart"
for entry in nm-applet pasystray blueman; do
  cat > "$CONF/autostart/$entry.desktop" <<EOF
[Desktop Entry]
Name=$entry
Exec=$entry
Type=Application
Hidden=true
EOF
done

# evolution-alarm-notify's own reminder popup is always Catppuccin Mocha
# regardless of the active desktop theme and isn't covered by this rice's
# theme switcher (GTK apps aren't themed per-theme here - see
# calendar-reminder-daemon.py above for the rationale). Same Hidden=true
# autostart override as above, but evolution-alarm-notify is ALSO
# D-Bus-activatable (BusName=org.gnome.Evolution-alarm-notify in its own
# systemd --user unit), which bypasses a plain autostart Hidden=true the
# moment anything touches its D-Bus name - `systemctl --user mask` is
# needed in addition to actually stop it from ever running.
log "Disabling evolution-alarm-notify's own popup (calendar-reminder-daemon.py replaces it)..."
cat > "$CONF/autostart/org.gnome.Evolution-alarm-notify.desktop" <<EOF
[Desktop Entry]
Name=Evolution Alarm Notify
Exec=evolution-alarm-notify
Type=Application
Hidden=true
EOF
systemctl --user mask evolution-alarm-notify.service >/dev/null 2>&1 || warn "Could not mask evolution-alarm-notify.service - its D-Bus-activated popup may still appear."

# ----------------------------------------------------------------------------
# 6e. snixembed (StatusNotifierItem -> legacy XEmbed tray proxy)
# ----------------------------------------------------------------------------
# Not packaged for Fedora. Builds cleanly from source with the vala/
# gtk3-devel/libdbusmenu(-gtk3)-devel packages already installed in section
# 1 - best-effort like the Nerd Font download above, since a build failure
# here shouldn't be able to take down the rest of the script (you'd just
# lose SNI tray icons for apps like OBS/1Password/Discord; the legacy-
# protocol tray icons this script's own widgets don't already replace would
# still work without it).
if ! command -v snixembed >/dev/null 2>&1; then
  log "Building snixembed from source (proxies modern tray icons for polybar)..."
  SNIXEMBED_TMPDIR="$(mktemp -d)"
  if git clone --depth 1 https://git.sr.ht/~steef/snixembed "$SNIXEMBED_TMPDIR" >/dev/null 2>&1 \
      && make -C "$SNIXEMBED_TMPDIR" >/dev/null 2>&1 \
      && make -C "$SNIXEMBED_TMPDIR" PREFIX="$HOME/.local" install >/dev/null 2>&1; then
    log "snixembed built and installed to $BIN/snixembed."
  else
    warn "snixembed build failed (network issue, or a missing/renamed build dependency) - SNI-only tray icons (1Password, Discord, OBS, etc.) won't appear in the tray until you build it manually from https://git.sr.ht/~steef/snixembed."
  fi
  rm -rf "$SNIXEMBED_TMPDIR"
else
  log "snixembed already installed, skipping build."
fi

# ----------------------------------------------------------------------------
# 7. rofi
# ----------------------------------------------------------------------------
log "Writing rofi config..."
mkdir -p "$CONF/rofi"
cat > "$CONF/rofi/config.rasi" <<'EOF'
configuration {
    modi: "drun,run,window";
    show-icons: true;
    icon-theme: "Papirus-Dark";
    display-drun: " Apps";
    display-run: " Run";
    display-window: " Windows";
}
@theme "current"
EOF


# ----------------------------------------------------------------------------
# 9. kitty
# ----------------------------------------------------------------------------
log "Writing kitty config..."
mkdir -p "$CONF/kitty"
cat > "$CONF/kitty/kitty.conf" <<'EOF'
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
font_size        11.5

background_opacity 0.90
window_padding_width 10
confirm_os_window_close 0

# Colors come from current.conf (a copy of one of themes/*.conf, chosen via
# ~/.local/bin/waybar-theme.sh) rather than being set directly here, so a
# theme switch can retheme every already-open kitty window without a
# restart via `kitty @ set-colors`. kitty always appends the PID to a unix
# socket path regardless of what's given here (confirmed empirically -
# listen_on unix:/tmp/kitty-mgns actually creates /tmp/kitty-mgns-<PID>,
# not the literal path), so {kitty_pid} is spelled out explicitly to match
# what kitty actually does and to keep each window's socket distinct when
# more than one is open at once.
allow_remote_control yes
listen_on unix:/tmp/kitty-mgns-{kitty_pid}
include current.conf
EOF


# ----------------------------------------------------------------------------
# 9c. Colorpicker (Mod+shift+g) - grab any on-screen pixel's color as hex
# ----------------------------------------------------------------------------
log "Writing colorpicker script..."
cat > "$BIN/colorpicker.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Grab any on-screen pixel's color as hex and copy it to the clipboard.
# slurp -p picks a
# single point, grim captures just that pixel, ImageMagick samples it, wl-copy
# puts the hex on the Wayland clipboard. A small solid swatch PNG is generated
# as the notification icon so the popup shows the picked color, not just text.
set -uo pipefail

for dep in slurp grim magick wl-copy; do
  if ! command -v "$dep" &>/dev/null; then
    notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "'$dep' is not installed"
    exit 1
  fi
done

# slurp -p: point mode, outputs "x,y 1x1". A plain cancel (Escape) exits slurp
# non-zero -> stay silent (user cancel).
GEOM=$(slurp -p 2>/dev/null) || exit 0
[ -n "$GEOM" ] || exit 0

# Capture the single pixel and ask ImageMagick for its sRGB triplet.
PIX=$(grim -g "$GEOM" -t ppm - 2>/dev/null | magick - -format '%[pixel:p{0,0}]' txt:- 2>/dev/null | tail -n1)
if [ -z "$PIX" ]; then
  notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "failed to sample pixel"
  exit 1
fi

# Parse "srgb(r,g,b)" / "srgba(r,g,b,a)" decimals into #RRGGBB (0-255 range;
# magick's txt: output is 8-bit decimals here, not Q16 scaled).
RGB=$(printf '%s' "$PIX" | grep -oE 'srgba?\([0-9]+,[0-9]+,[0-9]+' | head -1 | grep -oE '[0-9]+' | head -3)
read -r R G B <<< "$(printf '%s ' "$RGB")"
if [ -z "${R:-}" ] || [ -z "${G:-}" ] || [ -z "${B:-}" ]; then
  notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "could not parse color: $PIX"
  exit 1
fi
HEX=$(printf '#%02X%02X%02X' "$R" "$G" "$B")

printf '%s' "$HEX" | wl-copy
SWATCH="$(mktemp --suffix=.png)"
magick -size 64x64 xc:"$HEX" "$SWATCH" 2>/dev/null || true
notify-send -h string:x-dunst-stack-tag:colorpicker -i "$SWATCH" "Colorpicker" "$HEX copied to clipboard"
( sleep 5; rm -f "$SWATCH" ) &
disown || true
RICE_EOF
chmod +x "$BIN/colorpicker.sh"

# ----------------------------------------------------------------------------
# 9d. swappy (screenshot editor) config
# ----------------------------------------------------------------------------
# Without a config, swappy defaults save_dir to $XDG_DESKTOP_DIR/$HOME/Desktop
# and every Save (button or Ctrl+S) drops a swappy-*.png on the Desktop
# silently - reads like "nothing happens". Point it at the same directory
# screenshot.sh uses, with the date format the old rice's swappy files carry.
log "Writing swappy config..."
mkdir -p "$CONF/swappy"
cat > "$CONF/swappy/config" <<'EOF'
[Default]
save_dir=$HOME/Pictures/Screenshots
save_filename_format=%Y-%m-%d_%H-%M.png
EOF

# ----------------------------------------------------------------------------
# 10. fastfetch
# ----------------------------------------------------------------------------
log "Writing fastfetch config..."
mkdir -p "$CONF/fastfetch"
cat > "$CONF/fastfetch/config.jsonc" <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "display": { "separator": "  " },
  "modules": [
    "title", "separator", "os", "host", "kernel", "uptime", "packages",
    "shell", "wm", "de", "terminal", "cpu", "gpu", "memory", "disk", "colors"
  ]
}
EOF

# ----------------------------------------------------------------------------
# 11. lock script (swaylock)
# ----------------------------------------------------------------------------
# swaylock-effects (the fork with the live --clock and screenshot effects)
# has no usable Fedora package: the only COPR carries an fc35-era build that
# RPM refuses over the current swaylock. Instead, build the maintained fork
# (jirutka/swaylock-effects) from source into /usr/local, which shadows the
# Fedora binary without touching its package. Best-effort: plain swaylock
# works, lock.sh just falls back to the flat look without the clock.
if command -v dnf >/dev/null 2>&1; then
  if ! swaylock --help 2>&1 | grep -q -- "--effect-blur"; then
    log "Building swaylock-effects from source (jirutka fork, into /usr/local)..."
    if sudo dnf install -y meson ninja-build wayland-devel wayland-protocols-devel \
         libxkbcommon-devel cairo-devel gdk-pixbuf2-devel pam-devel scdoc \
         >/dev/null 2>&1; then
      SLE_TMP="$(mktemp -d)"
      if git clone --depth 1 https://github.com/jirutka/swaylock-effects.git \
           "$SLE_TMP/src" >/dev/null 2>&1 \
         && meson setup "$SLE_TMP/build" "$SLE_TMP/src" --buildtype release \
             --prefix /usr/local >/dev/null 2>&1 \
         && ninja -C "$SLE_TMP/build" >/dev/null 2>&1 \
         && sudo ninja -C "$SLE_TMP/build" install >/dev/null 2>&1; then
        log "swaylock-effects built and installed - the lock gets its live clock."
      else
        warn "swaylock-effects source build failed - the lock stays plain (no clock/effects)."
      fi
      rm -rf "$SLE_TMP"
    else
      warn "swaylock-effects build deps not installable - the lock stays plain (no clock/effects)."
    fi
  fi
fi
log "Writing lock script..."

# The lock's indicator colors: Catppuccin Mocha for swaylock
# (github.com/catppuccin/swaylock, themes/mocha.conf) - subtle dark ring at
# rest, green keypress dots, blue verify, maroon wrong. lock.sh passes this
# to swaylock via -C, so it is the single source of lock colors; the font
# and indicator geometry are the rice's own additions on top.
mkdir -p "$CONF/swaylock"
cat > "$CONF/swaylock/config" <<'EOF'
# Catppuccin Mocha for swaylock - github.com/catppuccin/swaylock (MIT)
color=1e1e2e
bs-hl-color=f5e0dc
caps-lock-bs-hl-color=f5e0dc
caps-lock-key-hl-color=a6e3a1
inside-color=1e1e2e
inside-clear-color=1e1e2e
inside-caps-lock-color=1e1e2e
inside-ver-color=1e1e2e
inside-wrong-color=1e1e2e
key-hl-color=a6e3a1
layout-bg-color=00000000
layout-border-color=00000000
layout-text-color=cdd6f4
line-color=00000000
line-clear-color=00000000
line-caps-lock-color=00000000
line-ver-color=00000000
line-wrong-color=00000000
ring-color=313244
ring-clear-color=f5e0dc
ring-caps-lock-color=fab387
ring-ver-color=89b4fa
ring-wrong-color=eba0ac
separator-color=00000000
text-color=cdd6f4
text-clear-color=f5e0dc
text-caps-lock-color=fab387
text-ver-color=89b4fa
text-wrong-color=eba0ac
# rice additions: the terminal font and a chunky indicator to match the bar
font=JetBrainsMono Nerd Font
indicator-radius=110
indicator-thickness=14
EOF
cat > "$BIN/lock.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Sway rice lock screen: Catppuccin Mocha scheme (~/.config/swaylock/config,
# seeded from github.com/catppuccin/swaylock) over a blurred live screenshot,
# with a random fortune quote baked in below the indicator - and, when the
# binary is swaylock-effects, a live clock at center.
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

# A random short geek quote under the ring. The i3 rice showed these via
# i3lock-color's --greeter flag; the sway engine has no greeter text option
# at all, so the quote is composited into the lock background itself
# (fortune -s: short one-liner fortunes only, folded by caption:).
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
done < <(swaymsg -t get_outputs 2>/dev/null | \
         jq -r '.[] | select(.active) | "\(.name) \(.current_mode.width) \(.current_mode.height)"')

# swaylock-effects (the fork with the live --clock) takes priority when the
# binary supports it; plain swaylock uses the same backgrounds, just without
# the clock. NOTE: this fork (jirutka v1.7.0.0) has no --time-color/
# --date-color - the clock renders in the config's text-color (Catppuccin
# cdd6f4) instead of the preview's lavender.
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
RICE_EOF
chmod +x "$BIN/lock.sh"

# ----------------------------------------------------------------------------
# sudo password feedback: show a "*" per keystroke at sudo's password
# prompt instead of nothing. Written via a temp file checked with
# `visudo -cf` before install - a malformed file in /etc/sudoers.d breaks
# sudo for everyone, so it's never written straight into place. Safe on
# any sudo >= 1.8.31 (the pwfeedback buffer overflow, CVE-2019-18634, was
# fixed there). Only affects sudo's own prompt - passwd/su/ssh/pinentry
# use their own prompts with no such option.
# ----------------------------------------------------------------------------
log "Enabling sudo password feedback (stars) (needs sudo)..."
PWFB_TMP="$(mktemp)"
echo 'Defaults pwfeedback' > "$PWFB_TMP"
if sudo visudo -cf "$PWFB_TMP" >/dev/null; then
  sudo install -m 0440 -o root -g root "$PWFB_TMP" /etc/sudoers.d/pwfeedback
else
  log "WARNING: pwfeedback sudoers snippet failed visudo validation, skipped"
fi
rm -f "$PWFB_TMP"

# ----------------------------------------------------------------------------
# 10b2. UPower critical-battery action - the backstop under battwatch.sh
# ----------------------------------------------------------------------------
# UPower acts on its own at critical battery even without a desktop
# environment, but distro defaults act only at ~2% with
# CriticalPowerAction=Auto/HybridSleep, which needs hibernation - not
# available with zram-only swap - so the laptop can just die instead. Set
# it explicitly: warn at 20%/8% and power off cleanly at 5%, matching the
# battwatch.sh pop-ups. Each key's active line is replaced, or the key is
# appended if it has none (the file's commented-out examples are left
# alone). Laptops only.
if ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1 && [ -f /etc/UPower/UPower.conf ]; then
  log "Setting UPower critical-battery action to power off at 5% (needs sudo)..."
  for kv in UsePercentageForPolicy=true PercentageLow=20 PercentageCritical=8 PercentageAction=5 CriticalPowerAction=PowerOff; do
    k="${kv%%=*}"
    if grep -qE "^[[:space:]]*$k=" /etc/UPower/UPower.conf; then
      sudo sed -i -E "s|^[[:space:]]*$k=.*|$kv|" /etc/UPower/UPower.conf
    else
      echo "$kv" | sudo tee -a /etc/UPower/UPower.conf >/dev/null
    fi
  done
  sudo systemctl try-restart upower 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# 10c. DPMS-wake-after-resume hook - dropped on sway: swayidle's resume
#      hook re-powers the displays after suspend.
# ----------------------------------------------------------------------------
# (X11 DPMS-wake systemd-sleep hook dropped - swayidle handles resume on sway)

# ----------------------------------------------------------------------------
# 11a. Block-art screensaver (Terminal Text Effects) - Mod+Escape, and shown
#      automatically before an idle-triggered lock (see --with-screensaver
#      above). Inspired by Omarchy's built-in one, same underlying tool
#      (`tte`) AND the same logo style Omarchy itself ships (a solid Unicode
#      half-block render, not typed ASCII letters), just run in a plain
#      fullscreen kitty window instead of Omarchy's Astal/AGS shell (which this
#      rice doesn't have an equivalent of).
# ----------------------------------------------------------------------------
log "Installing Terminal Text Effects (tte) via pipx for the screensaver..."
if command -v pipx >/dev/null 2>&1; then
  pipx install terminaltexteffects 2>/dev/null \
    || warn "pipx install terminaltexteffects failed - the screensaver (Mod+Escape, and before an idle lock) won't work until you run it manually."
else
  warn "pipx not found - skipping the screensaver's tte dependency. Install pipx and run 'pipx install terminaltexteffects' to enable it later."
fi

log "Writing screensaver script..."
cat > "$BIN/screensaver.sh" <<'EOF'
#!/usr/bin/env bash
# Block-art screensaver, inspired by Omarchy's built-in one - same underlying
# tool (Terminal Text Effects / `tte`, pipx-installed) AND the same logo
# style Omarchy itself ships (its logo.txt is a solid Unicode half-block
# render, not typed ASCII letters - see omarchy-transcode-ascii --mode
# block), just run in a plain fullscreen kitty window instead of Omarchy's
# Astal/AGS shell (which this rice doesn't have an equivalent of). Exits on any
# keypress OR mouse movement.
# tte is pipx-installed into ~/.local/bin - which the swayidle context's
# PATH (inherited from sway's login-time snapshot) does NOT include, so a
# bare-name call failed with "tte not found" whenever the screensaver was
# triggered by the idle timeout. Re-add it here so both entry paths work:
# the idle lock and the on-demand Mod+Escape bind.
export PATH="$HOME/.local/bin:$PATH"
LOGO="$HOME/.config/screensaver/logo.txt"
FEDORA_SVG="/usr/share/fedora-logos/fedora_logo.svg"
if [ ! -f "$LOGO" ]; then
  mkdir -p "$(dirname "$LOGO")"
  if command -v magick >/dev/null 2>&1 && [ -f "$FEDORA_SVG" ]; then
    # Two source pixel rows -> one terminal row, using a half-block glyph
    # (█ both on, ▀ top only, ▄ bottom only, space neither) to double the
    # effective vertical resolution - the same trick Omarchy's own
    # transcoder uses. The alpha channel (not color/threshold) is the mask,
    # since the SVG's logo shape is opaque on a transparent background.
    magick -background none "$FEDORA_SVG" -auto-orient \
      -alpha extract -alpha off -bordercolor black -border 1 -trim +repage \
      -resize 80x52 -threshold 50% -negate -compress none pbm:- 2>/dev/null \
      | awk '
        BEGIN { block["11"]="█"; block["10"]="▀"; block["01"]="▄"; block["00"]=" " }
        { sub(/#.*/, ""); for (i = 1; i <= NF; i++) token[++n] = $i }
        END {
          w = token[2]; h = token[3]; off = 4
          for (y = 0; y < h; y += 2) {
            line = ""
            for (x = 0; x < w; x++) {
              top = token[off + (y * w) + x]
              bottom = (y + 1 < h) ? token[off + ((y + 1) * w) + x] : 0
              line = line block[top bottom]
            }
            sub(/[ ]+$/, "", line)
            print line
          }
        }' > "$LOGO"
  fi
  # Fall back to the old typed-letter banner if ImageMagick or the Fedora
  # logo SVG isn't present (non-standard install) or the pipeline above
  # produced nothing.
  [ -s "$LOGO" ] || fastfetch --logo Fedora -s none > "$LOGO"
fi

# A plain fullscreen terminal only sees mouse movement as input if it typed
# something into stdin (it doesn't, by default) - polling the pointer
# position via xdotool is what actually catches "moved the mouse" as a
# dismiss trigger, not just keypresses.
mouse_pos() { xdotool getmouselocation --shell 2>/dev/null | awk -F= '/^X=/{x=$2} /^Y=/{y=$2} END{print x, y}'; }
LAST_POS="$(mouse_pos)"

while true; do
  # tte plays one effect to completion (several seconds) before returning,
  # so waiting for it to finish before checking for input meant dismissing
  # could take as long as the current animation - background it instead and
  # poll for either dismiss condition every 0.2s, killing it the instant
  # either fires, instead of waiting for it to finish on its own.
  #
  # tte's canvas defaults to the size of the input text itself (--canvas-*
  # -1), which is why effects were confined to a small box in the corner -
  # canvas-width/height 0 matches the actual terminal size instead, and the
  # anchor flags center both the canvas in the terminal and the logo within
  # that canvas, so effects (rain, fireworks, etc.) spread across the whole
  # screen rather than staying cramped around the logo's own bounding box.
  tte --random-effect --frame-rate 60 --input-file "$LOGO" \
    --canvas-width 0 --canvas-height 0 \
    --anchor-canvas c --anchor-text c &
  TTE_PID=$!

  while kill -0 "$TTE_PID" 2>/dev/null; do
    if read -t 0.2 -n 1 -s; then
      kill "$TTE_PID" 2>/dev/null
      exit 0
    fi
    CUR_POS="$(mouse_pos)"
    if [ -n "$CUR_POS" ] && [ "$CUR_POS" != "$LAST_POS" ]; then
      kill "$TTE_PID" 2>/dev/null
      exit 0
    fi
  done
done
EOF
chmod +x "$BIN/screensaver.sh"
# logo.txt is generated lazily on first real run (see screensaver.sh above) -
# not pre-generated here, so there's only one copy of the block-art pipeline
# to keep in sync.

# ----------------------------------------------------------------------------
# 11b. Power menu (lock / shutdown / reboot / suspend / logout via rofi)
# ----------------------------------------------------------------------------
log "Writing power menu theme..."
cat > "$CONF/rofi/powermenu.rasi" <<'EOF'
* {
    base:     #1e1e2eff;
    mantle:   #181825ff;
    text:     #cdd6f4ff;
    subtext:  #a6adc8ff;
    mauve:    #cba6f7ff;
    surface0: #313244ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 18px;
    padding: 24px;
}

mainbox {
    children: [ listview ];
}

listview {
    columns: 5;
    lines: 1;
    spacing: 10px;
    fixed-columns: true;
    scrollbar: false;
}

element {
    children: [ element-text ];
    padding: 26px;
    border-radius: 16px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 14px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
    /* Nerd Font glyphs' advance width isn't visually symmetric around their
       ink - 0.5 (true center) renders visibly right-of-center, so this is
       nudged left. */
    horizontal-align: 0.32;
    vertical-align: 0.5;
}
EOF

log "Writing power menu script..."
cat > "$BIN/powermenu.sh" <<'EOF'
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
  *""*)   swaymsg exit ;;
  *""*)   systemctl reboot ;;
  *""*) systemctl poweroff ;;
esac
EOF
chmod +x "$BIN/powermenu.sh"

# ----------------------------------------------------------------------------
# 11c. Volume/brightness OSD (dunst progress-bar popup on each key press)
# ----------------------------------------------------------------------------
log "Writing volume/brightness OSD scripts..."
cat > "$BIN/osd-volume.sh" <<'EOF'
#!/usr/bin/env bash
# usage: osd-volume.sh up|down|mute
case "$1" in
  up)   pactl set-sink-volume @DEFAULT_SINK@ +5% ;;
  down) pactl set-sink-volume @DEFAULT_SINK@ -5% ;;
  mute) pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
esac
VOL=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+%' | head -1 | tr -d '%')
MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')
if [ "$MUTED" = "yes" ]; then
  notify-send -h string:x-dunst-stack-tag:volume -h int:value:0 "Volume muted"
else
  notify-send -h string:x-dunst-stack-tag:volume -h int:value:"$VOL" "Volume: ${VOL}%"
fi
EOF
chmod +x "$BIN/osd-volume.sh"

cat > "$BIN/osd-brightness.sh" <<'EOF'
#!/usr/bin/env bash
# usage: osd-brightness.sh up|down
case "$1" in
  up)   brightnessctl set +5% ;;
  down) brightnessctl set 5%- ;;
esac
# brightnessctl -m info: device,class,currentvalue,percentage,maxvalue
PCT=$(brightnessctl -m info 2>/dev/null | cut -d, -f4 | tr -d '%')
notify-send -h string:x-dunst-stack-tag:brightness -h int:value:"$PCT" "Brightness: ${PCT}%"
EOF
chmod +x "$BIN/osd-brightness.sh"

# ensure ~/.local/bin is on PATH
if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  log "Added ~/.local/bin to PATH in .bashrc (source it or re-login)."
fi

# ----------------------------------------------------------------------------
# 11c2. Wi-Fi picker (rofi) - reachable by left-clicking the polybar
#       wireless widget.
# ----------------------------------------------------------------------------
log "Writing Wi-Fi picker script..."
cat > "$BIN/wifi-menu.sh" <<'EOF'
#!/usr/bin/env bash
# Rofi-based wifi picker - scans nearby networks and connects, unlike
# nm-connection-editor (which only edits already-saved connection
# profiles, and has no "browse nearby networks" view at all). Reuses
# current.rasi, the same rofi theme ~/.local/bin/waybar-theme.sh already
# keeps in sync with the active desktop theme, so this menu retints for
# free instead of needing its own GTK-theming project the way
# nm-connection-editor itself would (a real, ~6000-line, 156-color GTK3
# stylesheet - a much bigger job for a rarely-opened settings dialog than
# reusing rofi's own already-switchable theme here).
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/current.rasi"

# Best-effort rescan - a scan already in progress (e.g. NetworkManager's
# own periodic one) makes this fail with a harmless "Scanning not allowed
# immediately following previous scan" error; the list below just falls
# back to whatever NetworkManager already has cached from that scan.
nmcli device wifi rescan >/dev/null 2>&1 || true

# IN-USE/SSID/SECURITY/SIGNAL, sorted by signal descending (nmcli's own
# default sort) - dedupe by SSID keeping the first (=strongest) row seen,
# since the same network's multiple access points/bands all share one
# SSID and only need one menu entry. Skip blank SSIDs (hidden networks -
# nothing meaningful to connect to by name).
mapfile -t ROWS < <(
  nmcli -t -f IN-USE,SSID,SECURITY,SIGNAL device wifi list 2>/dev/null \
    | awk -F: '
        $2 == "" { next }
        !seen[$2]++ { print }
      '
)

if [ "${#ROWS[@]}" -eq 0 ]; then
  notify-send "Wi-Fi" "No networks found."
  exit 0
fi

declare -A SECURITY_OF SIGNAL_OF
MENU=""
CONNECTED_SSID=""
for row in "${ROWS[@]}"; do
  IFS=':' read -r inuse ssid security signal <<< "$row"
  SECURITY_OF["$ssid"]="$security"
  SIGNAL_OF["$ssid"]="$signal"
  if [ "$inuse" = "*" ]; then
    CONNECTED_SSID="$ssid"
    MENU+="${ssid} (connected)"$'\n'
  elif [ -z "$security" ] || [ "$security" = "--" ]; then
    MENU+="${ssid}"$'\n'
  else
    MENU+="${ssid} 󰌾"$'\n'
  fi
done

CHOSEN_LINE="$(printf '%s' "$MENU" | rofi -dmenu -i -p "Wi-Fi" -theme "$ROFI_THEME")"
[ -z "$CHOSEN_LINE" ] && exit 0

# Strip the decorations added above to recover the real SSID for lookup.
SSID="${CHOSEN_LINE%% 󰌾}"
SSID="${SSID%% (connected)}"

if [ "$SSID" = "$CONNECTED_SSID" ]; then
  notify-send "Wi-Fi" "Already connected to \"$SSID\"."
  exit 0
fi

# A saved connection profile (from a previous successful connect) already
# has whatever credentials it needs - reuse it directly rather than
# prompting for a password NetworkManager doesn't actually need again.
if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$SSID"; then
  if nmcli connection up "$SSID" >/dev/null 2>&1; then
    notify-send "Wi-Fi" "Connected to \"$SSID\"."
  else
    notify-send "Wi-Fi" "Failed to connect to \"$SSID\"."
  fi
  exit 0
fi

SECURITY="${SECURITY_OF[$SSID]:-}"
if [ -z "$SECURITY" ] || [ "$SECURITY" = "--" ]; then
  if nmcli device wifi connect "$SSID" >/dev/null 2>&1; then
    notify-send "Wi-Fi" "Connected to \"$SSID\"."
  else
    notify-send "Wi-Fi" "Failed to connect to \"$SSID\"."
  fi
  exit 0
fi

PASSWORD="$(rofi -dmenu -password -i -p "Password for $SSID" -theme "$ROFI_THEME")"
[ -z "$PASSWORD" ] && exit 0

if nmcli device wifi connect "$SSID" password "$PASSWORD" >/dev/null 2>&1; then
  notify-send "Wi-Fi" "Connected to \"$SSID\"."
else
  notify-send "Wi-Fi" "Failed to connect to \"$SSID\" - wrong password?"
fi
EOF
chmod +x "$BIN/wifi-menu.sh"

# ----------------------------------------------------------------------------
# 11d. Screensaver logo setter (text or image -> block art) - reachable from
#      the app menu below, and standalone as its own script.
# ----------------------------------------------------------------------------
log "Writing screensaver logo setter script..."
cat > "$BIN/set-screensaver-text.sh" <<'EOF'
#!/usr/bin/env bash
# Set the screensaver logo (~/.config/screensaver/logo.txt) from either
# typed text or an image file - both converted to the same solid Unicode
# half-block art (█▀▄) the Fedora logo uses in screensaver.sh. Matches
# Omarchy's own screensaver branding (`omarchy branding screensaver
# text|image`), just as one plain script instead of a subcommand.
#
# Usage:
#   set-screensaver-text.sh                  # prompts for text or an image path
#   set-screensaver-text.sh "some text"      # renders that text directly
#   set-screensaver-text.sh path/to/logo.png # converts that image directly (png/svg/jpg/...)
#
# Image mode is a monochrome silhouette render (1-bit threshold, no
# grayscale/color survives) - great for logos/icons/simple line art, same
# as Omarchy's own transcoder; a detailed photo will come out as a crude
# blob, not something with real detail. Assumes a dark subject on a light
# background (or real transparency, like an icon's alpha channel) - there's
# no --invert equivalent here for a light-subject-on-dark-photo yet.
#
# Overwrites $LOGO every run - that's intentional here (unlike
# screensaver.sh's own lazy Fedora-logo generation, which only writes if
# missing).
set -euo pipefail

LOGO="$HOME/.config/screensaver/logo.txt"
FONT="/usr/share/fonts/truetype/nerd-fonts/JetBrainsMonoNerdFont-Bold.ttf"
FEDORA_SVG="/usr/share/fedora-logos/fedora_logo.svg"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick (magick) is not installed." >&2
  echo "  Ubuntu/Debian: sudo apt install imagemagick" >&2
  echo "  Fedora:        sudo dnf install ImageMagick" >&2
  echo "  Arch:          sudo pacman -S imagemagick" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOGO")"

INPUT="${1:-}"
if [ -z "$INPUT" ]; then
  read -r -p "Screensaver text, a path to an image, or 'reset' for the Fedora default: " INPUT
fi
if [ -z "$INPUT" ]; then
  echo "Nothing entered, leaving $LOGO unchanged." >&2
  exit 1
fi

TMP_PNG="$(mktemp --suffix=.png)"
trap 'rm -f "$TMP_PNG"' EXIT

# Two source pixel rows -> one terminal row, using a half-block glyph
# (█ both on, ▀ top only, ▄ bottom only, space neither) - identical to the
# conversion screensaver.sh runs on the Fedora logo SVG.
to_block_art() {
  awk '
    BEGIN { block["11"]="█"; block["10"]="▀"; block["01"]="▄"; block["00"]=" " }
    { sub(/#.*/, ""); for (i = 1; i <= NF; i++) token[++n] = $i }
    END {
      w = token[2]; h = token[3]; off = 4
      for (y = 0; y < h; y += 2) {
        line = ""
        for (x = 0; x < w; x++) {
          top = token[off + (y * w) + x]
          bottom = (y + 1 < h) ? token[off + ((y + 1) * w) + x] : 0
          line = line block[top bottom]
        }
        sub(/[ ]+$/, "", line)
        print line
      }
    }'
}

if [ "$(printf '%s' "$INPUT" | tr '[:upper:]' '[:lower:]')" = "reset" ]; then
  # Reset mode - regenerates the exact same Fedora block-art logo
  # screensaver.sh itself lazily creates on first run (identical magick
  # pipeline against the real Fedora SVG, reusing this script's own
  # to_block_art rather than a second copy), so picking this is
  # indistinguishable from having never customized the logo at all.
  if [ -f "$FEDORA_SVG" ]; then
    magick -background none "$FEDORA_SVG" -auto-orient \
      -alpha extract -alpha off -bordercolor black -border 1 -trim +repage \
      -resize 80x52 -threshold 50% -negate -compress none pbm:- 2>/dev/null \
      | to_block_art >"$LOGO"
  fi
  # Same fallback screensaver.sh itself uses if the Fedora SVG isn't
  # installed (non-Fedora system) or the pipeline above produced nothing.
  if [ ! -s "$LOGO" ]; then
    command -v fastfetch >/dev/null 2>&1 && fastfetch --logo Fedora -s none >"$LOGO"
  fi
elif [ -f "$INPUT" ]; then
  # Image mode. Real transparency (an icon/logo on a clear background) is
  # the mask if present - dark pixels are already threshold-negated
  # correctly the same way the Fedora SVG is in screensaver.sh. Otherwise
  # (a flattened PNG/JPG/photo with no alpha channel) fall back to
  # grayscale + threshold with NO negate, since dark-subject-on-light-
  # background needs the opposite polarity from the alpha-mask case -
  # verified against a real black-shape-on-white test image, not assumed.
  read -r ALPHA_MIN ALPHA_MAX <<<"$(magick -background none "$INPUT" -alpha extract -format '%[fx:minima] %[fx:maxima]' info: 2>/dev/null)"
  USE_ALPHA=false
  if awk -v min="${ALPHA_MIN:-1}" -v max="${ALPHA_MAX:-0}" 'BEGIN { exit !(min < 0.999 && max > min) }'; then
    USE_ALPHA=true
  fi
  if [ "$USE_ALPHA" = true ]; then
    magick -background none "$INPUT" -auto-orient \
      -alpha extract -alpha off -bordercolor black -border 1 -trim +repage \
      -resize 80x52 -threshold 50% -negate -compress none pbm:- 2>/dev/null \
      | to_block_art >"$LOGO"
  else
    magick -background none "$INPUT" -auto-orient \
      -alpha remove -alpha off -colorspace Gray \
      -bordercolor black -border 1 -trim +repage \
      -resize 80x52 -threshold 50% -compress none pbm:- 2>/dev/null \
      | to_block_art >"$LOGO"
  fi
else
  # Text mode. Point size is tuned so short phrases end up roughly the same
  # visual scale as the block Fedora logo (which targets an 80-column
  # canvas) once resized below - longer text just shrinks further to fit,
  # same tradeoff arbitrarily-sized source images have above.
  FONT_ARGS=()
  [ -f "$FONT" ] && FONT_ARGS=(-font "$FONT") # else ImageMagick's own default
  magick -background none -fill white "${FONT_ARGS[@]}" -pointsize 120 \
    label:"$INPUT" "$TMP_PNG"
  magick "$TMP_PNG" -auto-orient \
    -alpha extract -alpha off -bordercolor black -border 1 -trim +repage \
    -resize 80x52 -threshold 50% -negate -compress none pbm:- 2>/dev/null \
    | to_block_art >"$LOGO"
fi

if [ ! -s "$LOGO" ]; then
  echo "Block-art conversion produced nothing." >&2
  exit 1
fi

echo
echo "Preview:"
cat "$LOGO"
echo
echo "Saved to $LOGO — screensaver.sh will pick it up on next run."
EOF
chmod +x "$BIN/set-screensaver-text.sh"

# ----------------------------------------------------------------------------
# 11d3. AI window startup folder - reachable from the app menu below, and
#       standalone as its own script. Stores a single path in a plain text
#       file that ai-window-toggle.sh reads on every fresh launch (passed
#       to `vibe --workdir`, its own documented flag for scoping which
#       directory it treats as the project root - not a plain `cd`, so it
#       works the same regardless of what shell/rc ends up running kitty).
#       Only takes effect for a NEW AI window - same "applies at creation
#       time, not retroactively" caveat as everything else in this rice
#       that isn't live-recolored/reloaded (border colors, for_window
#       rules); an already-running session keeps whatever folder it
#       started with until you close and reopen it.
# ----------------------------------------------------------------------------
log "Writing AI window startup-folder script..."
cat > "$BIN/set-ai-window-folder.sh" <<'EOF'
#!/usr/bin/env bash
# Sets the folder Mistral Vibe CLI starts in the next time Mod+a launches a
# fresh AI window (see ai-window-toggle.sh). `read -e -i` gives readline
# tab-completion and a pre-filled, editable default - same interactive
# style as set-screensaver-text.sh's own prompt, just editable in place
# instead of typed from scratch.
set -euo pipefail

CONF_DIR="$HOME/.config/ai-window"
WORKDIR_FILE="$CONF_DIR/workdir"
mkdir -p "$CONF_DIR"

CURRENT="$(cat "$WORKDIR_FILE" 2>/dev/null || echo "$HOME")"
echo "AI window startup folder is currently: $CURRENT"
read -r -e -i "$CURRENT" -p "New startup folder (tab-completes): " INPUT
INPUT="${INPUT:-$CURRENT}"
# read -e doesn't expand a leading ~ itself - do it manually before the
# directory check below, same as any other path a user might type here.
INPUT="${INPUT/#\~/$HOME}"

if [ ! -d "$INPUT" ]; then
  echo "Not a directory: $INPUT" >&2
  echo
  echo "Press any key to close..."
  read -r -n 1 -s
  exit 1
fi

echo "$INPUT" > "$WORKDIR_FILE"
echo "AI window will now start in: $INPUT"
echo
echo "Press any key to close..."
read -r -n 1 -s
EOF
chmod +x "$BIN/set-ai-window-folder.sh"

# ----------------------------------------------------------------------------
# 11e1. Polybar theme switcher - reachable from the app menu below, and
#       standalone as its own script.
# ----------------------------------------------------------------------------
log "Writing polybar theme switcher script..."
cat > "$BIN/waybar-theme.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Lists available themes (~/.config/waybar/themes/*/) via rofi and, on
# selection, applies matching waybar + rofi + kitty + starship + dunst + sway
# border-color themes together, so one pick retints the whole desktop instead
# of just the bar. Each is its own COMPLETE, standalone config (a waybar
# config.jsonc + style.css, a rofi .rasi pair, a kitty color .conf, a starship
# .toml, a dunst dunstrc, a sway client.* border fragment) applied with a plain
# file copy. One pick retints the whole desktop.
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
# The per-theme border fragments (client.* color lines) are valid sway
# syntax; the sway config includes the written current-borders.conf. Keyed
# by base name (no -square/-numbered/-alt).
SWAY_THEMES_DIR="$HOME/.config/sway/themes"
SWAY_CURRENT="$HOME/.config/sway/current-borders.conf"
mkdir -p "$HOME/.config/sway"
NVIM_COLORS_DIR="$HOME/.config/nvim/colors"
NVIM_CURRENT="$NVIM_COLORS_DIR/current.lua"
# The active theme's name; seeded by section 6 and re-written on every pick.
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
# Some themes @import a sibling palette by RELATIVE path (e.g. v2.1's
# `@import "./rose-pine.css"`, or a `colors.css`). style.css is copied to
# ~/.config/waybar/, so a relative `./` import resolves against that dir, not
# the theme dir - copy every sibling .css there too, or the import fails and
# waybar drops the ENTIRE stylesheet (the bar renders unstyled/blank).
for __css in "$WAYBAR_DIR"/*.css; do
  [ -f "$__css" ] || continue
  [ "$(basename "$__css")" = "style.css" ] && continue
  cp "$__css" "$HOME/.config/waybar/"
done
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
RICE_EOF
chmod +x "$BIN/waybar-theme.sh"

log "Writing app-theme-sync.sh..."
cat > "$BIN/app-theme-sync.sh" <<'EOF'
#!/usr/bin/env bash
# Brings the terminal apps that draw their OWN colors in line with the
# active desktop theme - kitty's colors alone don't reach them. Run by
# waybar-theme.sh after every theme switch (and once by the setup script),
# reading the theme's kitty palette and sway focused-border color that
# waybar-theme.sh has just put in place.
#   - cliamp (Mod+m): a custom theme, ~/.config/cliamp/themes/rice.toml
#     (cliamp's own custom-theme format; no bg, so the themed kitty
#     background shows through), selected in its config and applied live
#     to a running player via `cliamp theme rice`, which re-reads the file
#   - Mistral Vibe (Mod+a): Textual's ansi-dark/ansi-light theme, which
#     draws with the terminal's 16 colors - kitty's live recolor then
#     reaches it too, even mid-session. light vs dark from the background.
#   - Strata (Mod+E file manager): a custom theme in its own TOML format
#     (~/.config/strata/themes/rice.toml), live-reloaded by the app.
KITTY_CURRENT="$HOME/.config/kitty/current.conf"
BORDERS_CURRENT="$HOME/.config/sway/current-borders.conf"
[ -f "$KITTY_CURRENT" ] || exit 0
kc() { awk -v k="$1" '$1 == k { print $2; exit }' "$KITTY_CURRENT"; }
hex() { [[ "$1" =~ ^#[0-9A-Fa-f]{6}$ ]] && printf '%s' "$1" || printf '%s' "$2"; }

# set_toml_key <file> <key> <value>: a top-level `key = "value"`, replaced
# if present, else put first (before any [section], where top-level keys go)
set_toml_key() {
  local f="$1" k="$2" v="$3"
  mkdir -p "$(dirname "$f")"
  if [ ! -f "$f" ]; then
    printf '%s = "%s"\n' "$k" "$v" > "$f"
  elif grep -q "^$k[[:space:]]*=" "$f"; then
    sed -i "s|^$k[[:space:]]*=.*|$k = \"$v\"|" "$f"
  else
    sed -i "1i $k = \"$v\"" "$f"
  fi
}

fg="$(hex "$(kc foreground)" '#cdd6f4')"
accent="$(hex "$(awk '/^client.focused /{ print $2; exit }' "$BORDERS_CURRENT" 2>/dev/null)" "$(hex "$(kc color5)" "$fg")")"

if command -v cliamp >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/cliamp/themes"
  cat > "$HOME/.config/cliamp/themes/rice.toml" <<TOML
# Written by ~/.local/bin/app-theme-sync.sh from the active desktop theme
accent = "$accent"
bright_fg = "$fg"
fg = "$(hex "$(kc color8)" "$fg")"
green = "$(hex "$(kc color2)" '#a6e3a1')"
yellow = "$(hex "$(kc color3)" '#f9e2af')"
red = "$(hex "$(kc color1)" '#f38ba8')"
TOML
  set_toml_key "$HOME/.config/cliamp/config.toml" theme rice
  pgrep -x cliamp >/dev/null && cliamp theme rice >/dev/null 2>&1
fi

if command -v strata >/dev/null 2>&1; then
  # Strata ignores desktop GTK themes by design (it pins GTK to its own
  # built-in theme and drops GTK_THEME), so it gets themed through its
  # own custom-theme TOML instead: nine semantic tokens written from
  # the live kitty/border palette, selected once in settings.toml, and
  # live-reloaded whenever this file changes (matugen-style - a running
  # Strata re-tints every open window without a restart). Token mapping:
  # the kitty palette carries base/surface1/surface2 as background/
  # color0/color8, so surface is stepped between them and border blends
  # background with surface2; dim text is subtext (color15), danger red.
  bg_s="$(hex "$(kc background)" '#1e1e2e')"
  sur1_s="$(hex "$(kc color0)" '#4b4e55')"
  sur2_s="$(hex "$(kc color8)" '#585b70')"
  mixhex() {
    local t="${3:-50}"
    local ar=$((16#${1:1:2})) ag=$((16#${1:3:2})) ab=$((16#${1:5:2}))
    local br=$((16#${2:1:2})) bgx=$((16#${2:3:2})) bb=$((16#${2:5:2}))
    printf '#%02x%02x%02x' \
      $(( (ar * (100 - t) + br * t) / 100 )) \
      $(( (ag * (100 - t) + bgx * t) / 100 )) \
      $(( (ab * (100 - t) + bb * t) / 100 ))
  }
  mkdir -p "$HOME/.config/strata/themes"
  cat > "$HOME/.config/strata/themes/rice.toml" <<TOML
# Written by ~/.local/bin/app-theme-sync.sh from the active desktop theme
name = "Rice"
background = "$bg_s"
surface = "$(mixhex "$bg_s" "$sur1_s" 50)"
text = "$fg"
accent = "$accent"
danger = "$(hex "$(kc color1)" '#f38ba8')"
muted = "$sur1_s"
highlight = "$sur2_s"
border = "$(mixhex "$bg_s" "$sur2_s" 60)"
dim_text = "$(hex "$(kc color15)" "$fg")"
TOML
  # Strata's settings.toml requires BOTH mode and theme; a bare theme
  # key makes the file unparseable, and Strata then disables saving
  # for the whole session to preserve it (verified against the
  # upstream Preferences schema).
  set_toml_key "$HOME/.config/strata/settings.toml" mode theme
  set_toml_key "$HOME/.config/strata/settings.toml" theme rice
fi

if command -v vibe >/dev/null 2>&1 || [ -d "$HOME/.vibe" ]; then
  bg="$(hex "$(kc background)" '#1e1e2e')"
  r=$((16#${bg:1:2})); g=$((16#${bg:3:2})); b=$((16#${bg:5:2}))
  if [ $(( (r * 299 + g * 587 + b * 114) / 1000 )) -gt 140 ]; then
    vibe_theme=ansi-light
  else
    vibe_theme=ansi-dark
  fi
  set_toml_key "$HOME/.vibe/config.toml" theme "$vibe_theme"
fi

# VS Code: follow the active desktop theme - the shim rewrites
# workbench.colorTheme in settings.json (JSONC-safe); VS Code watches
# the file and applies the new editor theme live.
~/.local/bin/vscode-theme-sync || true

# The portal processes (xdg-desktop-portal{,-gtk,-wlr}) draw GTK file
# dialogs and popovers for apps like Edge, and inherit the systemd user
# manager's env - which the GTK block above just updated. They only read
# it at start, so restart them to follow the switch (they're dbus/
# systemd-run units; try-restart is a no-op if a unit doesn't exist).
systemctl --user try-restart xdg-desktop-portal-manual.service   xdg-desktop-portal-gtk-manual.service xdg-desktop-portal-wlr-manual.service 2>/dev/null || true

# libadwaita apps (gnome-calendar and every GNOME 47+ app) deliberately
# block theme CSS - the only levers GNOME allows are the color-scheme
# (already prefer-dark via gsettings) and the PRESET accent colors. Map
# the active theme's accent hue to the closest preset so highlights,
# selected-day and buttons follow the rice's hue as closely as GNOME
# permits.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$BORDERS_CURRENT" <<'ACCENTEOF'
import colorsys, re, subprocess, sys
borders = open(sys.argv[1], encoding="utf-8").read() if len(sys.argv) > 1 else ""
m = re.search(r"client\.focused\s+(#[0-9a-fA-F]{6})", borders)
accent = m.group(1) if m else "#cba6f7"
r, g, b = (int(accent[i:i+2], 16) / 255 for i in (1, 3, 5))
h, l, s = colorsys.rgb_to_hls(r, g, b)
if s < 0.15:
    preset = "slate" if l < 0.5 else "slate"
else:
    deg = h * 360
    preset = ("red" if deg < 15 else "orange" if deg < 45 else "yellow" if deg < 70
              else "green" if deg < 160 else "teal" if deg < 190 else "blue"
              if deg < 250 else "purple" if deg < 290 else "pink" if deg < 345 else "red")
subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "accent-color", preset],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ACCENTEOF
fi
exit 0
EOF
chmod +x "$BIN/app-theme-sync.sh"
"$BIN/app-theme-sync.sh" || true

# ----------------------------------------------------------------------------
# 11c2. Cursor theme switcher (Mod+alt+space -> Cursor Theme) - switches
#       between the 6 Qogir variants installed above.
# ----------------------------------------------------------------------------
log "Writing cursor-theme.sh..."
cat > "$BIN/cursor-theme.sh" <<'EOF'
#!/usr/bin/env bash
# Switches the mouse cursor theme between the 6 real Qogir variants
# installed during setup (see the Qogir cursor theme step) - the -Light
# suffix variants aren't offered since they're cursor-identical aliases of
# their non-Light counterpart. Applies live: sway's own root cursor
# updates immediately via `swaymsg seat seat0 xcursor_theme`, the sway
# config's include file is rewritten so a reload keeps the pick, and
# environment.d + GTK settings carry it to newly started apps.
#
# Usage:
#   cursor-theme.sh          # prompts via rofi
#   cursor-theme.sh <name>   # applies directly, no prompt
set -euo pipefail

THEMES=(Qogir Qogir-Dark Qogir-Manjaro Qogir-Manjaro-Dark Qogir-Ubuntu Qogir-Ubuntu-Dark)

CHOSEN="${1:-}"
if [ -z "$CHOSEN" ]; then
  CHOSEN="$(printf '%s\n' "${THEMES[@]}" | rofi -dmenu -i -p "Cursor Theme" -theme ~/.config/rofi/current.rasi)"
  [ -z "$CHOSEN" ] && exit 0
fi

valid=0
for t in "${THEMES[@]}"; do [ "$t" = "$CHOSEN" ] && valid=1; done
if [ "$valid" -ne 1 ]; then
  notify-send "Cursor Theme" "Unknown theme: $CHOSEN"
  exit 1
fi

mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/cursor-theme.conf" <<CONF
XCURSOR_THEME=$CHOSEN
XCURSOR_SIZE=24
CONF

# Sway, not X11: the compositor's own pointer comes from the seat's
# xcursor_theme setting, which the main sway config re-applies from this
# include file on every reload (the old hardcoded "xcursor_theme Adwaita"
# line in the config re-pinned Adwaita on each reload, silently undoing
# the switch).
mkdir -p "$HOME/.config/sway"
printf 'seat seat0 xcursor_theme %s 24\n' "$CHOSEN" > "$HOME/.config/sway/cursor-theme.conf"

for gtk_settings in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  [ -f "$gtk_settings" ] && sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CHOSEN/" "$gtk_settings"
done
gsettings set org.gnome.desktop.interface cursor-theme "$CHOSEN" 2>/dev/null || true

# Apply live: sway's seat command retints the pointer immediately, no
# reload needed; reload stays as the belt-and-braces path via the include
# file above.
swaymsg "seat seat0 xcursor_theme $CHOSEN 24" >/dev/null 2>&1 || true
swaymsg reload >/dev/null 2>&1 || true
# Make apps launched via systemd/dbus (portals, search providers) pick up
# the new theme without a re-login too.
systemctl --user set-environment XCURSOR_THEME="$CHOSEN" XCURSOR_SIZE=24 2>/dev/null || true

notify-send "Cursor Theme" "Switched to $CHOSEN"
EOF
chmod +x "$BIN/cursor-theme.sh"
cat > "$BIN/icon-theme.sh" <<'EOF'
#!/usr/bin/env bash
# icon-theme switcher - the icon-theme counterpart of cursor-theme.sh.
#
# WHY THIS EXISTS: on a bare sway session there is no xsettings daemon, so
# GTK3/GTK4 apps read the icon theme from ~/.config/gtk-3.0/settings.ini and
# gtk-4.0/settings.ini - NOT from gsettings (gsettings only matters when a
# settings daemon bridges dconf into xsettings, which nothing here runs).
# lxappearance only writes ~/.gtkrc-2.0 (GTK2), so picking a theme there
# silently never reaches GTK3/4 apps. This script writes every location
# consistently in one shot: settings.ini (gtk-3 + gtk-4), ~/.gtkrc-2.0 and
# gsettings (for any future daemon/portal consumer).
#
# Usage:
#   icon-theme.sh          # prompts via rofi with the installed themes
#   icon-theme.sh <name>   # applies directly, no prompt
set -euo pipefail

# Real icon themes only: an index.theme with an Icon Theme/Name, from both
# /usr/share/icons and ~/.local/share/icons (user installs), deduped.
ALL_DIRS=("$HOME/.local/share/icons" "/usr/share/icons")
declare -A SEEN
THEMES=()
for d in "${ALL_DIRS[@]}"; do
  [ -d "$d" ] || continue
  for t in "$d"/*/; do
    name="$(basename "$t")"
    [ -f "$t/index.theme" ] && [ "${SEEN[$name]:-}" = "" ] || continue
    grep -q "^\[Icon Theme\]" "$t/index.theme" 2>/dev/null || continue
    SEEN[$name]=1
    THEMES+=("$name")
  done
done
if [ "${#THEMES[@]}" -eq 0 ]; then
  notify-send "Icon Theme" "No icon themes found in /usr/share/icons"
  exit 1
fi

CHOSEN="${1:-}"
if [ -z "$CHOSEN" ]; then
  CHOSEN="$(printf '%s\n' "${THEMES[@]}" | rofi -dmenu -i -p "Icon Theme" -theme ~/.config/rofi/current.rasi)"
  [ -n "$CHOSEN" ] || exit 0
fi

valid=0
for t in "${THEMES[@]}"; do [ "$t" = "$CHOSEN" ] && valid=1; done
if [ "$valid" -ne 1 ]; then
  notify-send "Icon Theme" "Unknown icon theme: $CHOSEN"
  exit 1
fi

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  if [ -f "$f" ] && grep -q '^gtk-icon-theme-name=' "$f"; then
    sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$CHOSEN/" "$f"
  elif [ -f "$f" ]; then
    sed -i "/^\[Settings\]/a gtk-icon-theme-name=$CHOSEN" "$f"
  else
    printf '[Settings]\ngtk-icon-theme-name=%s\n' "$CHOSEN" > "$f"
  fi
done

if [ -f "$HOME/.gtkrc-2.0" ] && grep -q '^gtk-icon-theme-name=' "$HOME/.gtkrc-2.0"; then
  sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=\"$CHOSEN\"/" "$HOME/.gtkrc-2.0"
else
  printf 'gtk-icon-theme-name="%s"\n' "$CHOSEN" >> "$HOME/.gtkrc-2.0"
fi

gsettings set org.gnome.desktop.interface icon-theme "$CHOSEN" 2>/dev/null || true

notify-send "Icon Theme" "Switched to $CHOSEN (newly started apps pick it up)"

# NOTE: already-running apps keep their loaded icon theme until restarted -
# same as every other GTK setting on a session without a settings daemon.
EOF
chmod +x "$BIN/icon-theme.sh"

# ----------------------------------------------------------------------------
# 11d2. Keybinding cheat sheet (Mod+alt+space -> Keybinding Help) - printed in
#       a floating kitty window, dismissed on any keypress.
# ----------------------------------------------------------------------------
log "Writing keybinding cheat sheet script..."
cat > "$BIN/keybindings-help.sh" <<'EOF'
#!/usr/bin/env bash
# Prints this rice's keybinding cheat sheet (same content as the README's
# "Keybinding Cheat Sheet" table) in a floating kitty window, in the
# terminal's own palette - kitty's colors follow the desktop theme, so the
# cheat sheet does too (it used to hardcode Catppuccin Mocha's RGB values).
# Dismisses on any keypress. Reachable from the app menu
# (Mod+alt+space -> Keybinding Help) and standalone.
MAUVE=$'\033[35m'    # magenta (color5) - key column
TEXT=$'\033[39m'     # default foreground - descriptions
SUBTEXT=$'\033[90m'  # bright black (color8) - divider
RESET=$'\033[0m'

# binding|action - same rows as the README cheat sheet table, kept in sync
# by hand (this is a small, curated display list, not something parsed out
# of the sway config, same shape as app-menu.sh's own LABELS/COMMANDS). Sorted
# alphabetically by key; where a key has more than one binding, the plain
# Mod+<key> form comes before any Mod+<modifier>+<key> form, and
# multi-modifier forms come after single-modifier ones - same rule the
# README table's rows follow.
ROWS=(
  "Mod+1..9|Switch to workspace 1-9"
  "Mod+shift+1..9|Move window to workspace 1-9"
  "Mod+a|AI window (Mistral Vibe CLI), toggle show/hide"
  "Mod+shift+a|Mistral Vibe web app, toggle show/hide"
  "Mod+b|Split horizontal (for next window)"
  "Mod+c|Toggle caffeine (inhibit screen-lock/sleep)"
  "Mod+shift+c|Reload Sway"
  "Mod+e|File manager (Strata)"
  "Mod+shift+e|Exit Sway (with confirm)"
  "Mod+Escape|Block-art screensaver, on demand"
  "Mod+f|Fullscreen toggle"
  "Mod+shift+f|Floating toggle"
  "Mod+shift+g|Colorpicker (click a pixel, hex copied to clipboard)"
  "Mod+h|Focus left"
  "Mod+ctrl+h|Focus monitor to the left"
  "Mod+shift+h|Move window left"
  "Mod+ctrl+shift+h|Move workspace to the monitor on the left"
  "Mod+i|Show this keybinding help"
  "Mod+j|Focus down"
  "Mod+shift+j|Move window down"
  "Mod+k|Focus up"
  "Mod+shift+k|Move window up"
  "Mod+l|Lock screen"
  "Mod+ctrl+l|Focus monitor to the right"
  "Mod+ctrl+shift+l|Move workspace to the monitor on the right"
  "Mod+m|CLIamp terminal music player, toggle show/hide"
  "Mod+shift+m|CLIamp first-time setup"
  "Mod+n|Toggle Do Not Disturb"
  "Mod+p|Printer setup"
  "Mod+shift+p|Power menu"
  "Print|Screenshot (slurp region select, swappy annotation if installed)"
  "Mod+r|Resize mode (h/j/k/l, Return/Escape to exit)"
  "Mod+shift+r|Reload Sway"
  "Mod+Return|Open kitty"
  "Mod+shift+q|Close focused window"
  "Mod+semicolon|Focus right"
  "Mod+shift+semicolon|Move window right"
  "Mod+space|Rofi app launcher (drun)"
  "Mod+alt+space|App menu (this menu)"
  "Mod+ctrl+space|Toggle tiling/floating focus"
  "Mod+shift+space|Rofi run launcher"
  "Mod+t|Toggle container layout split direction"
  "Mod+v|Split vertical (for next window)"
  "Mod+shift+v|Clipboard history (copyq)"
  "Mod+shift+w|Wallpaper picker"
  "Mod+shift+XF86Assistant|Claude Desktop, toggle show/hide"
  "XF86Audio Play/Next/Prev|Media control (playerctl)"
  "XF86Audio Raise/Lower/Mute Volume|Volume, with a dunst level popup"
  "XF86MonBrightness Up/Down|Brightness, with a dunst level popup"
)

WIDTH=0
for row in "${ROWS[@]}"; do
  binding="${row%%|*}"
  [ "${#binding}" -gt "$WIDTH" ] && WIDTH="${#binding}"
done

clear
echo "${MAUVE}Keybinding Cheat Sheet${RESET}  ${SUBTEXT}(Mod = Super/Windows key)${RESET}"
echo "${SUBTEXT}$(printf '%.0s─' $(seq 1 70))${RESET}"
echo
for row in "${ROWS[@]}"; do
  binding="${row%%|*}"
  action="${row#*|}"
  printf "  ${MAUVE}%-${WIDTH}s${RESET}   ${TEXT}%s${RESET}\n" "$binding" "$action"
done
echo
echo "${SUBTEXT}Press any key to close...${RESET}"
read -r -n 1 -s
EOF
chmod +x "$BIN/keybindings-help.sh"

# ----------------------------------------------------------------------------
# 11e. App menu (Mod+alt+space) - Omarchy-style floating rofi menu for reaching
#      this rice's own utility scripts in one place.
# ----------------------------------------------------------------------------
log "Writing app menu script..."
cat > "$BIN/app-menu.sh" <<'EOF'
#!/usr/bin/env bash
# Floating rofi menu for reaching this rice's own utility scripts in one
# place - inspired by Omarchy's Super-key menu system, scoped down to
# actions that actually exist here rather than Omarchy's much larger
# package/theme management menu (no equivalent in this setup). Actions that
# need interactive input (Set Screensaver) open in their own floating kitty
# window - see the AppMenuTask for_window rule in the sway config - matching how
# copyq/cliamp already float; everything else just runs directly.
LABELS=(
  $'  Desktop Theme'
  $'  Cursor Theme'
  $'  Icon Theme'
  $'  Set Screensaver Text/Image'
  $'  Preview Screensaver'
  $'  Set AI Window Folder'
  $'  AI API Keys'
  $'  Toggle Caffeine'
  $'  Toggle Do Not Disturb'
  $'  Music Player'
  $'  Clipboard History'
  $'  Colorpicker'
  $'  Lock Screen'
  $'  Power Menu'
  $'  Reload Sway'
  $'  Restart Waybar'
  $'  Keybinding Help'
)
COMMANDS=(
  "~/.local/bin/waybar-theme.sh"
  "~/.local/bin/cursor-theme.sh"
  "~/.local/bin/icon-theme.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/set-screensaver-text.sh"
  "kitty --class Screensaver -e ~/.local/bin/screensaver.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/set-ai-window-folder.sh"
  "if [ -x ~/.local/bin/ai-key-manager ]; then ~/.local/bin/ai-key-manager; else ai-key-manager; fi"
  "~/.local/bin/caffeine-toggle.sh"
  "~/.local/bin/dnd-toggle.sh"
  "~/.local/bin/cliamp-toggle.sh"
  "copyq toggle"
  "~/.local/bin/colorpicker.sh"
  "~/.local/bin/lock.sh --with-screensaver"
  "~/.local/bin/powermenu.sh"
  "swaymsg reload"
  "~/.local/bin/waybar-launch.sh"
  "kitty --class KeybindingsHelp -e ~/.local/bin/keybindings-help.sh"
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
EOF
chmod +x "$BIN/app-menu.sh"

log "Writing cliamp-toggle.sh..."
cat > "$BIN/cliamp-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Toggles the floating Cliamp window via sway's scratchpad instead of leaving
# "quit the TUI" as the only way to get it out of the way (kitty exits the
# moment its child process does, so closing the window has always meant
# killing playback too). cliamp exposes both MPRIS and its own IPC socket
# regardless of whether its window is visible (confirmed directly: still
# listed in `playerctl -l` and answering `cliamp status` with the window
# scratchpad-hidden) - so hiding it doesn't stop playback or lose control,
# the existing polybar-media.sh widget still shows prev/play-pause/next.
# Quitting cliamp itself (q inside the TUI) still fully stops it - this is
# a separate, non-destructive way to just tuck the window away.
#
# `scratchpad show` only toggles a window that has already been moved to
# the scratchpad at least once - on a plain floating window it just fails
# (confirmed: swaymsg reports success:false, does nothing). So the first
# hide request for a freshly-launched window falls back to `move
# scratchpad`; every request after that is a real, working toggle.
#
# The scratchpad's own remembered geometry isn't reliable here - confirmed
# directly: after being hidden and shown again, the window reappeared at
# rect (-350, -250), well off a 1920x1200 screen, instead of the centered
# position it had before. Reassert size/position explicitly every time
# rather than trusting `scratchpad show` to restore it correctly.
# Harmless when the window ends up hidden instead of shown (confirmed:
# repositioning a scratchpad-hidden window doesn't un-hide it).
if pgrep -x cliamp >/dev/null; then
  swaymsg '[con_mark="cliamp-scratch"] scratchpad show' | grep -q '"success": *true' \
    || swaymsg '[con_mark="cliamp-scratch"] move scratchpad' >/dev/null
  swaymsg '[con_mark="cliamp-scratch"] resize set 700 500, move position center' >/dev/null
else
  exec kitty --class Cliamp -e cliamp
fi
EOF
chmod +x "$BIN/cliamp-toggle.sh"

log "Writing cliamp-setup.sh..."
cat > "$BIN/cliamp-setup.sh" <<'EOF'
#!/usr/bin/env bash
# Opens cliamp's own provider-configuration wizard (`cliamp setup`) in a
# floating window - a genuinely different command from bare `cliamp`
# (bound to $mod+m via cliamp-toggle.sh), not the same app in a different
# environment. Bare `cliamp` is just the player; picking/configuring a
# remote source (Navidrome, Plex, Spotify, ...) only happens inside
# `cliamp setup`'s own "Pick a provider to configure" screen, which the
# player's own TUI has no path to (confirmed directly: Tab/Enter/Escape
# inside the player cycle Playlist/Equalizer/Source/Provider views, none
# of which reach the setup wizard). Not scratchpad-toggled like cliamp
# itself - the wizard is a one-shot flow that exits on its own once you're
# done, so it's launched fresh every time rather than minimized/resumed.
exec kitty --class CliampSetup -e cliamp setup
EOF
chmod +x "$BIN/cliamp-setup.sh"

log "Writing ai-window-toggle.sh (Mistral Vibe CLI)..."
cat > "$BIN/ai-window-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Toggles a floating "AI window" running Mistral Vibe CLI (`vibe`) via sway's
# scratchpad - same show/hide-without-killing pattern as cliamp-toggle.sh,
# so an in-progress Vibe conversation/session isn't lost by just tucking
# the window away.
#
# Doesn't copy cliamp-toggle.sh's "try `scratchpad show`, fall back to
# `move scratchpad` on failure" approach - confirmed live that it's
# unreliable here: `scratchpad show` on this window reported success:true
# while actually leaving it shoved off-screen (negative coordinates) on its
# *current* workspace, still counted visible/focused, instead of actually
# parking it in sway's hidden __i3_scratch workspace. Asking sway directly
# which workspace the marked container is on right now and picking the one
# correct action for that state sidesteps the ambiguous return value
# entirely: no mark found -> launch fresh; already in __i3_scratch -> show
# it; anywhere else (i.e. currently visible) -> hide it. Also sidesteps
# tracking `vibe` by process name, which wouldn't work anyway - it's a
# Python console_scripts entry point, so under `ps`/`pgrep -x` it reports
# as "python3", never "vibe".
mark=ai-window-scratch

current_ws=$(swaymsg -t get_tree | python3 -c "
import json, sys
t = json.load(sys.stdin)
def walk(n, ws=None):
    if n.get('type') == 'workspace':
        ws = n.get('name')
    if 'ai-window-scratch' in n.get('marks', []):
        print(ws or '')
        sys.exit(0)
    for c in n.get('nodes', []) + n.get('floating_nodes', []):
        walk(c, ws)
walk(t)
")

if [ -z "$current_ws" ]; then
  # Startup folder is configurable via the app menu's "Set AI Window
  # Folder" entry (set-ai-window-folder.sh) - $HOME if never set. `vibe
  # --workdir` is its own documented flag for this, not a plain `cd`
  # before exec, so it's scoped correctly regardless of shell/rc.
  workdir="$(cat "$HOME/.config/ai-window/workdir" 2>/dev/null || echo "$HOME")"
  exec kitty --class AIVibe -e vibe --workdir "$workdir"
elif [ "$current_ws" = "__i3_scratch" ]; then
  swaymsg "[con_mark=\"$mark\"] scratchpad show" >/dev/null
  swaymsg "[con_mark=\"$mark\"] resize set 900 650, move position center" >/dev/null
else
  swaymsg "[con_mark=\"$mark\"] move scratchpad" >/dev/null
fi
EOF
chmod +x "$BIN/ai-window-toggle.sh"

log "Writing claude-desktop-toggle.sh..."
cat > "$BIN/claude-desktop-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Toggles Claude Desktop via sway's scratchpad - same show/hide-without-
# killing pattern as ai-window-toggle.sh/cliamp-toggle.sh, so an
# in-progress conversation isn't lost by just tucking the window away.
# Same direct "ask sway which workspace the marked container is on right
# now" approach as ai-window-toggle.sh, for the same reason: `scratchpad
# show`'s own success:true return doesn't reliably mean the window is
# actually visible.
mark=claude-desktop-scratch

current_ws=$(swaymsg -t get_tree | python3 -c "
import json, sys
t = json.load(sys.stdin)
def walk(n, ws=None):
    if n.get('type') == 'workspace':
        ws = n.get('name')
    if 'claude-desktop-scratch' in n.get('marks', []):
        print(ws or '')
        sys.exit(0)
    for c in n.get('nodes', []) + n.get('floating_nodes', []):
        walk(c, ws)
walk(t)
")

if [ -z "$current_ws" ]; then
  exec claude-desktop-unofficial
elif [ "$current_ws" = "__i3_scratch" ]; then
  swaymsg "[con_mark=\"$mark\"] scratchpad show" >/dev/null
  swaymsg "[con_mark=\"$mark\"] resize set 1200 850, move position center" >/dev/null
else
  swaymsg "[con_mark=\"$mark\"] move scratchpad" >/dev/null
fi
EOF
chmod +x "$BIN/claude-desktop-toggle.sh"

log "Writing mistral-vibe-toggle.sh..."
cat > "$BIN/mistral-vibe-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Toggles the Mistral Vibe web app (chat.mistral.ai - Le Chat was renamed
# Vibe in 2026) via sway's scratchpad, same show/hide-without-killing
# pattern as claude-desktop-toggle.sh. Mistral ships no Linux desktop app,
# so it runs in a Chromium-family browser's --app mode (no tabs/toolbar).
# --class only takes effect for a browser's first process, which is why it
# gets its own profile dir: otherwise an already-running browser would
# just open another normal window with the browser's class. Sign in once
# in that profile; it's kept between launches.
mark=mistral-vibe-scratch
url="https://chat.mistral.ai"
profile="$HOME/.local/share/mistral-vibe-app"

current_ws=$(swaymsg -t get_tree | python3 -c "
import json, sys
t = json.load(sys.stdin)
def walk(n, ws=None):
    if n.get('type') == 'workspace':
        ws = n.get('name')
    if 'mistral-vibe-scratch' in n.get('marks', []):
        print(ws or '')
        sys.exit(0)
    for c in n.get('nodes', []) + n.get('floating_nodes', []):
        walk(c, ws)
walk(t)
")

if [ -z "$current_ws" ]; then
  for b in google-chrome-stable google-chrome chromium chromium-browser brave-browser microsoft-edge-stable vivaldi-stable vivaldi; do
    if command -v "$b" >/dev/null 2>&1; then
      exec "$b" --user-data-dir="$profile" --class=MistralVibe --ozone-platform=x11 \
        --no-first-run --no-default-browser-check --app="$url"
    fi
  done
  notify-send "Mistral Vibe" "Needs a Chromium-based browser (Chrome, Chromium, Brave, Edge or Vivaldi) - install one from the post-install script's Browsers category."
elif [ "$current_ws" = "__i3_scratch" ]; then
  swaymsg "[con_mark=\"$mark\"] scratchpad show" >/dev/null
  swaymsg "[con_mark=\"$mark\"] resize set 1200 850, move position center" >/dev/null
else
  swaymsg "[con_mark=\"$mark\"] move scratchpad" >/dev/null
fi
EOF
chmod +x "$BIN/mistral-vibe-toggle.sh"

# ----------------------------------------------------------------------------
# 12. Wallpaper fallback (solid Catppuccin base color) if none exists
# ----------------------------------------------------------------------------
if [ ! -f "$CONF/sway/wallpaper.png" ]; then
  if command -v convert >/dev/null 2>&1; then
    log "Generating a solid Catppuccin-base fallback wallpaper..."
    convert -size 1920x1080 xc:'#1e1e2e' "$CONF/sway/wallpaper.png"
  else
    warn "ImageMagick not found — drop your own image at $CONF/sway/wallpaper.png"
    touch "$CONF/sway/wallpaper.png"
  fi
fi
# swaybg-restore.sh picks this up at login (exec_always) if no pick was made
# yet - press Mod+shift+w any time to choose a real image; this only seeds one.

# ----------------------------------------------------------------------------
# 13. Base GTK theme - follows the active desktop theme (best-effort, cosmetic only)
# ----------------------------------------------------------------------------
# The active desktop theme's own GTK theme (Rice-<name>, generated by the
# repo's generate-gtk-themes.py in section 15 from the [colors] block
# hancore-theme-gen.py wrote for it) - waybar-theme.sh switches it on every
# theme pick, same as the old collection. The current theme name file is
# seeded by section 6; fall back to the first HANCORE theme if it's missing.
GTK_THEME_NAME="Rice-$(cat "$HOME/.config/waybar/current-theme-name" 2>/dev/null || echo v1)"

# Qogir cursor theme (all 6 real variants - the upstream -Light suffix
# variants are skipped, since they're just aliases with identical cursor
# art to their non-Light counterpart, differing only in icon-theme colors
# this cursor-only install never uses). Without an explicit pick the
# pointer would never change at all - sway's seat default is stock
# Adwaita everywhere (GTK apps too: gtk-cursor-theme-size was already being set
# below, but never gtk-cursor-theme-name, so the size applied to a theme
# that was never actually chosen). No prebuilt cursor-only release exists
# upstream - vinceliuice/Qogir-icon-theme ships cursors bundled inside its
# own combined icon+cursor install.sh, which would also drag in the full
# icon set (this rice already uses Papirus for icons) - so this extracts
# just the cursors/ directory per variant directly from a shallow clone
# instead of running that script, writing a minimal index.theme itself
# (a real Xcursor theme only needs cursors/ + an index.theme with a Name=
# line; the full icon-listing index.theme upstream ships is for the icon
# theme half, not needed here). CURSOR_THEME_NAME below is the default
# active variant - cursor-theme.sh (11e2 below) switches between all 6
# later without re-running this install.
CURSOR_THEME_NAME="Qogir"
if [ ! -d "$HOME/.local/share/icons/Qogir" ]; then
  log "Downloading Qogir cursor theme (6 variants)..."
  QOGIR_TMPDIR="$(mktemp -d)"
  if git clone --depth 1 -q https://github.com/vinceliuice/Qogir-icon-theme.git "$QOGIR_TMPDIR" 2>/dev/null; then
    mkdir -p "$HOME/.local/share/icons"
    QOGIR_THEME_SUFFIXES=("" "-Manjaro" "-Ubuntu" "" "-Manjaro" "-Ubuntu")
    QOGIR_COLOR_SUFFIXES=("" "" "" "-Dark" "-Dark" "-Dark")
    for i in "${!QOGIR_THEME_SUFFIXES[@]}"; do
      qname="Qogir${QOGIR_THEME_SUFFIXES[$i]}${QOGIR_COLOR_SUFFIXES[$i]}"
      qdest="$HOME/.local/share/icons/$qname"
      rm -rf "$qdest"
      mkdir -p "$qdest"
      cp "$QOGIR_TMPDIR/COPYING" "$QOGIR_TMPDIR/AUTHORS" "$qdest/"
      cp -r "$QOGIR_TMPDIR/src/cursors/dist${QOGIR_THEME_SUFFIXES[$i]}${QOGIR_COLOR_SUFFIXES[$i]}/cursors" "$qdest/"
      printf '[Icon Theme]\nName=%s\n' "$qname" > "$qdest/index.theme"
    done
  else
    warn "Qogir cursor theme download failed (network issue?) - the pointer will fall back to whatever's already configured; install it manually later from https://github.com/vinceliuice/Qogir-icon-theme."
  fi
  rm -rf "$QOGIR_TMPDIR"
else
  log "Qogir cursor theme already present, skipping download."
fi

# Two real, live-confirmed gaps beyond XCURSOR_THEME/gtk-cursor-theme-name
# above - GTK apps picked up the theme fine, but polybar (and bare X11/XCB
# toolkit apps generally) kept showing the plain stock X cursor over their
# own windows:
#   1. libxcb-cursor's theme lookup only checks the legacy ~/.icons path,
#      not the XDG ~/.local/share/icons one the theme was actually
#      installed to above - symlinking every variant into ~/.icons too
#      (confirmed via real-world reports of this exact polybar symptom)
#      covers both, and lets cursor-theme.sh switch to any of them later
#      without needing to re-symlink.
#   2. Some xcb-cursor-based apps resolve the theme via the Xcursor.theme/
#      Xcursor.size X resources (X RESOURCE_MANAGER, set by `xrdb`) rather
#      than (or in addition to) the environment variables - this rice never
#      used Xresources/xrdb for anything before, so nothing ever set them.
mkdir -p "$HOME/.icons"
for qvariant in Qogir Qogir-Dark Qogir-Manjaro Qogir-Manjaro-Dark Qogir-Ubuntu Qogir-Ubuntu-Dark; do
  [ -d "$HOME/.local/share/icons/$qvariant" ] && ln -sfn "$HOME/.local/share/icons/$qvariant" "$HOME/.icons/$qvariant"
done
cat > "$HOME/.Xresources" <<EOF
Xcursor.theme: $CURSOR_THEME_NAME
Xcursor.size: 24
EOF

mkdir -p "$CONF/gtk-3.0" "$CONF/gtk-4.0"
for gtk_settings in "$CONF/gtk-3.0/settings.ini" "$CONF/gtk-4.0/settings.ini"; do
  cat > "$gtk_settings" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME_NAME
gtk-icon-theme-name=Papirus-Dark
gtk-application-prefer-dark-theme=1
gtk-font-name=Sans 10
gtk-cursor-theme-name=$CURSOR_THEME_NAME
gtk-cursor-theme-size=24
EOF
done
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
# GTK2 apps are rare these days but not extinct - ~/.gtkrc-2.0 is a
# completely different config file/format from gtk-3.0/settings.ini above
# and isn't covered by it. lxappearance (installed in section 1) is the
# standard self-service GUI for this if you'd rather pick interactively;
# this just seeds the same theme/icons so GTK2 apps don't look out of place
# by default.
if [ ! -f "$HOME/.gtkrc-2.0" ]; then
  cat > "$HOME/.gtkrc-2.0" <<EOF
gtk-theme-name="$GTK_THEME_NAME"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="Sans 10"
EOF
fi

# GTK4 apps built with libadwaita (gnome-calendar, and others) hardcode
# Adwaita/Adwaita-dark and ignore gtk-theme-name entirely by design - the
# GTK_THEME env var is the one (unsupported but working) override that still
# forces them to load a named theme's CSS. environment.d is read once at
# session start, so this only takes effect after the next login.
mkdir -p "$CONF/environment.d"
cat > "$CONF/environment.d/gtk-theme.conf" <<EOF
GTK_THEME=$GTK_THEME_NAME
EOF

# XCURSOR_THEME/XCURSOR_SIZE - read by libXcursor, which is what actually
# resolves the pointer shape for X11-native apps and anything GTK/Qt-based
# that doesn't go through gtk-cursor-theme-name specifically (set above,
# but that alone doesn't cover non-GTK apps or the root window). Same
# once-per-login caveat as GTK_THEME above.
cat > "$CONF/environment.d/cursor-theme.conf" <<EOF
XCURSOR_THEME=$CURSOR_THEME_NAME
XCURSOR_SIZE=24
EOF

# ----------------------------------------------------------------------------
# 14. HP printer plugin check (best-effort — only runs if an HP device is
#     actually present)
# ----------------------------------------------------------------------------
# CUPS + HPLIP (installed above) cover the open-source rendering path for
# most printers, but several HP models - especially older "host-based"
# LaserJets/inkjets like the LaserJet P1006/P1005/P1018 - also need a
# proprietary HP-supplied plugin for actual rasterization. Without it, jobs
# sit in the queue and silently fail with "hplip.plugin-error" /
# "m_Job initialization failed with error = 48" in
# /var/log/cups/error_log, with no obvious error shown anywhere - confirmed
# directly against a real LaserJet P1006 on this exact setup.
#
# Only checked/installed if an HP device is actually detected (CUPS's
# discovered devices, or USB vendor ID 03f0) - most printers don't need this
# at all, so there's no reason to force an interactive EULA + download on
# everyone. hp-plugin's installed state lives in /var/lib/hp/hplip.state
# under a [plugin] section.
if command -v hp-plugin >/dev/null 2>&1 \
    && (lpinfo -v 2>/dev/null | grep -qi "hp\|hewlett" || lsusb 2>/dev/null | grep -qi "03f0"); then
  if grep -qx "installed = 1" /var/lib/hp/hplip.state 2>/dev/null; then
    log "HP proprietary plugin already installed."
  else
    log "HP printer detected without its proprietary plugin installed - running hp-plugin now (accept the download/license prompts, and your sudo password when asked)..."
    hp-plugin -i || warn "hp-plugin failed or was cancelled - re-run 'hp-plugin -i' manually later if print jobs silently sit in the queue."
  fi
else
  log "No HP printer detected - skipping HP plugin check (harmless if you add one later; just run 'hp-plugin -i' then)."
fi

# ----------------------------------------------------------------------------
# 14b. Audio: pin the Jabra Link 380 to its analog output profile
# ----------------------------------------------------------------------------
# The Jabra Link 380 USB dongle exposes both an Analog Stereo profile and an
# IEC958 (S/PDIF digital) profile. WirePlumber sometimes selects - or auto-
# switches to - the IEC958 one, which plays media (Spotify, YouTube, ...) at a
# heavily attenuated level, while a call that had grabbed the analog/headset
# routing still sounds fine - making it look app-specific when it's really the
# device profile. This drop-in forces the analog profile and disables auto-
# profile switching so it can't flip back. The +input:mono-fallback variant
# keeps the headset microphone available for meetings.
#
# The device.name match is a regex (leading ~) on the vendor portion only, so
# it works regardless of the dongle's serial number (0b0e is Jabra's USB
# vendor id). Harmless on machines without the dongle - the rule simply never
# matches - so it's written unconditionally, ready for the next time one is
# plugged in. Takes effect on the next WirePlumber start; the best-effort
# restart below applies it immediately if a user session is already running.
log "Writing WirePlumber rule to pin the Jabra Link 380 to its analog profile..."
mkdir -p "$CONF/wireplumber/wireplumber.conf.d"
cat > "$CONF/wireplumber/wireplumber.conf.d/51-jabra-analog.conf" <<'EOF'
monitor.alsa.rules = [
  {
    matches = [
      {
        device.name = "~alsa_card.usb.*Jabra_Link_380.*"
      }
    ]
    actions = {
      update-props = {
        device.profile = "output:analog-stereo+input:mono-fallback"
        api.acp.auto-profile = false
      }
    }
  }
]
EOF
if systemctl --user is-active --quiet wireplumber 2>/dev/null; then
  systemctl --user restart wireplumber 2>/dev/null \
    && log "WirePlumber restarted - Jabra rule active in this session." \
    || warn "Could not restart WirePlumber now - the rule applies on next login."
else
  log "WirePlumber not running in this session - the Jabra rule applies on next login."
fi

# ----------------------------------------------------------------------------
# 14c. CLIamp (terminal music player) - Mod+m
# ----------------------------------------------------------------------------
# Not packaged for Fedora - vendor curl|sh installer fetches a prebuilt
# release binary (no Go/build deps needed) into ~/.local/bin, same shape as
# the Claude Code installer pattern used elsewhere. Best-effort like
# snixembed/the Nerd Font above - a failed install just logs a warning.
if ! command -v cliamp >/dev/null 2>&1; then
  log "Installing CLIamp (terminal music player)..."
  if curl -fsSL https://cliamp.stream/install.sh | sh >/dev/null 2>&1 \
      && command -v cliamp >/dev/null 2>&1; then
    log "CLIamp installed ($(command -v cliamp)) - launch with Mod+m."
  else
    warn "CLIamp install failed (network issue) - install manually from https://www.cliamp.stream/ if you want it."
  fi
else
  log "CLIamp already installed, skipping."
fi

# ----------------------------------------------------------------------------
# 14d. Strata (GTK4 file manager) - github.com/lgse/strata
# ----------------------------------------------------------------------------
# Not packaged for Fedora - the upstream release ships a generic glibc
# tarball (built on Arch, but there is nothing Arch-specific in it: one
# static-ish binary + desktop metadata). glibc >= 2.39 and GTK >= 4.12
# are required - both satisfied by Fedora 44 and OpenMandriva Rolling.
# Strata is made the DEFAULT file manager: the inode/directory handler
# (per-user mimeapps.list via xdg-mime) and the org.freedesktop.FileManager1
# D-Bus service that backs "Open file location" - the per-user services
# dir shadows the system one (nautilus's here), and the service file is
# renamed to the bus name because D-Bus activation looks up <bus-name>.
# .service. Verified live: xdg-open launches Strata. Strata's own in-app
# updater (Settings -> Updates) can upgrade the binary later.
if command -v strata >/dev/null 2>&1; then
  log "Strata already installed, skipping."
else
  log "Installing Strata (GTK4 file manager)..."
  # runtime deps per the upstream README (package names verified against
  # the Fedora 44 repos); failures are non-fatal - the bar keeps pcmanfm.
  sudo dnf install -y \
    gtk4 gtksourceview5 poppler-glib bubblewrap gvfs \
    gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugin-libav \
    ffmpeg ffmpegthumbnailer LibRaw \
    >/dev/null 2>&1 || warn "Strata runtime deps reported errors - continuing anyway."
  __strata_ver="1.0.0"
  case "$(uname -m)" in
    x86_64)  __strata_target="x86_64-unknown-linux-gnu" ;;
    aarch64) __strata_target="aarch64-unknown-linux-gnu" ;;
    *) __strata_target="" ;;
  esac
  __strata_ok=""
  if [ -n "$__strata_target" ]; then
    __strata_dir="$(mktemp -d)"
    __strata_base="https://github.com/lgse/strata/releases/download/v${__strata_ver}/strata-${__strata_ver}-${__strata_target}"
    if curl -fsSL --max-time 300 -o "$__strata_dir/strata.tar.gz" "${__strata_base}.tar.gz" >/dev/null 2>&1 \
       && curl -fsSL --max-time 60 -o "$__strata_dir/strata.tar.gz.sha256" "${__strata_base}.tar.gz.sha256" >/dev/null 2>&1 \
       && sed "s/strata-${__strata_ver}-${__strata_target}\.tar\.gz/strata.tar.gz/" "$__strata_dir/strata.tar.gz.sha256" \
            | (cd "$__strata_dir" && sha256sum --check - >/dev/null 2>&1) \
       && tar -xzf "$__strata_dir/strata.tar.gz" -C "$__strata_dir"; then
      __strata_src="$__strata_dir/strata-${__strata_ver}-${__strata_target}"
      mkdir -p "$HOME/.local/bin" \
        "$HOME/.local/share/applications" \
        "$HOME/.local/share/icons/hicolor/scalable/apps"
      install -Dm755 "$__strata_src/strata" "$HOME/.local/bin/strata"
      sed "s|^Exec=.*|Exec=$HOME/.local/bin/strata %U|" \
        "$__strata_src/io.github.lgse.Strata.desktop" \
        > "$HOME/.local/share/applications/io.github.lgse.Strata.desktop"
      install -Dm644 "$__strata_src/io.github.lgse.Strata.svg" \
        "$HOME/.local/share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg"
      update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
      gtk-update-icon-cache -qtf "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
      if command -v strata >/dev/null 2>&1; then
        log "Strata installed ($(command -v strata)) - launch from the app menu."
        __strata_ok=1
      fi
    fi
    rm -rf "$__strata_dir"
  fi
  [ -n "$__strata_ok" ] || warn "Strata install failed (network issue or checksum mismatch) - install manually from https://github.com/lgse/strata/releases if you want it."
fi

# Make Strata the default file manager. Idempotent and run even when the
# binary was already present (covers installs from an earlier run of this
# section that predate the default switch). The service file is written
# directly rather than copied from the tarball (which is already cleaned
# up here): D-Bus activation requires it named after the bus name.
if command -v strata >/dev/null 2>&1; then
  xdg-mime default io.github.lgse.Strata.desktop inode/directory
  xdg-mime default io.github.lgse.Strata.desktop inode/mount-point
  mkdir -p "$HOME/.local/share/dbus-1/services"
  cat > "$HOME/.local/share/dbus-1/services/org.freedesktop.FileManager1.service" <<STRATA_DBUS_EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=$HOME/.local/bin/strata --gapplication-service
STRATA_DBUS_EOF
  log "Strata is now the default file manager (inode/directory + org.freedesktop.FileManager1)."
fi

# ----------------------------------------------------------------------------
# 15. GTK / Neovim / VS Code themes matching every installed bar theme
# ----------------------------------------------------------------------------
# The HANCORE themes (and any of the old collection the user kept) are
# fed to the repo's own generate-gtk/nvim/vscode-themes.py as [colors]
# blocks in ~/.config/polybar/themes/<name>.ini - the same input format
# the old rice's own themes used - via rice-gen-driver.py, which patches
# the generators' hardcoded THEMES list to every installed theme before
# running them. Best-effort, like the old section: a missing repo dir
# only warns.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RICEGEN_TMP="$(mktemp -d)"
cat > "$RICEGEN_TMP/rice-gen-driver.py" <<'RICEGENEOF'
#!/usr/bin/env python3
"""Drive the repo's generate-gtk/nvim/vscode-themes.py for EVERY theme
currently installed in ~/.config/polybar/themes - the HANCORE themes'
[colors] blocks written by hancore-theme-gen.py, plus any of the rice's
own themes the user kept (they live in the same place, same format) -
instead of those generators' hardcoded THEMES lists.

Light themes (base color luminance > 0.5, none of the HANCORE set is
light today but the check is cheap) are collected the way the generators
expect LIGHT_THEMES.

Usage: rice-gen-driver.py <repo-dir-containing-the-generators>
"""
import configparser
import glob
import importlib.util
import os
import sys

repo = sys.argv[1]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def luminance(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def main():
    themes_dir = os.path.expanduser("~/.config/polybar/themes")
    names = sorted(os.path.basename(p)[:-4]
                   for p in glob.glob(os.path.join(themes_dir, "*.ini")))
    if not names:
        print("rice-gen-driver: no themes in %s, nothing to do" % themes_dir)
        return 0

    light = set()
    for n in names:
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(os.path.join(themes_dir, "%s.ini" % n))
        if parser.has_section("colors") and luminance(parser["colors"]["base"]) > 0.5:
            light.add(n)
    print("rice-gen-driver: %d themes (%d light)" % (len(names), len(light)))

    for gen in ("generate-vscode-themes.py", "generate-gtk-themes.py",
                "generate-nvim-themes.py"):
        path = os.path.join(repo, gen)
        if not os.path.isfile(path):
            print("rice-gen-driver: %s not found, skipping" % gen)
            continue
        mod = load(path, gen.replace("-", "_"))
        mod.THEMES = names
        if hasattr(mod, "LIGHT_THEMES"):
            mod.LIGHT_THEMES = light
        if hasattr(mod, "_vscode_gen"):
            # generate-gtk/nvim re-exec generate-vscode-themes.py as their
            # shared color-resolution module - patch that copy too, since
            # the GTK generator reads LIGHT_THEMES from it at call time.
            mod._vscode_gen.THEMES = names
            mod._vscode_gen.LIGHT_THEMES = light
        print("=== %s" % gen)
        mod.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
RICEGENEOF
if python3 -I "$RICEGEN_TMP/rice-gen-driver.py" "$REPO_DIR" >/dev/null; then
  log "Matching GTK (Rice-*), Neovim (rice-*) and VS Code themes generated."
else
  warn "GTK/Neovim/VS Code theme generation failed (repo dir: $REPO_DIR) - run it by hand: python3 sway-build/rice-gen-driver.py \"$REPO_DIR\""
fi
rm -rf "$RICEGEN_TMP"

log "Done."
cat <<'EOF'

────────────────────────────────────────────────────────────
 Next steps
────────────────────────────────────────────────────────────
 1. Log out.
 2. At the GDM login screen, click the gear icon next to the
    password field and select "Sway" (a native Wayland session —
    the sway package registers it automatically).
 3. First login will look mostly bare until waybar spawns (a couple
    seconds). If it doesn't appear, run
        ~/.local/bin/waybar-launch.sh
    from a kitty terminal (Mod+Return) to see errors directly.
 4. Brightness keys need the 'video' group membership added above -
    log out/in (or reboot) once for that to take effect.
 5. Multi-monitor: plug in your monitor(s), run `arandr` to drag them
    into the arrangement you want, then `autorandr --save mylayout` to
    save it. autorandr auto-detects and re-applies saved layouts on
    hotplug from then on, and its postswitch hook re-launches waybar
    and re-restores the wallpaper. By default sway leaves
    workspaces wherever they were first created, which feels like a
    separate desktop per monitor - edit the `workspace <n> output <name>`
    block near the top of the "workspaces" section in ~/.config/sway/config
    (commented out) to pin workspace ranges to specific outputs instead.
 6. udiskie (USB automount), gammastep (night light), and snixembed (SNI
    tray icon proxy - lets apps like 1Password/Discord/OBS show a tray
    icon at all) all start silently in the background - no keybinding
    needed. gammastep needs a location to compute sunrise/sunset; it uses
    geoclue2 automatically if available, otherwise edit
    ~/.config/gammastep/config.ini to set a fixed lat/lon (see
    `man gammastep`).
 7. Press Mod+shift+w to pick a real wallpaper - a solid dark
    placeholder is set initially so login isn't blank.
 8. Desktop theming comes from the HANCORE waybar collection - pick a
    theme with the app menu (Mod+alt+space -> Desktop Theme) or
    `waybar-theme.sh <name>`; one pick retints waybar, rofi, kitty,
    dunst, starship, sway borders, GTK, Neovim and VS Code together.

 Cheat sheet (Mod = Super/Windows key):
   Mod+Return        open kitty
   Mod+space         app launcher (rofi)
   Mod+e             file manager (Strata)
   Mod+shift+w       wallpaper picker (azote)
   Mod+l             lock screen
   Mod+shift+p       power menu (lock/suspend/logout/reboot/shutdown)
   Mod+shift+v       clipboard history (copyq)
   Print             screenshot (slurp region select + grim, swappy annotate)
   Mod+shift+g       colorpicker (click a pixel, hex copied to clipboard)
   Mod+shift+q       close focused window
   Mod+f             fullscreen toggle
   Mod+shift+f       floating toggle
   Mod+1..9          switch workspace
   Mod+shift+1..9    move window to workspace
   Mod+h/j/k/l-ish   focus (h/j/k/; — see config)
   Mod+ctrl+h/l      focus next/prev monitor
   Mod+ctrl+shift+h/l move workspace to next/prev monitor
   Mod+shift+r       reload Sway (same as Mod+shift+c)
   Mod+shift+e       exit Sway (with confirm)
   XF86 media/volume/brightness keys all bound - see config for specifics.

 Waybar widgets are clickable where it makes sense:
   left/right-click the network, bluetooth, battery, clock or tray
   widgets - see each theme's own config.jsonc for specifics.

 Run `fastfetch` in a terminal for the obligatory rice screenshot.
────────────────────────────────────────────────────────────
EOF
