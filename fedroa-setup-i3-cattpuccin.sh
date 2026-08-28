#!/usr/bin/env bash
# ============================================================================
# i3 "hackerbox" post-install script — Fedora 44
# Theme: Catppuccin Mocha | Layout: gapped + picom blur/shadows
#
# Installs: i3, picom, polybar, rofi, dunst, kitty, i3lock-color (COPR, with a
#           stock i3lock fallback), xss-lock, lxqt-policykit, flameshot,
#           ImageMagick, brightnessctl, playerctl, numlockx, dex-autostart, autorandr,
#           arandr, fastfetch, Nerd Font, tray helpers, GTK/icon theme, rofi
#           power menu, copyq clipboard history, udiskie USB automount, pcmanfm
#           file manager, gammastep night light, volume/brightness OSD popups,
#           snixembed (built from source - proxies modern StatusNotifierItem
#           tray icons into the legacy protocol polybar's tray understands),
#           nitrogen wallpaper picker, Catppuccin GTK3/4 theme, per-monitor
#           polybar (powerline-style Catppuccin theme with a native bluetooth
#           widget, primary/secondary split so only one instance claims the
#           systray) + always-visible window borders and tightened gaps.
# Idempotent-ish: safe to re-run, but back up existing configs first if you
# have your own dotfiles — this OVERWRITES the files listed below.
# ============================================================================
set -euo pipefail

log()  { echo -e "\e[1;35m[i3-setup]\e[0m $*"; }
warn() { echo -e "\e[1;33m[i3-setup]\e[0m $*"; }

if ! command -v dnf >/dev/null 2>&1; then
  echo "This script targets Fedora (dnf not found). Aborting." >&2
  exit 1
fi

CONF="$HOME/.config"
BIN="$HOME/.local/bin"
FONTS="$HOME/.local/share/fonts"
mkdir -p "$CONF" "$BIN" "$FONTS"

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
      --description "before fedroa-setup-i3-cattpuccin.sh" 2>/dev/null)"; then
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
log "Installing base X11 stack + i3 + rice toolkit via dnf..."
sudo dnf install -y \
  xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-xauth xrandr xset \
  i3 i3lock \
  picom polybar rofi dunst kitty \
  xss-lock network-manager-applet pasystray blueman lxqt-policykit pipewire-pulseaudio \
  copyq udiskie pcmanfm gammastep libnotify nitrogen gnome-calendar \
  system-config-printer hplip \
  vala gtk3-devel libdbusmenu-devel libdbusmenu-gtk3-devel \
  lxappearance papirus-icon-theme \
  fastfetch git curl unzip jq flameshot ImageMagick \
  brightnessctl playerctl numlockx dex-autostart autorandr arandr xdotool \
  solaar solaar-udev \
  pipx \
  jetbrains-mono-fonts

# network-manager-applet/pasystray/blueman/udiskie are still installed above -
# their tray-icon *applets* (nm-applet, pasystray, blueman-applet) are
# deliberately never autostarted (see the i3 config below); polybar's own
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

log "Enabling COPR for i3lock-color (not in official Fedora repos)..."
sudo dnf copr enable -y tokariew/i3lock-color || warn "COPR enable failed — you can install i3lock-color manually later."
# The tokariew build installs itself AS /usr/bin/i3lock (same binary name,
# extended flags - there's no separate "i3lock-color" command), which
# conflicts file-for-file with the stock i3lock already installed above -
# `dnf install` alone fails the whole transaction over that conflict.
# `dnf swap` removes the old package and installs the new one as one atomic
# transaction, which is exactly the fix for this class of same-file conflict.
sudo dnf swap -y i3lock i3lock-color || warn "i3lock-color install failed; falling back to stock i3lock for now."

# ----------------------------------------------------------------------------
# 2. Nerd Font (JetBrainsMono) — official Fedora repos don't ship patched fonts
# ----------------------------------------------------------------------------
if [ ! -d "$FONTS/JetBrainsMonoNerd" ]; then
  log "Downloading JetBrainsMono Nerd Font..."
  TMPZIP="$(mktemp --suffix=.zip)"
  # Best-effort: under set -e, an unguarded curl failure here (flaky network,
  # GitHub rate limit, renamed release asset) would abort the WHOLE script
  # before any i3/picom/polybar/rofi/dunst/kitty config below ever gets
  # written - the font is cosmetic, it shouldn't be able to take those down.
  if curl -fLo "$TMPZIP" \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" 2>/dev/null; then
    mkdir -p "$FONTS/JetBrainsMonoNerd"
    unzip -o "$TMPZIP" -d "$FONTS/JetBrainsMonoNerd" >/dev/null
    fc-cache -f "$FONTS/JetBrainsMonoNerd"
  else
    warn "Nerd Font download failed (network issue?) - configs below still reference 'JetBrainsMono Nerd Font'; install it manually later or edit the font name in ~/.config/{i3,polybar,rofi,kitty}."
  fi
  rm -f "$TMPZIP"
else
  log "JetBrainsMono Nerd Font already present, skipping download."
fi

# ----------------------------------------------------------------------------
# 3. Catppuccin Mocha palette (used across every config below)
# ----------------------------------------------------------------------------
# base=#1e1e2e mantle=#181825 crust=#11111b text=#cdd6f4 subtext0=#a6adc8
# surface0=#313244 surface1=#45475a surface2=#585b70 overlay0=#6c7086
# blue=#89b4fa lavender=#b4befe sapphire=#74c7ec sky=#89dceb teal=#94e2d5
# green=#a6e3a1 yellow=#f9e2af peach=#fab387 maroon=#eba0ac red=#f38ba8
# mauve=#cba6f7 pink=#f5c2e7 flamingo=#f2cdcd rosewater=#f5e0dc

# ----------------------------------------------------------------------------
# 4. i3 config
# ----------------------------------------------------------------------------
log "Writing i3 config..."
mkdir -p "$CONF/i3"
cat > "$CONF/i3/config" <<'EOF'
set $mod Mod4
font pango:JetBrainsMono Nerd Font 10

# gaps (merged upstream i3-gaps)
gaps inner 8
gaps outer 2
# smart_gaps/smart_borders have no explicit "off" token in i3's config
# grammar - omitting the directive entirely is how you disable it. Both
# defaulted to hiding things (outer gaps, and the border) specifically when
# gaps/multiple-windows made them seem redundant - which made a single-
# window workspace inconsistent with a multi-window one (no gap, no border)
# instead of always looking the same. With both omitted, gaps and the 2px
# border always render.
default_border pixel 2
default_floating_border pixel 2
# "smart" hides border edges that touch the screen boundary - with only one
# window on a workspace, all four of its edges qualify, hiding the whole
# bezel. "none" keeps every edge visible regardless of window count.
hide_edge_borders none

# Catppuccin Mocha border colors
# class                 border   bground  text     indicator child_border
client.focused          #cba6f7  #1e1e2e  #cdd6f4  #cba6f7   #cba6f7
client.unfocused        #313244  #1e1e2e  #6c7086  #313244   #313244
client.focused_inactive #45475a  #1e1e2e  #a6adc8  #45475a   #45475a
client.urgent           #f38ba8  #1e1e2e  #f38ba8  #f38ba8   #f38ba8

floating_modifier $mod

