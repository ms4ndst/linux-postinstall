#!/usr/bin/env bash
# ============================================================================
# i3 "hackerbox" post-install script — Fedora 44
# Theme: Catppuccin Mocha | Layout: gapped + picom blur/shadows
#
# Installs: i3, picom, polybar, rofi, dunst, kitty, feh, i3lock-color (COPR,
#           with a stock i3lock fallback), xss-lock, polkit-gnome, flameshot,
#           ImageMagick, brightnessctl, playerctl, numlockx, dex, autorandr,
#           arandr, fastfetch, Nerd Font, tray helpers, GTK/icon theme, rofi
#           power menu, per-monitor polybar + wallpaper with autorandr hotplug.
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
  picom polybar rofi dunst kitty feh \
  xss-lock NetworkManager-applet pasystray blueman polkit-gnome pipewire-pulseaudio \
  lxappearance papirus-icon-theme \
  fastfetch git curl unzip jq flameshot ImageMagick \
  brightnessctl playerctl numlockx dex autorandr arandr \
  jetbrains-mono-fonts

# brightnessctl's udev rules gate /sys/class/backlight writes behind the
# "video" group - without this, the brightness keys below silently no-op.
log "Adding $USER to the 'video' group (needed for brightnessctl)..."
sudo usermod -aG video "$USER" 2>/dev/null \
  || warn "Could not add $USER to 'video' group - brightness keys may not work until you do this manually."

log "Enabling COPR for i3lock-color (not in official Fedora repos)..."
sudo dnf copr enable -y tokariew/i3lock-color || warn "COPR enable failed — you can install i3lock-color manually later."
sudo dnf install -y i3lock-color || warn "i3lock-color install failed; falling back to stock i3lock for now."

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
gaps inner 14
gaps outer 4
smart_gaps on
smart_borders on
default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart

# Catppuccin Mocha border colors
# class                 border   bground  text     indicator child_border
client.focused          #cba6f7  #1e1e2e  #cdd6f4  #cba6f7   #cba6f7
client.unfocused        #313244  #1e1e2e  #6c7086  #313244   #313244
client.focused_inactive #45475a  #1e1e2e  #a6adc8  #45475a   #45475a
client.urgent           #f38ba8  #1e1e2e  #f38ba8  #f38ba8   #f38ba8

floating_modifier $mod

# --- launch ---
bindsym $mod+Return exec kitty
bindsym $mod+d exec rofi -show drun -theme ~/.config/rofi/catppuccin-mocha.rasi
bindsym $mod+shift+d exec rofi -show run -theme ~/.config/rofi/catppuccin-mocha.rasi
bindsym $mod+shift+q kill
bindsym $mod+shift+c reload
bindsym $mod+shift+r restart
bindsym $mod+shift+e exec i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'

# --- lock / screenshot / power ---
bindsym $mod+l exec --no-startup-id ~/.local/bin/lock.sh
bindsym $mod+shift+p exec --no-startup-id ~/.local/bin/powermenu.sh
bindsym Print exec --no-startup-id "flameshot gui || import /tmp/shot-$(date +%s).png"

# --- volume / brightness / media (adjust key names if your kernel maps differ) ---
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +5%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-
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
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+shift+1 move container to workspace number 1
bindsym $mod+shift+2 move container to workspace number 2
bindsym $mod+shift+3 move container to workspace number 3
bindsym $mod+shift+4 move container to workspace number 4
bindsym $mod+shift+5 move container to workspace number 5

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
exec --no-startup-id nm-applet
exec --no-startup-id pasystray
exec --no-startup-id blueman-applet
exec --no-startup-id /usr/libexec/polkit-gnome-authentication-agent-1
exec --no-startup-id ~/.local/bin/wallpaper.sh
exec --no-startup-id dunst
exec --no-startup-id numlockx on
# Runs any other installed app's ~/.config/autostart .desktop entries (tray
# apps, sync clients, etc.) - bare i3 has no XDG autostart support of its own.
exec --no-startup-id dex -a -e i3
exec --no-startup-id xss-lock --transfer-sleep-lock -- ~/.local/bin/lock.sh
# Idle-based lock: screensaver activation at 5min (triggers xss-lock -> lock.sh),
# DPMS standby/suspend/off at 5/10/15min so the lock lands before the display blanks.
exec --no-startup-id xset s 300 dpms 300 600 900

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
log "Writing polybar config..."
mkdir -p "$CONF/polybar"
cat > "$CONF/polybar/config.ini" <<'EOF'
[colors]
base     = #1e1e2e
mantle   = #181825
text     = #cdd6f4
subtext  = #a6adc8
mauve    = #cba6f7
blue     = #89b4fa
green    = #a6e3a1
yellow   = #f9e2af
red      = #f38ba8
surface1 = #45475a