# --- window rules ---
# Settings-style dialogs launched from the polybar network/bluetooth widgets,
# copyq's clipboard menu, and Evolution's calendar/task reminder popup - float
# + center + shrink instead of tiling full-height like a regular window.
for_window [class="^Nm-connection-editor$"] floating enable, resize set 550 450, move position center
for_window [class="^Blueman-manager$"] floating enable, resize set 500 400, move position center
for_window [class="^copyq$"] floating enable, resize set 450 500, move position center
for_window [class="^Evolution-alarm-notify$"] floating enable, resize set 450 350, move position center
for_window [class="^gnome-calendar$"] floating enable, resize set 700 550, move position center
for_window [class="^System-config-printer\.py$"] floating enable, resize set 750 550, move position center
for_window [class="^Screensaver$"] fullscreen enable

# --- launch ---
bindsym $mod+Return exec kitty
bindsym $mod+d exec rofi -show drun -theme ~/.config/rofi/catppuccin-mocha.rasi
bindsym $mod+shift+d exec rofi -show run -theme ~/.config/rofi/catppuccin-mocha.rasi
bindsym $mod+e exec pcmanfm
bindsym $mod+shift+w exec nitrogen
bindsym $mod+p exec system-config-printer
bindsym $mod+c exec --no-startup-id ~/.local/bin/caffeine-toggle.sh
bindsym $mod+n exec --no-startup-id ~/.local/bin/dnd-toggle.sh
bindsym $mod+Escape exec --no-startup-id kitty --class Screensaver -e ~/.local/bin/screensaver.sh
bindsym $mod+shift+q kill
bindsym $mod+shift+c reload
bindsym $mod+shift+r restart
bindsym $mod+shift+e exec i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'

# --- lock / screenshot / power ---
bindsym $mod+l exec --no-startup-id ~/.local/bin/lock.sh --with-screensaver
bindsym $mod+shift+p exec --no-startup-id ~/.local/bin/powermenu.sh
bindsym Print exec --no-startup-id "flameshot gui || import /tmp/shot-$(date +%s).png"

# --- clipboard history (copyq) ---
bindsym $mod+shift+v exec --no-startup-id copyq toggle

# --- volume / brightness / media (adjust key names if your kernel maps differ) ---
# osd-*.sh wrap pactl/brightnessctl and pop a dunst progress-bar notification
# showing the resulting level - plain pactl/brightnessctl give zero visual
# feedback on their own.
bindsym XF86AudioRaiseVolume exec --no-startup-id ~/.local/bin/osd-volume.sh up
bindsym XF86AudioLowerVolume exec --no-startup-id ~/.local/bin/osd-volume.sh down
bindsym XF86AudioMute exec --no-startup-id ~/.local/bin/osd-volume.sh mute
bindsym XF86MonBrightnessUp exec --no-startup-id ~/.local/bin/osd-brightness.sh up
bindsym XF86MonBrightnessDown exec --no-startup-id ~/.local/bin/osd-brightness.sh down
bindsym XF86AudioPlay exec --no-startup-id playerctl play-pause
bindsym XF86AudioNext exec --no-startup-id playerctl next
bindsym XF86AudioPrev exec --no-startup-id playerctl previous

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

bindsym $mod+f fullscreen toggle
bindsym $mod+shift+space floating toggle
bindsym $mod+space focus mode_toggle

# --- workspaces ---
# By default i3 assigns each workspace to whichever output it was FIRST
# created on and leaves it there - with no assignment at all, that makes a
# multi-monitor setup feel like unrelated desktops per screen instead of one
# layout, since switching workspace only ever changes what the CURRENTLY
# FOCUSED output shows. Pin workspaces to specific outputs for predictable
# placement across reboots/output reorder - uncomment and edit the output
# names below to match `xrandr --query` (or `polybar --list-monitors`) on
# your hardware, e.g. for a 3-monitor setup:
#   workspace 1 output eDP-1
#   workspace 2 output eDP-1
#   workspace 3 output eDP-1
#   workspace 4 output HDMI-1
#   workspace 5 output HDMI-1
#   workspace 6 output HDMI-1
#   workspace 7 output DP-1
#   workspace 8 output DP-1
#   workspace 9 output DP-1
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
# exec_always re-runs on every reload ($mod+shift+c) and restart ($mod+shift+r) -
# kill any previous instance first so picom doesn't pile up duplicates. The
# short sleep gives the old process time to actually exit and release the X
# compositor selection before the new one tries to grab it.
exec_always --no-startup-id "pkill -x picom; sleep 0.5; picom --config ~/.config/picom/picom.conf"
# polybar-launch.sh handles its own kill-before-relaunch AND launches one bar
# per connected output - see the script for why this can't just be inlined here.
exec_always --no-startup-id ~/.local/bin/polybar-launch.sh
# snixembed proxies StatusNotifierItem (SNI) tray icons - used by most modern
# apps (1Password, Discord, OBS, etc.) - into the legacy XEmbed protocol that
# polybar's tray module actually understands. --fork blocks until it's ready
# on the session bus, then forks, so SNI apps starting right after it detect
# it instead of racing it and silently skipping their tray icon. Must start
# before any SNI-only app, hence first in this list.
exec --no-startup-id snixembed --fork
# nm-applet/pasystray/blueman-applet are NOT started here on purpose - their
# tray icons would duplicate polybar's own wifi/volume/bluetooth widgets.
# Network Manager/PulseAudio/bluetoothd all keep working fine without their
# applets running; only the redundant tray icon goes away. Their
# /etc/xdg/autostart entries are overridden with Hidden=true in
# ~/.config/autostart/ (section 6d below) so dex-autostart further down
# doesn't bring them back either.
#
# blueman-manager (opened by clicking the polybar bluetooth widget) itself
# auto-spawns blueman-applet as its backend with no way to opt out - the
# guard script kills it right back every few seconds so it can't linger.
exec --no-startup-id ~/.local/bin/blueman-applet-guard.sh
exec --no-startup-id /usr/libexec/lxqt-policykit-agent
exec --no-startup-id copyq
exec --no-startup-id udiskie --tray
exec --no-startup-id gammastep
exec --no-startup-id nitrogen --restore
exec --no-startup-id dunst
exec --no-startup-id numlockx on
# Runs any other installed app's ~/.config/autostart .desktop entries (tray
# apps, sync clients, etc.) - bare i3 has no XDG autostart support of its own.
# (Fedora packages upstream's "dex" as "dex-autostart" - same tool/flags,
# renamed to avoid a name collision with an unrelated Fedora package.)
exec --no-startup-id dex-autostart -a -e i3
# MX Anywhere 3S needs its Scroll Wheel Resolution HID++ feature toggled
# off-then-on after every reconnect (reboot, sleep/wake) for scrolling to
# work properly - see ~/.local/bin/fix-mx-scroll.sh for why a plain "set to
# true" isn't enough. Silently a no-op on any other hardware (the device
# just never shows up in `solaar show`, so the retry loop times out and
# exits quietly) - hardcoded to this specific, confirmed mouse rather than
# gated behind generic detection, matching the same fix already offered as
# a manual Peripherals menu action in post-install-fedora.sh.
exec --no-startup-id ~/.local/bin/fix-mx-scroll.sh
exec --no-startup-id xss-lock --transfer-sleep-lock -- ~/.local/bin/lock.sh --with-screensaver
# Idle-based lock: screensaver activation at 30min (triggers xss-lock ->
# lock.sh --with-screensaver, which force-blanks the display immediately on
# lock regardless of these DPMS timers - see lock_and_blank() in lock.sh).
# DPMS standby/suspend/off at 30/60/90min are mostly a fallback for that.
exec --no-startup-id xset s 1800 dpms 1800 3600 5400

bar {
    mode invisible
}
EOF

# ----------------------------------------------------------------------------
# 5. picom
# ----------------------------------------------------------------------------
log "Writing picom config..."
mkdir -p "$CONF/picom"
cat > "$CONF/picom/picom.conf" <<'EOF'
backend = "glx";        # glx suits Mesa (Intel/AMD); on NVIDIA's proprietary
                         # driver, switch this to "xrender" if you see tearing/flicker
vsync = true;

shadow = true;
shadow-radius = 18;
shadow-opacity = 0.55;
shadow-color = "#11111b";
shadow-exclude = [
  "class_g = 'polybar'",
  "class_g = 'i3-frame'"
];

fading = true;
fade-in-step = 0.05;
fade-out-step = 0.05;
# The screensaver kitty window and i3lock (an override-redirect window with
# no conventional WM_CLASS at all - confirmed from its own source, so this
# is the only way to target it specifically) fading in/out on the
# screensaver->lock transition is what looked like "flicker"/"going black":
# the screensaver fades OUT revealing the real desktop underneath mid-fade,
# then i3lock fades IN from fully transparent (briefly looking like a black
# screen) rather than either just appearing/disappearing instantly.
fade-exclude = [
  "class_g = 'Screensaver'",
  "override_redirect = true"
];

corner-radius = 10;
rounded-corners-exclude = [
  "class_g = 'polybar'"
];

blur: {
  method = "dual_kawase";
  strength = 6;
}
blur-background-exclude = [
  "class_g = 'polybar'"
];

active-opacity = 1.0;
inactive-opacity = 0.92;
opacity-rule = [
  "92:class_g = 'kitty' && focused",
  "80:class_g = 'kitty' && !focused"
];

mark-wmwin-focused = true;
mark-ovredir-focused = true;
detect-rounded-corners = true;
detect-client-opacity = true;
use-damage = true;
EOF

# ----------------------------------------------------------------------------
# 6. polybar
# ----------------------------------------------------------------------------
# Battery (laptop) and backlight detection - baked into the config below via
# placeholder substitution so desktops without one still get a valid config
# (an unreferenced module is loaded lazily and silently ignored by polybar).
BATTERY_NAME="$(ls /sys/class/power_supply 2>/dev/null | grep -m1 -E '^BAT')"
AC_NAME="$(ls /sys/class/power_supply 2>/dev/null | grep -m1 -E '^(AC|ADP)')"
BACKLIGHT_CARD="$(ls /sys/class/backlight 2>/dev/null | head -1)"

log "Writing polybar config (powerline-style, Catppuccin Mocha)..."
mkdir -p "$CONF/polybar"
cat > "$CONF/polybar/config.ini" <<'EOF'
[colors]
base     = #1e1e2e
mantle   = #181825
surface0 = #313244
surface1 = #45475a
text     = #cdd6f4
subtext  = #a6adc8
mauve    = #cba6f7
lavender = #b4befe
blue     = #89b4fa
sky      = #89dceb
green    = #a6e3a1
teal     = #94e2d5
yellow   = #f9e2af
peach    = #fab387
red      = #f38ba8

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 8
padding-left = 1
padding-right = 0
module-margin = 0
; font-1 is a slightly larger slot for the powerline separator glyphs so the
; rounded caps render full-height instead of looking clipped/short next to
; the regular text baseline. font-2 is the plain, unpatched JetBrains Mono -
; some Nerd Font patched builds have broken/asymmetric advance widths on
; ordinary glyphs (polybar#484, referencing nerd-fonts#991), which throws off
; centering on digit-only labels; this sidesteps it for the modules that use it.
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
underline-size = 2
overline-size = 2
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
; the only instance that actually owns the X11 systray (single-owner across
; every polybar instance, regardless of which bar config asks for it) - also
; the only one carrying the battery widget. polybar-launch.sh launches this
; bar name on whichever output xrandr reports as primary. Clock is the very
; last segment, farthest right; the tray sits at the very left of the right-
; hand group, bookended by a thin mauve "cap" so it reads as a closed
; container instead of trailing off.
modules-right = sep-base-mauve-cap tray-cap sep-mauve-cap-surface0 tray sep-surface0-sky @@SKY_WIDGET@@ sep-sky-mauve pulseaudio sep-mauve-blue network-wired network-wireless sep-blue-teal bluetooth @@PRIMARY_MID@@ memory sep-yellow-green cpu sep-green-lavender date-icon date

[bar/top-secondary]
inherit = bar/base
; same as top-primary minus tray/battery/bluetooth - without this split every
; extra monitor showed a permanently empty tray slot since only one instance
; can ever win the X11 tray selection, and a second bluetooth radio reading
; would just be a duplicate of the primary bar's.
modules-right = sep-base-sky @@SKY_WIDGET@@ sep-sky-mauve pulseaudio sep-mauve-blue network-wired network-wireless sep-blue-yellow memory sep-yellow-green cpu sep-green-lavender date-icon date

; --- powerline separators ---------------------------------------------------
; Each is a plain glyph rendered in the color of the segment being LEFT
; (label-foreground) over the background of the segment being ENTERED
; (label-background) - that's what makes the rounded cap look like it
; belongs to both neighbours and reads as one continuous capsule chain. All
; of them point the same direction because the whole chain flows left to
; right; only the fg/bg pair changes per transition. The placeholder tokens
; below get substituted with the actual Nerd Font glyphs after this heredoc
; (search this script for SEP=$'\uXXXX') because literal Private-Use-Area
; characters don't survive being embedded directly in script-authoring
; tools - injecting them via bash's ANSI-C quoting is the reliable path.
;
; sep-base-mauve-cap/tray-cap/sep-mauve-cap-surface0 also carry a mauve
; label-underline/overline so the tray's own frame lines (below) continue
; unbroken through the cap instead of stopping right at its own boundary.
[module/sep-base-mauve-cap]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.mauve}
label-underline = ${colors.mauve}
label-overline = ${colors.mauve}

[module/tray-cap]
type = custom/text
format = <label>
label = "  "
label-background = ${colors.mauve}
label-underline = ${colors.mauve}
label-overline = ${colors.mauve}

[module/sep-mauve-cap-surface0]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.mauve}
label-background = ${colors.surface0}
label-underline = ${colors.mauve}
label-overline = ${colors.mauve}

[module/sep-surface0-sky]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.sky}
label-underline = ${colors.mauve}
label-overline = ${colors.mauve}

[module/sep-base-sky]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.sky}

[module/sep-sky-mauve]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.sky}
label-background = ${colors.mauve}

[module/sep-mauve-blue]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.mauve}
label-background = ${colors.blue}

[module/sep-blue-teal]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.blue}
label-background = ${colors.teal}

[module/sep-teal-peach]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.teal}
label-background = ${colors.peach}

[module/sep-teal-green]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.teal}
label-background = ${colors.green}

[module/sep-green-peach]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.peach}

[module/sep-green-yellow]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.yellow}

[module/sep-green-red]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.red}

[module/sep-red-peach]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.red}
label-background = ${colors.peach}

[module/sep-red-yellow]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.red}
label-background = ${colors.yellow}

[module/sep-teal-yellow]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.teal}
label-background = ${colors.yellow}

[module/sep-peach-yellow]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.peach}
label-background = ${colors.yellow}

[module/sep-blue-yellow]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.blue}
label-background = ${colors.yellow}

[module/sep-yellow-green]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.yellow}
label-background = ${colors.green}