[bar/top]
; set by polybar-launch.sh (one instance per connected output) - falls back
; to polybar's own auto-picked primary monitor if launched without it.
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 8
padding-left = 1
padding-right = 1
module-margin = 1
font-0 = "JetBrainsMono Nerd Font:size=10;2"
modules-left = i3
modules-center = date
; tray only actually renders on whichever instance wins X11's single-owner
; tray selection (usually the first one launched) - expected on multi-monitor.
modules-right = pulseaudio network-wired network-wireless memory cpu tray

[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
label-focused-background = ${colors.surface1}
label-focused-foreground = ${colors.mauve}
label-focused-padding = 2
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent-foreground = ${colors.red}
label-urgent-padding = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = %date%  %time%
label-foreground = ${colors.blue}

[module/cpu]
type = internal/cpu
interval = 2
label = " %percentage%%"
label-foreground = ${colors.green}

[module/memory]
type = internal/memory
interval = 2
label = " %percentage_used%%"
label-foreground = ${colors.yellow}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface_type = wired
interval = 3
label-connected = " %ifname%"
label-connected-foreground = ${colors.blue}
format-disconnected =

[module/network-wireless]
type = internal/network
interface_type = wireless
interval = 3
label-connected = " %essid%"
label-connected-foreground = ${colors.blue}
format-disconnected =

[module/pulseaudio]
type = internal/pulseaudio
label-volume = " %percentage%%"
label-muted = " muted"
label-volume-foreground = ${colors.mauve}

[module/tray]
type = internal/tray
tray-spacing = 8

[settings]
screenchange-reload = true
EOF

# ----------------------------------------------------------------------------
# 6b. Multi-monitor helper scripts (polybar per output, wallpaper per output,
#     autorandr hotplug hook)
# ----------------------------------------------------------------------------
log "Writing multi-monitor helper scripts..."
cat > "$BIN/polybar-launch.sh" <<'EOF'
#!/usr/bin/env bash
# One polybar instance per connected output (falls back to whatever polybar
# picks as primary if --list-monitors comes back empty, e.g. a stale X state).
pkill -x polybar
while pgrep -x polybar >/dev/null; do sleep 0.1; done
mapfile -t MONITORS < <(polybar --list-monitors 2>/dev/null | cut -d: -f1)
if [ "${#MONITORS[@]}" -eq 0 ]; then
  polybar -c ~/.config/polybar/config.ini top &
else
  for m in "${MONITORS[@]}"; do
    MONITOR="$m" polybar -c ~/.config/polybar/config.ini top &
  done
fi
EOF
chmod +x "$BIN/polybar-launch.sh"

cat > "$BIN/wallpaper.sh" <<'EOF'
#!/usr/bin/env bash
# feh fills the ENTIRE virtual screen with a single image by default, which
# stretches it across every monitor combined instead of filling each one -
# repeat the same image once per connected output so each gets its own fill.
WALLPAPER="$HOME/.config/i3/wallpaper.png"
n=$(xrandr --query 2>/dev/null | grep -c ' connected')
[ "$n" -lt 1 ] && n=1
args=()
for ((i = 0; i < n; i++)); do args+=("$WALLPAPER"); done
feh --bg-fill "${args[@]}"
EOF
chmod +x "$BIN/wallpaper.sh"

# autorandr's postswitch hook fires on every profile change (monitor plugged/
# unplugged/reconfigured) - re-run both scripts so bars and wallpaper follow
# the new output layout instead of staying stuck on the old one.
mkdir -p "$CONF/autorandr"
cat > "$CONF/autorandr/postswitch" <<'EOF'
#!/usr/bin/env bash
~/.local/bin/polybar-launch.sh
~/.local/bin/wallpaper.sh
EOF
chmod +x "$CONF/autorandr/postswitch"

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
# --insidecolor/--ringcolor/etc. are i3lock-color-only flags - stock i3lock
# rejects unknown options and would just fail to lock, so branch on which
# binary is actually present instead of assuming the COPR build succeeded.
if command -v i3lock-color >/dev/null 2>&1; then
  exec i3lock-color \
    --insidecolor=1e1e2eff \
    --ringcolor=cba6f7ff \
    --line-uses-inside \
    --keyhlcolor=a6e3a1ff \
    --ringvercolor=f9e2afff \
    --ringwrongcolor=f38ba8ff \
    --separatorcolor=313244ff \
    --verifcolor=cdd6f4ff \
    --wrongcolor=f38ba8ff \
    --insidevercolor=1e1e2eff \
    --insidewrongcolor=1e1e2eff \
    --timecolor=cdd6f4ff \
    --datecolor=a6adc8ff \
    --clock --indicator
elif command -v i3lock >/dev/null 2>&1; then
  exec i3lock -c 1e1e2e
else
  echo "lock.sh: neither i3lock-color nor i3lock is installed" >&2
  exit 1
fi
EOF
chmod +x "$BIN/lock.sh"

# ----------------------------------------------------------------------------
# 11b. Power menu (lock / shutdown / reboot / suspend / logout via rofi)
# ----------------------------------------------------------------------------
log "Writing power menu script..."
cat > "$BIN/powermenu.sh" <<'EOF'
#!/usr/bin/env bash
choice=$(printf ' Lock\n Suspend\n Logout\n Reboot\n Shutdown' \
  | rofi -dmenu -i -p "Power" -theme ~/.config/rofi/catppuccin-mocha.rasi)
case "$choice" in
  *Lock*)     ~/.local/bin/lock.sh ;;
  *Suspend*)  systemctl suspend ;;
  *Logout*)   i3-msg exit ;;
  *Reboot*)   systemctl reboot ;;
  *Shutdown*) systemctl poweroff ;;