[module/sep-green-lavender]
type = custom/text
format = <label>
label = "@@SEP@@"
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.lavender}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
; The real centering culprit on workspace numbers: label-focused/unfocused/
; urgent default to "%icon% %name%" - since no ws-icon-N is configured,
; %icon% renders empty but the literal space between it and %name% is still
; there, permanently skewing the visible digit right of center. ws-label
; pins content to just the index, removing that invisible leading space.
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-urgent = ${self.ws-label}
; font-2 (index 3, see bar/base) is the plain, unpatched font - a further
; safety margin against the Nerd Font glyph-metrics quirk above. No fill/
; background here either - polybar has no way to draw a rounded rectangle
; around dynamic per-item text, so a filled box always renders as a hard
; square; underline+overline avoids that entirely instead of trying to
; soften it.
label-focused-font = 3
label-focused-foreground = ${colors.mauve}
label-focused-underline = ${colors.mauve}
label-focused-overline = ${colors.mauve}
label-focused-padding = 3
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.red}
label-urgent-underline = ${colors.red}
label-urgent-overline = ${colors.red}
label-urgent-padding = 2

; Split into its own module (icon on the normal-size font) from the date
; module (text on the plain font) rather than mixing both fonts in one
; label - polybar's per-glyph font fallback can pick the WRONG font-N for a
; glyph missing from the label's primary font, rendering it clipped/broken.
[module/date-icon]
type = custom/text
format = <label>
label = "%{A1:gnome-calendar &:}  @@ICO_CLOCK@@ %{A}"
label-font = 1
label-foreground = ${colors.base}
format-background = ${colors.lavender}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:gnome-calendar &:}  %date%  %time%  %{A}"
label-font = 3
label-foreground = ${colors.base}
format-background = ${colors.lavender}

; Only referenced in modules-right (as @@SKY_WIDGET@@) when no backlight
; device was found - see @@SKY_WIDGET@@ substitution below.
[module/xkeyboard]
type = internal/xkeyboard
blacklist-0 = num lock
label-layout = "  @@ICO_KB@@ %layout% "
label-layout-foreground = ${colors.base}
format-background = ${colors.sky}

[module/backlight]
type = internal/backlight
card = @@BACKLIGHT_CARD@@
enable-scroll = true
format = <label>
label = "  @@ICO_BACKLIGHT@@ %percentage%% "
label-foreground = ${colors.base}
format-background = ${colors.sky}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "  @@ICO_VOL@@ %percentage%% "
label-muted = "  @@ICO_MUTE@@ muted "
label-volume-foreground = ${colors.base}
label-muted-foreground = ${colors.base}
format-volume-background = ${colors.mauve}
format-muted-background = ${colors.mauve}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label. They
; share one segment color/slot since at most one of them is ever visible.
; click-left/click-right as plain config keys are silently ignored by
; internal/network (confirmed against polybar/polybar#1617/#273) - the
; actual mechanism is wrapping the label content in inline %{A...} action
; tags instead, which is what's used below.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  @@ICO_WIRED@@ %ifname% %{A}"
label-connected-foreground = ${colors.base}
format-connected-background = ${colors.blue}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}  @@ICO_WIFI@@ %essid% %{A}%{A}"
label-connected-foreground = ${colors.base}
format-connected-background = ${colors.blue}
format-disconnected =

; polybar has no native bluetooth module - this polls bluetoothctl via the
; helper script (section 6b below) instead. click-left DOES work here since
; custom/script honors it directly (unlike internal/network above).
[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.base}
format-background = ${colors.teal}

; "Caffeine" toggle - no packaged equivalent exists for Fedora (checked both
; dnf and Flathub). click-left toggles idle/lock/sleep inhibition (section
; 6c below); click-right forces the screensaver/lock to activate right now.
[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.base}
format-background = ${colors.green}

; Do Not Disturb toggle - pauses/resumes dunst via dunstctl.
[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.base}
format-background = ${colors.red}

[module/battery]
type = internal/battery
battery = @@BATTERY_NAME@@
adapter = @@AC_NAME@@
label-charging = "  @@ICO_BATT@@ %percentage%% "
label-discharging = "  @@ICO_BATT@@ %percentage%% "
label-full = "  @@ICO_BATT@@ Full "
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}
format-charging-background = ${colors.peach}
format-discharging-background = ${colors.peach}
format-full-background = ${colors.peach}

[module/memory]
type = internal/memory
interval = 2
label = "  @@ICO_MEM@@ %percentage_used%% "
label-foreground = ${colors.base}
format-background = ${colors.yellow}

[module/cpu]
type = internal/cpu
interval = 2
label = "  @@ICO_CPU@@ %percentage%% "
label-foreground = ${colors.base}
format-background = ${colors.green}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
; polybar's tray module has no true 4-sided border - format-underline/
; format-overline (top+bottom accent lines) is the closest it can draw to a
; frame, continued unbroken from the cap modules above. format-background is
; ALSO needed (not just tray-background, which per the docs only colors the
; individual icons, not the space around them) for a solid, cohesive pill
; instead of a transparent gap with framed icons.
format-background = ${colors.surface0}
format-underline = ${colors.mauve}
format-overline = ${colors.mauve}

[settings]
screenchange-reload = true
EOF

# Substitute placeholders now that the file is written (kept out of the
# heredoc above since it's single-quoted - polybar's own ${...} references
# would otherwise get mangled by bash expansion, and literal Nerd Font
# Private-Use-Area glyphs don't survive being typed directly into a script
# file). $'\uXXXX'/$'\UXXXXXXXX' is bash's ANSI-C-quoted Unicode escape
# (bash >=4.2); the 8-digit \U form is needed for ICO_BACKLIGHT since that
# glyph sits above U+FFFF, outside \u's 4-digit range.
SEP=$''          # rounded right-pointing powerline cap
ICO_CLOCK=$''
ICO_KB=$''
ICO_VOL=$''
ICO_MUTE=$''
ICO_WIRED=$''
ICO_WIFI=$''
ICO_BATT=$''
ICO_MEM=$''       # nf-fa-hdd_o - the more commonly-cited "memory" glyph
                        # (nf-fa-memory) isn't in every Nerd Font build
ICO_CPU=$''
ICO_BT=$''
ICO_BACKLIGHT=$'󰃟'    # nf-md-brightness_6 (supplementary plane codepoint)
ICO_COFFEE=$''      # nf-fa-coffee
ICO_BELL=$''      # nf-fa-bell
ICO_BELL_OFF=$''  # nf-fa-bell-slash

if [ -n "$BATTERY_NAME" ]; then
  PRIMARY_MID="sep-teal-green caffeine sep-green-red dnd sep-red-peach battery sep-peach-yellow"
else
  warn "No battery detected - skipping the polybar battery widget (desktop machine, or an unusual power_supply naming)."
  PRIMARY_MID="sep-teal-green caffeine sep-green-red dnd sep-red-yellow"
  BATTERY_NAME=BAT0
  AC_NAME=AC
fi

if [ -n "$BACKLIGHT_CARD" ]; then
  SKY_WIDGET="backlight"
else
  warn "No backlight device detected under /sys/class/backlight - showing the keyboard-layout widget in that slot instead (desktop machine, or brightness controlled by the monitor itself)."
  SKY_WIDGET="xkeyboard"
  BACKLIGHT_CARD="intel_backlight"
fi

sed -i \
  -e "s/@@PRIMARY_MID@@/$PRIMARY_MID/" \
  -e "s/@@SKY_WIDGET@@/$SKY_WIDGET/g" \
  -e "s/@@BATTERY_NAME@@/$BATTERY_NAME/" \
  -e "s/@@AC_NAME@@/${AC_NAME:-AC}/" \
  -e "s/@@BACKLIGHT_CARD@@/$BACKLIGHT_CARD/" \
  -e "s/@@SEP@@/$SEP/g" \
  -e "s/@@ICO_CLOCK@@/$ICO_CLOCK/g" \
  -e "s/@@ICO_KB@@/$ICO_KB/g" \
  -e "s/@@ICO_VOL@@/$ICO_VOL/g" \
  -e "s/@@ICO_MUTE@@/$ICO_MUTE/g" \
  -e "s/@@ICO_WIRED@@/$ICO_WIRED/g" \
  -e "s/@@ICO_WIFI@@/$ICO_WIFI/g" \
  -e "s/@@ICO_BATT@@/$ICO_BATT/g" \
  -e "s/@@ICO_MEM@@/$ICO_MEM/g" \
  -e "s/@@ICO_CPU@@/$ICO_CPU/g" \
  -e "s/@@ICO_BACKLIGHT@@/$ICO_BACKLIGHT/g" \
  "$CONF/polybar/config.ini"

# ----------------------------------------------------------------------------
# 6b. Multi-monitor helper script (polybar per output) + autorandr hotplug hook
# ----------------------------------------------------------------------------
log "Writing multi-monitor helper scripts..."
cat > "$BIN/polybar-launch.sh" <<'EOF'
#!/usr/bin/env bash
# One polybar instance per connected output. Whichever output xrandr marks
# primary gets "top-primary" (owns the systray + battery module - the X11
# tray selection can only ever be won by one instance, so every other bar
# uses "top-secondary" instead of showing a permanently empty tray slot).
# Falls back to top-primary alone if --list-monitors comes back empty (e.g.
# a stale X state), or if nothing is marked primary at all.
pkill -x polybar
while pgrep -x polybar >/dev/null; do sleep 0.1; done
# picom restarts via its own separate exec_always line at the same time
# polybar does (on both i3 reload/restart and login) - with no ordering
# between the two, polybar (and its tray, embedding icons from apps that
# are already running) could start compositing before picom's new instance
# is actually up, which showed up as tray icons flashing visible for a
# moment then disappearing once the old compositor state finally caught up
# (or never fully did). Wait up to 5s for picom to exist before launching;
# proceed anyway past that so a picom failure doesn't block the bar
# forever.
for _ in $(seq 1 50); do
  pgrep -x picom >/dev/null && break
  sleep 0.1
done
LIST="$(polybar --list-monitors 2>/dev/null)"
if [ -z "$LIST" ]; then
  polybar -c ~/.config/polybar/config.ini top-primary &
else
  HAS_PRIMARY=$(grep -c '(primary)' <<< "$LIST")
  first=1
  while IFS= read -r line; do
    m="${line%%:*}"
    if [[ "$line" == *"(primary)"* ]] || { [ "$HAS_PRIMARY" -eq 0 ] && [ "$first" -eq 1 ]; }; then
      bar=top-primary
    else
      bar=top-secondary
    fi
    MONITOR="$m" polybar -c ~/.config/polybar/config.ini "$bar" &
    first=0
  done <<< "$LIST"
fi

# snixembed never actually restarts on its own on i3 restart/reload - its
# own --fork helper deliberately exits immediately if a StatusNotifierWatcher
# already exists (to avoid a second instance), and its source has no logic
# at all for detecting that the X11 tray SELECTION changed owners (confirmed
# by reading it - no _NET_SYSTEM_TRAY_S0/MANAGER handling anywhere). So when
# the polybar instance snixembed's icons were embedded in just died above
# and a brand new one claimed the tray, those already-registered icons are
# orphaned with nothing to recover them - this is what actually explained
# the tray coming back empty (or icons flashing then vanishing) after
# Mod+shift+r, not a picom/compositor timing issue as first suspected.
# Force-restarting snixembed here (after the new polybar/tray already
# exists) makes every already-running SNI app notice the watcher's name
# changed owner and re-register + re-embed fresh - confirmed this already
# happens automatically (Slack and CopyQ both re-registered on their own)
# the last time snixembed's binary itself was replaced mid-session.
pkill -x snixembed
while pgrep -x snixembed >/dev/null; do sleep 0.1; done
snixembed --fork &
disown
EOF
chmod +x "$BIN/polybar-launch.sh"

# nitrogen (installed in section 1) handles wallpaper instead of a feh
# script - it natively fills every connected output with `nitrogen
# --restore` on its own, so there's no per-monitor tiling logic to write
# here. See section 12 for the initial wallpaper pick.

# autorandr's postswitch hook fires on every profile change (monitor plugged/
# unplugged/reconfigured) - re-run polybar and re-restore the wallpaper so
# both follow the new output layout instead of staying stuck on the old one.
mkdir -p "$CONF/autorandr"
cat > "$CONF/autorandr/postswitch" <<'EOF'
#!/usr/bin/env bash
~/.local/bin/polybar-launch.sh
nitrogen --restore
EOF
chmod +x "$CONF/autorandr/postswitch"

# ----------------------------------------------------------------------------
# 6c. polybar bluetooth widget + blueman-applet guard
# ----------------------------------------------------------------------------
log "Writing polybar bluetooth helper script..."
cat > "$BIN/polybar-bluetooth.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: prints bluetooth adapter power state.
if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
  STATE="on"
else
  STATE="off"
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
#   1. xset's screensaver/DPMS timers are disabled, so xss-lock never fires
#      (it triggers off X11's screensaver-activation signal) and the display
#      never blanks/suspends.
#   2. A backgrounded `systemd-inhibit` holds idle/sleep/lid-switch locks so
#      systemd-logind won't suspend even on lid close, matching what the
#      screensaver-based inhibition alone wouldn't cover.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
IDLE_RESTORE="300 dpms 300 600 900"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")" 2>/dev/null
  rm -f "$PIDFILE"
  xset s $IDLE_RESTORE
  notify-send -h string:x-dunst-stack-tag:caffeine "Caffeine: off" "Screen lock/sleep restored"
else
  xset s off -dpms
  systemd-inhibit --what=idle:sleep:handle-lid-switch --who="i3-caffeine" \
      --why="User requested via caffeine-toggle.sh" --mode=block \
      sleep infinity &
  disown
  echo "$!" > "$PIDFILE"
  notify-send -h string:x-dunst-stack-tag:caffeine "Caffeine: on" "Screen lock/sleep inhibited until toggled off"
fi
EOF
chmod +x "$BIN/caffeine-toggle.sh"

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

log "Writing Do Not Disturb toggle + polybar widget scripts..."
cat > "$BIN/dnd-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Do Not Disturb toggle for dunst. Notify BEFORE pausing (a notification
# sent after wouldn't show - that's the whole point of pausing) rather than
# after, so the confirmation is actually visible either way.
#
# dunst's own pause only covers standard desktop notifications (the
# freedesktop Notifications D-Bus interface) - GNOME Calendar/Evolution's
# reminder popups are a separate mechanism entirely (evolution-alarm-notify,
# its own dedicated window, not a desktop notification), so this also flips
# its notify-enable-display/notify-enable-audio gsettings in lockstep to
# actually cover both.
if [ "$(dunstctl is-paused)" = "true" ]; then
  dunstctl set-paused false
  gsettings set org.gnome.evolution-data-server.calendar notify-enable-display true
  gsettings set org.gnome.evolution-data-server.calendar notify-enable-audio true
  notify-send -h string:x-dunst-stack-tag:dnd "Do Not Disturb: off" "Notifications resumed"
else
  notify-send -h string:x-dunst-stack-tag:dnd "Do Not Disturb: on" "Notifications silenced until toggled off"
  dunstctl set-paused true
  gsettings set org.gnome.evolution-data-server.calendar notify-enable-display false
  gsettings set org.gnome.evolution-data-server.calendar notify-enable-audio false