esac
EOF
chmod +x "$BIN/powermenu.sh"

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

# ----------------------------------------------------------------------------
# 13. GTK / icon theme (best-effort — cosmetic only, won't fail the script)
# ----------------------------------------------------------------------------
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true

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
        polybar -c ~/.config/polybar/config.ini top
    from a kitty terminal (Mod+Return) to see errors directly.
 4. Brightness keys need the 'video' group membership added above -
    log out/in (or reboot) once for that to take effect.
 5. Multi-monitor: plug in your monitor(s), run `arandr` to drag them
    into the arrangement you want, then `autorandr --save mylayout` to
    save it. autorandr auto-detects and re-applies saved layouts on
    hotplug from then on, and its postswitch hook re-launches polybar
    (one bar per output) and re-tiles the wallpaper automatically.

 Cheat sheet (Mod = Super/Windows key):
   Mod+Return        open kitty
   Mod+d             app launcher (rofi)
   Mod+l             lock screen
   Mod+shift+p       power menu (lock/suspend/logout/reboot/shutdown)
   Print             screenshot (flameshot gui)
   Mod+shift+q       close focused window
   Mod+f             fullscreen toggle
   Mod+shift+space   floating toggle
   Mod+1..5          switch workspace
   Mod+shift+1..5    move window to workspace
   Mod+h/j/k/l-ish   focus (h/j/k/; — see config)
   Mod+ctrl+h/l      focus next/prev monitor
   Mod+ctrl+shift+h/l move workspace to next/prev monitor
   Mod+shift+r       restart i3
   Mod+shift+e       exit i3 (with confirm)
   XF86 media/volume/brightness keys all bound - see config for specifics.

 Run `fastfetch` in a terminal for the obligatory rice screenshot.
────────────────────────────────────────────────────────────
EOF