fi
EOF
chmod +x "$BIN/dnd-toggle.sh"

cat > "$BIN/polybar-dnd.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: prints notification state (on/off), not
# dunst pause-mode state - "off" / bell-slash means silenced (dunst paused).
if [ "$(dunstctl is-paused)" = "true" ]; then
  printf '  @@ICO_BELL_OFF@@ off '
else
  printf '  @@ICO_BELL@@ on '
fi
EOF
chmod +x "$BIN/polybar-dnd.sh"
sed -i "s/@@ICO_BELL_OFF@@/$ICO_BELL_OFF/; s/@@ICO_BELL@@/$ICO_BELL/" "$BIN/polybar-dnd.sh"

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
# yet by the time i3 starts.
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

# ----------------------------------------------------------------------------
# 6d. Disable the redundant tray applets' own autostart entries
# ----------------------------------------------------------------------------
# network-manager-applet/pasystray/blueman all ship their OWN
# /etc/xdg/autostart/*.desktop entries independent of the i3 exec lines
# above - removing those exec lines alone isn't enough, since
# dex-autostart -a -e i3 (further up in the i3 config) would still pick
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
log "Writing rofi config + Catppuccin theme..."
mkdir -p "$CONF/rofi"
cat > "$CONF/rofi/catppuccin-mocha.rasi" <<'EOF'
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
    width: 30%;
    border-radius: 12px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 8px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 8;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF
cat > "$CONF/rofi/config.rasi" <<'EOF'
configuration {
    modi: "drun,run,window";
    show-icons: true;
    icon-theme: "Papirus-Dark";
    display-drun: " Apps";
    display-run: " Run";
    display-window: " Windows";
}
@theme "catppuccin-mocha"
EOF

# ----------------------------------------------------------------------------
# 8. dunst
# ----------------------------------------------------------------------------
log "Writing dunst config..."
mkdir -p "$CONF/dunst"
cat > "$CONF/dunst/dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#cba6f7"
corner_radius = 10
background = "#1e1e2e"
foreground = "#cdd6f4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#313244"

[urgency_low]
background = "#1e1e2e"
foreground = "#a6adc8"
frame_color = "#45475a"
timeout = 4

[urgency_normal]
background = "#1e1e2e"
foreground = "#cdd6f4"
frame_color = "#cba6f7"
timeout = 6

[urgency_critical]
background = "#1e1e2e"
foreground = "#f38ba8"
frame_color = "#f38ba8"
timeout = 0
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

# Catppuccin Mocha
foreground              #CDD6F4
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #F5E0DC
cursor                  #F5E0DC
cursor_text_color       #1E1E2E

color0  #45475A
color8  #585B70
color1  #F38BA8
color9  #F38BA8
color2  #A6E3A1
color10 #A6E3A1
color3  #F9E2AF
color11 #F9E2AF
color4  #89B4FA
color12 #89B4FA
color5  #F5C2E7
color13 #F5C2E7
color6  #94E2D5
color14 #94E2D5
color7  #BAC2DE
color15 #A6ADC8
EOF

# ----------------------------------------------------------------------------
# 9b. flameshot
# ----------------------------------------------------------------------------
# Flameshot >=14 defaults to capturing via the XDG desktop portal's
# org.freedesktop.portal.Screenshot interface, which nothing implements on a
# bare i3 session (no xdg-desktop-portal + WM-specific backend running) -
# "flameshot gui" just errors with "Could not locate org.freedesktop.portal.
# desktop" instead of taking a screenshot. useX11LegacyScreenshot=true makes
# it capture via Qt's native X11 grab instead, which needs no portal at all.
log "Writing flameshot config (legacy X11 capture, no portal needed)..."
mkdir -p "$CONF/flameshot"
if [ -f "$CONF/flameshot/flameshot.ini" ] && ! grep -q '^useX11LegacyScreenshot=' "$CONF/flameshot/flameshot.ini"; then
  sed -i '/^\[General\]/a useX11LegacyScreenshot=true' "$CONF/flameshot/flameshot.ini"
elif [ ! -f "$CONF/flameshot/flameshot.ini" ]; then
  cat > "$CONF/flameshot/flameshot.ini" <<'EOF'
[General]
useX11LegacyScreenshot=true
EOF
fi

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
# 11. lock script (i3lock-color + xss-lock)
# ----------------------------------------------------------------------------
log "Writing lock script..."
cat > "$BIN/lock.sh" <<'EOF'
#!/usr/bin/env bash
# --with-screensaver (passed by both xss-lock on idle activation and the
# Mod+l keybind) runs the ASCII screensaver first; dismissing it (any
# keypress) proceeds straight into the real password-protected lock below -
# unlike Omarchy's version, dismissing early does NOT cancel the pending
# lock, so locking stays fully enforced either way.
if [ "$1" = "--with-screensaver" ]; then
  kitty --class Screensaver -e ~/.local/bin/screensaver.sh
fi

# Color flags are i3lock-color-only - stock i3lock rejects unknown options
# and would just fail to lock. The tokariew COPR build of i3lock-color
# installs itself AS /usr/bin/i3lock (same binary name, extended flags -
# there is no separate "i3lock-color" command), so detect by checking
# whether the i3lock-color PACKAGE is installed via rpm, not by binary name
# or `--help` output - i3lock's `--help` always prints the same terse usage
# summary regardless of build (it just points to `man i3lock` for the full
# flag list), so grepping it for a color flag name never actually matches
# either build and silently always falls through to the plain branch below.
# This build is based on the modern Raymo111/i3lock-color fork, whose flags
# use hyphens (--inside-color) rather than the older eBrnd-style names
# (--insidecolor) - confirmed against `man i3lock` on this exact build,
# since guessing the wrong style fails with "unrecognized option" even when
# the color-capable binary IS installed.
# Blank the display immediately on lock rather than leaving the blurred
# lock screen lit until the idle DPMS timer eventually catches up (minutes
# later) - i3lock has to be backgrounded (not exec'd) so this script can
# still run `xset dpms force off` right after it starts. Any keypress/mouse
# movement wakes the display back up (X's own DPMS behavior) straight into
# the running i3lock prompt.
#
# A repeated "keep re-asserting dpms off" loop was tried here to fight a
# suspected DPMS auto-wake during i3lock's startup, but the actual flicker
# turned out to be picom fading the screensaver/i3lock windows in and out
# (see picom.conf's fade-exclude) - repeatedly calling `xset dpms force
# off` risked being an additional source of visible flicker on its own
# (some panels/drivers visibly blink on every DPMS state-change command,
# even a no-op one), so back to a single call now that the real cause is
# fixed at the compositor level instead.
lock_and_blank() {
  "$@" &
  local pid=$!
  xset dpms force off
  wait "$pid"
}

# A different Catppuccin Mocha accent for the ring every lock (the full
# official 14-color accent set) - purely cosmetic variety, doesn't touch the
# ringver/ringwrong/wrong colors below, which stay fixed so "verifying"/
# "wrong password" feedback always reads the same regardless of which
# accent got picked. The array is roughly warm-to-cool hue ordered, so the
# keypress highlight picks the accent 7 slots away (half the array) from
# the ring's - opposite-ish in hue, giving a genuinely different, vibrant
# color rather than a flat neutral, while staying entirely within the
# Catppuccin palette. A flat near-black was tried first and worked for
# contrast, but read as dull compared to the ring's own vibrancy.
ACCENTS=(f5e0dc f2cdcd f5c2e7 cba6f7 f38ba8 eba0ac fab387 f9e2af a6e3a1 94e2d5 89dceb 74c7ec 89b4fa b4befe)
ACCENT_IDX=$((RANDOM % ${#ACCENTS[@]}))
ACCENT="${ACCENTS[$ACCENT_IDX]}"
KEYHL="${ACCENTS[$(( (ACCENT_IDX + 7) % ${#ACCENTS[@]} ))]}"

GREETERS=(
  "Halt! Who goes there?"
  "Access denied. Nice try though."
  "The system is sleeping. Don't wake it rudely."
  "Enter the secret handshake."
  "sudo unlock-my-life"
  "404: Productivity not found. Try again later."
  "This machine is protected by 1s and 0s."
  "Locked tighter than my code reviews."
  "Insert coin to continue."
  "Powered by caffeine and Stack Overflow."
  "Not today, script kiddie."
  "Beep boop. State your business."
  "I'm sorry, Dave. I'm afraid I can't do that."
  "Open the pod bay doors... after you unlock."
  "It's not a bug, it's an undocumented feature."
  "42. Now enter the actual password."
  "Have you tried turning it off and on again?"
  "Resistance is futile. Password required."
  "This is not the login screen you're looking for."
  "May the Force be with your password."
  "Live long and log in."
  "Do or do not unlock. There is no try."
  "Great Scott! You need 1.21 gigawatts. Or your password."
  "There is no cloud. It's just my computer."
  "In case of emergency: sudo !!"
  "rm -rf /doubts && unlock"
)
GREETER="${GREETERS[$RANDOM % ${#GREETERS[@]}]}"

WRONGS=(
  "Nope."
  "Not even close."
  "Try again, hacker."
  "Access denied. Obviously."
  "That's a hard no."
  "Swing and a miss."
  "Nice try, but no cigar."
  "Computer says no."
  "Wrong. Try harder."
  "Denied. As expected."
  "ERROR 401: Unauthorized human."
  "This is not the password you're looking for."
  "I have a bad feeling about this password."
  "Insufficient mana. Try again."
)
WRONG="${WRONGS[$RANDOM % ${#WRONGS[@]}]}"

# --wrong-pos below (and --verif-pos, same idea) isn't in `man i3lock` - it's
# a real flag, confirmed straight from i3lock.c/unlock_indicator.c on
# github.com/Raymo111/i3lock-color, just missing from the man page. It has
# its own position independent of --greeter-pos, defaulting to "ix:iy"
# (centered on the ring, same as --verif-pos) if never set.
#
# -c/--color (a solid fill) and --blur are mutually exclusive in this
# codebase - render_lock() paints one or the other, never both - so there's
# no flag to just "darken the blur". -i/--image DOES still get drawn on top
# of the blur unconditionally, though (confirmed in unlock_indicator.c), so
# a solid black PNG tiled (-t) across the screen works as a resolution-
# independent dimming overlay: a 1x1 pixel repeated via CAIRO_EXTEND_REPEAT
# covers any screen size without needing to know actual resolution.
DIM="$HOME/.config/i3lock/dim.png"
[ -f "$DIM" ] || { mkdir -p "$HOME/.config/i3lock"; magick -size 1x1 xc:"rgba(0,0,0,0.45)" "$DIM"; }

if rpm -q i3lock-color >/dev/null 2>&1; then
  lock_and_blank i3lock \
    --blur=8 \
    -i "$DIM" -t \
    --clock --indicator \
    --no-modkey-text \
    --inside-color=1e1e2ecc \
    --ring-color="${ACCENT}ff" \
    --ring-width=14 \
    --line-uses-ring \
    --keyhl-color="${KEYHL}ff" \
    --bshl-color=f38ba8ff \
    --ringver-color=f9e2afff \
    --insidever-color=1e1e2ecc \
    --ringwrong-color=f38ba8ff \
    --insidewrong-color=1e1e2ecc \
    --separator-color=313244ff \
    --verif-color=cdd6f4ff \
    --wrong-color=f38ba8ff \
    --time-color=cdd6f4ff \
    --date-color=a6adc8ff \
    --greeter-pos="ix:iy+r+50" \
    --time-pos="ix:iy+r+100" \
    --date-pos="ix:iy+r+140" \
    --wrong-pos="ix:iy-r-30" \
    --greeter-text="$GREETER" \
    --greeter-color=cdd6f4ff \
    --wrong-text="$WRONG"
elif command -v i3lock >/dev/null 2>&1; then
  lock_and_blank i3lock -c 1e1e2e
else
  echo "lock.sh: i3lock is not installed" >&2
  exit 1
fi
EOF
chmod +x "$BIN/lock.sh"

# ----------------------------------------------------------------------------
# 11a. ASCII screensaver (Terminal Text Effects) - Mod+Escape, and shown
#      automatically before an idle-triggered lock (see --with-screensaver
#      above). Inspired by Omarchy's built-in one, same underlying tool
#      (`tte`), just run in a plain fullscreen kitty window instead of
#      Omarchy's Astal/AGS shell (which i3 doesn't have an equivalent of).
# ----------------------------------------------------------------------------
log "Installing Terminal Text Effects (tte) via pipx for the ASCII screensaver..."
if command -v pipx >/dev/null 2>&1; then
  pipx install terminaltexteffects 2>/dev/null \
    || warn "pipx install terminaltexteffects failed - the screensaver (Mod+Escape, and before an idle lock) won't work until you run it manually."
else
  warn "pipx not found - skipping the ASCII screensaver's tte dependency. Install pipx and run 'pipx install terminaltexteffects' to enable it later."
fi

log "Writing screensaver script..."
cat > "$BIN/screensaver.sh" <<'EOF'
#!/usr/bin/env bash
# ASCII-art screensaver, inspired by Omarchy's built-in one - same underlying
# tool (Terminal Text Effects / `tte`, pipx-installed), just run in a plain
# fullscreen kitty window instead of Omarchy's Astal/AGS shell (which i3
# doesn't have an equivalent of). Exits on any keypress OR mouse movement.
LOGO="$HOME/.config/screensaver/logo.txt"
[ -f "$LOGO" ] || fastfetch --logo Fedora -s none > "$LOGO"

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
mkdir -p "$CONF/screensaver"
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch --logo Fedora -s none > "$CONF/screensaver/logo.txt" 2>/dev/null
fi

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
# Icon-only menu (green=lock, sky=suspend, yellow=logout, peach=reboot,
# red=shutdown) - no labels, so there's no text to wrap/clip in a narrow
# column. rofi echoes back the exact line it displayed, so matching on the
# icon glyph itself (rather than a label string) is what identifies the
# selection here.
choice=$(printf '<span foreground="#a6e3a1" font="JetBrainsMono Nerd Font 26">@@ICO_LOCK@@</span>\n<span foreground="#89dceb" font="JetBrainsMono Nerd Font 26">@@ICO_SUSPEND@@</span>\n<span foreground="#f9e2af" font="JetBrainsMono Nerd Font 26">@@ICO_LOGOUT@@</span>\n<span foreground="#fab387" font="JetBrainsMono Nerd Font 26">@@ICO_REBOOT@@</span>\n<span foreground="#f38ba8" font="JetBrainsMono Nerd Font 26">@@ICO_SHUTDOWN@@</span>' \
  | rofi -dmenu -markup-rows -i -p "" -theme ~/.config/rofi/powermenu.rasi)
case "$choice" in
  *"@@ICO_LOCK@@"*)     ~/.local/bin/lock.sh --with-screensaver ;;
  *"@@ICO_SUSPEND@@"*)  systemctl suspend ;;
  *"@@ICO_LOGOUT@@"*)   i3-msg exit ;;
  *"@@ICO_REBOOT@@"*)   systemctl reboot ;;
  *"@@ICO_SHUTDOWN@@"*) systemctl poweroff ;;
esac
EOF
chmod +x "$BIN/powermenu.sh"
ICO_LOCK=$''
ICO_SUSPEND=$''
ICO_LOGOUT=$''
ICO_REBOOT=$''
ICO_SHUTDOWN=$''
sed -i \
  -e "s/@@ICO_LOCK@@/$ICO_LOCK/g" \
  -e "s/@@ICO_SUSPEND@@/$ICO_SUSPEND/g" \
  -e "s/@@ICO_LOGOUT@@/$ICO_LOGOUT/g" \
  -e "s/@@ICO_REBOOT@@/$ICO_REBOOT/g" \
  -e "s/@@ICO_SHUTDOWN@@/$ICO_SHUTDOWN/g" \
  "$BIN/powermenu.sh"

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
# 12. Wallpaper fallback (solid Catppuccin base color) if none exists
# ----------------------------------------------------------------------------
if [ ! -f "$CONF/i3/wallpaper.png" ]; then
  if command -v convert >/dev/null 2>&1; then
    log "Generating a solid Catppuccin-base fallback wallpaper..."
    convert -size 1920x1080 xc:'#1e1e2e' "$CONF/i3/wallpaper.png"
  else
    warn "ImageMagick not found — drop your own image at $CONF/i3/wallpaper.png"
    touch "$CONF/i3/wallpaper.png"
  fi
fi
# Feed it to nitrogen so there's an actual saved pick to `--restore` on first
# login instead of a blank/undefined X background - re-run `nitrogen` (bound
# to Mod+shift+w) any time to pick a real image; this only bootstraps one.
if command -v nitrogen >/dev/null 2>&1 && [ ! -f "$CONF/nitrogen/bg-saved.cfg" ]; then
  nitrogen --set-zoom-fill --save "$CONF/i3/wallpaper.png" >/dev/null 2>&1 \
    || warn "nitrogen couldn't set the initial wallpaper (no X session yet?) — run 'nitrogen --set-zoom-fill --save ~/.config/i3/wallpaper.png' once you're in an i3 session, or just press Mod+shift+w to pick a real image."
fi

# ----------------------------------------------------------------------------
# 13. Catppuccin GTK3/4 theme (best-effort — cosmetic only, won't fail the script)
# ----------------------------------------------------------------------------
# Not packaged for Fedora. The official catppuccin/gtk GitHub releases ship
# prebuilt theme folders (just GTK CSS + assets, no compilation) - download
# the Mocha/mauve variant matching the rest of this rice and drop it
# straight into ~/.themes.
GTK_THEME_NAME="catppuccin-mocha-mauve-standard+default"
if [ ! -d "$HOME/.themes/$GTK_THEME_NAME" ]; then
  log "Downloading Catppuccin GTK theme (Mocha, mauve accent)..."
  GTK_THEME_TMPZIP="$(mktemp --suffix=.zip)"
  if curl -fLo "$GTK_THEME_TMPZIP" \
      "https://github.com/catppuccin/gtk/releases/download/v1.0.3/${GTK_THEME_NAME}.zip" 2>/dev/null; then
    mkdir -p "$HOME/.themes"
    unzip -o "$GTK_THEME_TMPZIP" -d "$HOME/.themes" >/dev/null
  else
    warn "Catppuccin GTK theme download failed (network issue?) - GTK apps will fall back to whatever theme is already configured; install it manually later from https://github.com/catppuccin/gtk/releases."
  fi
  rm -f "$GTK_THEME_TMPZIP"
else
  log "Catppuccin GTK theme already present, skipping download."
fi

mkdir -p "$CONF/gtk-3.0" "$CONF/gtk-4.0"
for gtk_settings in "$CONF/gtk-3.0/settings.ini" "$CONF/gtk-4.0/settings.ini"; do
  cat > "$gtk_settings" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME_NAME
gtk-icon-theme-name=Papirus-Dark
gtk-application-prefer-dark-theme=1
gtk-font-name=Sans 10
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

log "Done."
cat <<'EOF'

────────────────────────────────────────────────────────────
 Next steps
────────────────────────────────────────────────────────────
 1. Log out.
 2. At the GDM login screen, click the gear icon next to the
    password field and select "i3" (it's a plain Xorg session —
    installing the i3 package registers it automatically).
 3. First login will look mostly bare until picom/polybar spawn
    (a couple seconds). If polybar doesn't appear, run:
        polybar -c ~/.config/polybar/config.ini top-primary
    from a kitty terminal (Mod+Return) to see errors directly.
 4. Brightness keys need the 'video' group membership added above -
    log out/in (or reboot) once for that to take effect.
 5. Multi-monitor: plug in your monitor(s), run `arandr` to drag them
    into the arrangement you want, then `autorandr --save mylayout` to
    save it. autorandr auto-detects and re-applies saved layouts on
    hotplug from then on, and its postswitch hook re-launches polybar
    (one bar per output, tray/battery/bluetooth only on whichever is
    primary) and re-restores the wallpaper. By default i3 leaves
    workspaces wherever they were first created, which feels like a
    separate desktop per monitor - edit the `workspace <n> output <name>`
    block near the top of the "workspaces" section in ~/.config/i3/config
    (commented out) to pin workspace ranges to specific outputs instead.
 6. udiskie (USB automount), gammastep (night light), and snixembed (SNI
    tray icon proxy - lets apps like 1Password/Discord/OBS show a tray
    icon at all) all start silently in the background - no keybinding
    needed. gammastep needs a location to compute sunrise/sunset; it uses
    geoclue2 automatically if available, otherwise edit
    ~/.config/gammastep/config.ini to set a fixed lat/lon (see
    `man gammastep`).
 7. Press Mod+shift+w (nitrogen) to pick a real wallpaper - a solid dark
    placeholder is set initially so login isn't blank.
 8. GTK apps are themed Catppuccin Mocha (GTK2, GTK3, and GTK4 settings
    are all written directly); re-run `lxappearance` yourself any time to
    change the theme/icons/font/cursor interactively instead.

 Cheat sheet (Mod = Super/Windows key):
   Mod+Return        open kitty
   Mod+d             app launcher (rofi)
   Mod+e             file manager (pcmanfm)
   Mod+shift+w       wallpaper picker (nitrogen)
   Mod+l             lock screen
   Mod+shift+p       power menu (lock/suspend/logout/reboot/shutdown)
   Mod+shift+v       clipboard history (copyq)
   Print             screenshot (flameshot gui)
   Mod+shift+q       close focused window
   Mod+f             fullscreen toggle
   Mod+shift+space   floating toggle
   Mod+1..9          switch workspace
   Mod+shift+1..9    move window to workspace
   Mod+h/j/k/l-ish   focus (h/j/k/; — see config)
   Mod+ctrl+h/l      focus next/prev monitor
   Mod+ctrl+shift+h/l move workspace to next/prev monitor
   Mod+shift+r       restart i3
   Mod+shift+e       exit i3 (with confirm)
   XF86 media/volume/brightness keys all bound - see config for specifics.

 Polybar widgets are clickable where it makes sense:
   left-click wifi/ethernet     open nm-connection-editor
   right-click wifi             toggle wifi radio on/off
   left-click bluetooth         open blueman-manager

 Run `fastfetch` in a terminal for the obligatory rice screenshot.
────────────────────────────────────────────────────────────
EOF