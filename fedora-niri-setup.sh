#!/usr/bin/env bash
# ============================================================================
# Niri "hackerbox" post-install script - Fedora 44 (HANCORE waybar themes)
#
# A scrolling-tiling Wayland rice built on niri (github.com/YaLTeR/niri), the
# sibling of this repo's Sway rice (fedora-sway-setup.sh). It reuses the SAME
# theme collection and switcher: HANCORE-linux/waybar-themes, fetched at install
# time and adapted at install time, so one pick retints waybar, rofi, kitty,
# dunst, starship, the niri focus-ring, GTK, Neovim and VS Code together.
#
# Installs: niri (from the upstream yalter/niri COPR), waybar, swaybg, swayidle,
#           swaylock, rofi, dunst, kitty, grim/slurp/satty, ImageMagick,
#           brightnessctl, playerctl, fastfetch, Nerd Font, tray helpers,
#           GTK/icon themes, copyq, udiskie, gammastep, azote, volume/brightness
#           OSD popups, and NiriMod (github.com/srinivasr/NiriMod) - a GTK4
#           settings editor for niri, bound to Mod+Shift+S.
#
# Settings management: NiriMod edits ~/.config/niri/config.kdl graphically
#           (validated through `niri validate`, comments preserved). This script
#           seeds a complete config.kdl; use NiriMod or hand-edit from there.
#
# Build/maintenance: the embedded helper scripts and the niri config live in
#           niri-build/; re-sync them into this file with
#           `python3 -I niri-build/build_fedora_niri.py`.
#
# Idempotent-ish: safe to re-run, but back up existing configs first if you
# have your own dotfiles - this OVERWRITES the files listed above.
# ===============================================================================
set -euo pipefail

log()  { echo -e "\e[1;35m[niri-setup]\e[0m $*"; }
warn() { echo -e "\e[1;33m[niri-setup]\e[0m $*"; }

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
# Keep sudo warm for the whole run.
sudo -v || true
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

CONF="$HOME/.config"
BIN="$HOME/.local/bin"
FONTS="$HOME/.local/share/fonts"
mkdir -p "$CONF" "$BIN" "$FONTS"

# Default cursor theme - referenced when the niri config is written (its
# cursor block is filled from it) and by the GTK section later. Qogir is
# installed in section 9b; cursor-theme.sh switches between its 6 variants.
CURSOR_THEME_NAME="Qogir"

CLEAN_THEMES=0
printf '\nThis script will install the HANCORE waybar theme collection.\n'
read -r -p 'Clean out ALL existing desktop themes first, then install the new ones? [y/N] ' reply || true
case "$reply" in
  [yY]|[yY][eE][sS]) CLEAN_THEMES=1 ;;
esac
unset reply

# ----------------------------------------------------------------------------
# 0. Safety net: snapper snapshot of / before touching anything
# ----------------------------------------------------------------------------
if command -v snapper >/dev/null 2>&1 \
    && sudo snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx root; then
  log "Taking a snapper snapshot of / before starting (rollback point)..."
  if SNAP_NUM="$(sudo snapper -c root create --type single --print-number \
      --description "before fedora-niri-setup.sh" 2>/dev/null)"; then
    log "Snapshot #$SNAP_NUM created. Roll back with: sudo snapper -c root undochange ${SNAP_NUM}..0"
  else
    warn "snapper snapshot failed — proceeding without a rollback point."
  fi
else
  warn "snapper not found (or no 'root' config) — skipping pre-install snapshot."
fi

# ----------------------------------------------------------------------------
# 1. Packages
# ----------------------------------------------------------------------------
# niri is not in Fedora's repos; the upstream author maintains the yalter/niri
# COPR (stable). dnf5's copr plugin ships with dnf-plugins-core.
log "Enabling the yalter/niri COPR (upstream niri builds for Fedora)..."
sudo dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
if ! sudo dnf copr enable -y yalter/niri 2>/dev/null; then
  warn "Could not enable the yalter/niri COPR automatically. If niri fails to install below, enable it manually: sudo dnf copr enable yalter/niri"
fi

log "Installing niri + the Wayland rice toolkit via dnf..."
sudo dnf install -y \
  niri \
  waybar swaybg swayidle swaylock \
  cava btop \
  grim slurp wl-clipboard \
  rofi-wayland dunst kitty \
  xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \
  network-manager-applet blueman lxqt-policykit pipewire-pulseaudio wireplumber \
  copyq udiskie gammastep libnotify gnome-calendar \
  azote \
  system-config-printer \
  lxappearance papirus-icon-theme adwaita-cursor-theme \
  fastfetch git curl unzip jq ImageMagick fortune-mod xdotool \
  brightnessctl playerctl pipx dex-autostart dnf-utils nwg-displays \
  solaar solaar-udev evolution-data-server \
  gtk4 libadwaita python3-gobject python3-cairo \
  jetbrains-mono-fonts \
  || warn "Some packages failed to install - check the dnf output above; the rice still works without the optional ones."

# niri itself is mandatory - bail early with a clear message if the COPR step
# did not land it, rather than writing configs for a compositor that is absent.
if ! command -v niri >/dev/null 2>&1; then
  warn "niri is not installed. Enable the COPR and install it, then re-run:"
  warn "  sudo dnf copr enable yalter/niri && sudo dnf install niri"
  exit 1
fi

# satty (screenshot annotator) - not always packaged; best-effort.
if ! command -v satty >/dev/null 2>&1; then
  sudo dnf install -y satty >/dev/null 2>&1 \
    || warn "satty not available via dnf - screenshots fall back to a plain save+copy. Install satty later for annotation (github.com/gabm/Satty)."
fi

# brightnessctl's udev rules gate /sys/class/backlight writes behind the
# "video" group - without this, the brightness keys silently no-op.
log "Adding $USER to the 'video' group (needed for brightnessctl)..."
sudo usermod -aG video "$USER" 2>/dev/null \
  || warn "Could not add $USER to 'video' group - brightness keys may not work until you do."

# ----------------------------------------------------------------------------
# 2. Nerd Font (JetBrainsMono) — official Fedora repos don't ship patched fonts
# ----------------------------------------------------------------------------
if [ ! -d "$FONTS/JetBrainsMonoNerd" ]; then
  log "Downloading JetBrainsMono Nerd Font..."
  TMPZIP="$(mktemp --suffix=.zip)"
  if curl -fLo "$TMPZIP" \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" 2>/dev/null; then
    mkdir -p "$FONTS/JetBrainsMonoNerd"
    unzip -o "$TMPZIP" -d "$FONTS/JetBrainsMonoNerd" >/dev/null
    fc-cache -f "$FONTS/JetBrainsMonoNerd"
  else
    warn "Nerd Font download failed - configs still reference 'JetBrainsMono Nerd Font'; install it manually later."
  fi
  rm -f "$TMPZIP"
else
  log "JetBrainsMono Nerd Font already present, skipping download."
fi

# ----------------------------------------------------------------------------
# 3. Niri config
# ----------------------------------------------------------------------------
log "Writing niri config..."
mkdir -p "$CONF/niri/themes"
cat > "$CONF/niri/config.kdl" <<'NIRI_KDL_EOF'
// Niri rice config - Fedora. Written by fedora-niri-setup.sh.
// Niri is a scrolling-tiling Wayland compositor configured in KDL; this is the
// equivalent of the Sway rice's config, mapped onto niri's model (columns scroll
// horizontally, windows stack vertically within a column). Validate edits with
// `niri validate`. Niri live-reloads this file (and every include) on save.
//
// Docs: https://yalter.github.io/niri/

// --- input -------------------------------------------------------------------
input {
    keyboard {
        numlock
        xkb {
            // @@XKB_LAYOUT@@ is filled from the system layout (localectl) at
            // install time. Set your own layout(s) here, e.g. layout "us,se".
            layout "@@XKB_LAYOUT@@"
        }
    }
    touchpad {
        tap
        natural-scroll
        dwt            // disable-while-typing
    }
    mouse {
        // accel-profile "flat"
    }
    // Focus the window under the pointer as it moves. Comment out for
    // click-to-focus only.
    focus-follows-mouse max-scroll-amount="0%"
    // Warp the mouse to the focused window on keyboard focus changes.
    // warp-mouse-to-focus
}

// --- outputs -----------------------------------------------------------------
// One block per monitor; niri applies the matching one. List names/modes with
// `niri msg outputs`. Left disabled by default (the `/-` prefix) so niri
// auto-arranges; uncomment and edit to pin resolution/scale/position.
/-output "eDP-1" {
    mode "1920x1080@60.000"
    scale 1.0
    position x=0 y=0
    transform "normal"
}

// --- layout ------------------------------------------------------------------
layout {
    gaps 8
    center-focused-column "never"

    // Column width presets cycled by Mod+R. Matches the Sway rice's tiling feel.
    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }
    default-column-width { proportion 0.5; }

    // Accent ring around the focused column - niri's idiomatic equivalent of
    // Sway's focused border color. The colors below are the Catppuccin Mocha
    // defaults; the active desktop theme's palette is applied live by
    // waybar-theme.sh, which writes themes/current.kdl (included at the bottom
    // of this file and merged over these values).
    focus-ring {
        width 2
        active-color "#cba6f7"
        inactive-color "#45475a"
    }
    // A thin border on every window (CSD apps self-decorate; this keeps a
    // consistent 1px edge). Off would drop it entirely.
    border {
        off
    }

    struts {
        // waybar reserves its own space via layer-shell exclusive zones, so no
        // manual struts are needed here.
    }
}

// --- misc --------------------------------------------------------------------
prefer-no-csd
// Ask apps to omit their own titlebars where they honor it. Pair with the
// focus-ring above for a clean tiled look.

screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

hotkey-overlay {
    // Show the built-in keybind cheat-sheet at startup until you learn them;
    // comment `skip-at-startup` back in to suppress it.
    skip-at-startup
}

environment {
    // Hint toolkits/Qt toward Wayland; niri exports XDG_CURRENT_DESKTOP=niri
    // and feeds the systemd/D-Bus activation environment itself.
    QT_QPA_PLATFORM "wayland"
    MOZ_ENABLE_WAYLAND "1"
    ELECTRON_OZONE_PLATFORM_HINT "auto"
}

cursor {
    xcursor-theme "@@CURSOR_THEME@@"
    xcursor-size 24
}

// --- startup -----------------------------------------------------------------
// Bar, wallpaper, notifications, tray helpers, idle/lock. The wrapper scripts
// live in ~/.local/bin; spawn-sh-at-startup runs a shell so the pgrep guards
// and PATH work. Niri does NOT re-run these on config reload (unlike Sway's
// exec_always), so each guards against a double-launch itself.
spawn-sh-at-startup "~/.local/bin/waybar-launch.sh"
spawn-sh-at-startup "~/.local/bin/swaybg-restore.sh"
spawn-sh-at-startup "pgrep -x dunst >/dev/null || dunst"
spawn-sh-at-startup "pgrep -x playerctld >/dev/null || playerctld daemon"
spawn-sh-at-startup "pgrep -x copyq >/dev/null || copyq"
spawn-sh-at-startup "pgrep -x udiskie >/dev/null || udiskie --tray"
spawn-sh-at-startup "pgrep -x gammastep >/dev/null || gammastep"
spawn-at-startup "/usr/libexec/lxqt-policykit-agent"
spawn-sh-at-startup "~/.local/bin/calendar-reminder-daemon-launch.sh"
spawn-sh-at-startup "~/.local/bin/battwatch.sh"
// Autostart desktop entries (XDG ~/.config/autostart), niri-tagged.
spawn-sh-at-startup "command -v dex-autostart >/dev/null && dex-autostart -a -e niri"
// Idle + lock: swayidle works on niri (wayland idle protocol). Screensaver +
// lock after idle; display off later; lock before sleep. Guarded against
// stacking inside the launcher.
spawn-sh-at-startup "~/.local/bin/swayidle-launch.sh"

// --- workspaces ---------------------------------------------------------------
// Dynamic workspaces (no named/fixed ones): niri's default, and the waybar
// theme shows a fixed set of slots. niri-scratch.sh stashes summoned utilities
// on the trailing empty workspace (niri has no truly-hidden workspace).

// --- window rules ------------------------------------------------------------
// Float + center + size the usual settings-style dialogs and app-mode windows.
// Niri matches on app-id / title (regex in r#"..."#). Multipart `window-rule`
// blocks are independent (not merged), one concern each.

// Settings / connection / dialog utilities -> small floating + centered.
window-rule {
    match app-id=r#"^(nm-connection-editor|blueman-manager|org.pulseaudio.pavucontrol|pavucontrol|system-config-printer)$"#
    open-floating true
}
window-rule {
    match app-id=r#"^(com.github.hluk.copyq|copyq)$"#
    open-floating true
    default-column-width { fixed 450; }
}
// Screenshot annotator (satty).
window-rule {
    match app-id=r#"^com.gabm.satty$"#
    open-floating true
}
// Greenshot editor - float it (region capture uses screencopy, not a window,
// so this only affects the editor/settings windows). StartupWMClass=greenshot.
window-rule {
    match app-id=r#"^greenshot$"#
    open-floating true
    // Fix the size so the editor opens centered and doesn't grow off to the
    // right as Greenshot resizes itself to a large screenshot (niri anchors a
    // floating window's top-left on resize). 90% of the screen; proportion
    // keeps it right on any resolution.
    default-column-width { proportion 0.9; }
    default-window-height { proportion 0.9; }
}
// Mistral Vibe web app: pin the floating size so it matches Claude's window
// (the browser profile otherwise remembers an over-tall window that doesn't fit).
window-rule {
    match app-id=r#"^MistralVibe$"#
    open-floating true
    default-column-width { fixed 1200; }
    default-window-height { fixed 850; }
}
// Polkit auth dialog (e.g. unlocking 1Password after the vault locks).
window-rule {
    match app-id=r#"^lxqt-policykit-agent$"#
    open-floating true
}
// NiriMod settings editor - float it, give it room.
window-rule {
    match app-id=r#"^(io.github.srinivasr.NiriMod|nirimod|NiriMod)$"#
    open-floating true
    default-column-width { proportion 0.6; }
}
// Scratchpad utilities (summoned/stashed by niri-scratch.sh): open floating and
// centered so a summon lands as an overlay.
window-rule {
    match app-id=r#"^(Cliamp|com.anthropic.Claude|claude|MistralVibe|AIVibe)$"#
    open-floating true
}
// Size the terminal-based ones (kitty would otherwise open near-fullscreen).
window-rule {
    match app-id=r#"^AIVibe$"#
    default-column-width { fixed 1000; }
    default-window-height { fixed 700; }
}
window-rule {
    match app-id=r#"^Cliamp$"#
    default-column-width { fixed 760; }
    default-window-height { fixed 520; }
}
// cliamp's setup wizard and the rice's own rofi/kitty utility windows.
window-rule {
    match app-id=r#"^(CliampSetup|AppMenuTask|KeybindingsHelp|UpdatesTask|WeatherFloat)$"#
    open-floating true
}
// Size them (kitty/rofi windows would otherwise open near-fullscreen).
window-rule {
    match app-id=r#"^WeatherFloat$"#
    default-column-width { fixed 765; }
    default-window-height { fixed 600; }
}
window-rule {
    match app-id=r#"^KeybindingsHelp$"#
    default-column-width { fixed 950; }
    default-window-height { fixed 820; }
}
window-rule {
    match app-id=r#"^UpdatesTask$"#
    default-column-width { fixed 1000; }
    default-window-height { fixed 560; }
}
window-rule {
    match app-id=r#"^AppMenuTask$"#
    default-column-width { fixed 640; }
    default-window-height { fixed 420; }
}
// Block-art screensaver (Mod+Escape / idle) - fullscreen.
window-rule {
    match app-id=r#"^Screensaver$"#
    open-fullscreen true
}
// GNOME Calendar / print dialog floats.
window-rule {
    match app-id=r#"^(org.gnome.Calendar|system-config-printer)$"#
    open-floating true
}
// Rounded corners + a hair of shadow on floating windows, for polish.
window-rule {
    geometry-corner-radius 8
    clip-to-geometry true
}

// --- animations --------------------------------------------------------------
animations {
    slowdown 1.0
}

// --- key bindings ------------------------------------------------------------
// Mod = Super. Mirrors the Sway rice where niri has an equivalent action;
// niri-native actions (column/overview/consume) have no Sway analog.
binds {
    // Help overlay (niri's built-in binding cheat-sheet).
    Mod+Shift+Slash { show-hotkey-overlay; }

    // --- launch ---
    Mod+Return hotkey-overlay-title="Open a terminal: kitty" { spawn "kitty"; }
    Mod+Space hotkey-overlay-title="Run an application" { spawn-sh "~/.local/bin/fresh-env rofi -show drun -theme ~/.config/rofi/current.rasi"; }
    Mod+Shift+Space { spawn-sh "~/.local/bin/fresh-env rofi -show run -theme ~/.config/rofi/current.rasi"; }
    Mod+E { spawn-sh "~/.local/bin/fresh-env ~/.local/bin/strata"; }
    Mod+Shift+W { spawn-sh "~/.local/bin/fresh-env ~/.local/bin/wallpaper-picker.sh"; }
    Mod+P { spawn "system-config-printer"; }
    // NiriMod - GUI settings management for this config.
    Mod+Shift+S hotkey-overlay-title="Niri settings (NiriMod)" { spawn-sh "~/.local/bin/niri-mod.sh"; }
    // App menu - rofi menu reaching the rice's own utility scripts.
    Mod+Alt+Space hotkey-overlay-title="App menu" { spawn-sh "~/.local/bin/app-menu.sh"; }
    // Keybinding cheat-sheet (this rice's, in a floating kitty).
    Mod+I { spawn-sh "kitty --class KeybindingsHelp -e ~/.local/bin/keybindings-help.sh"; }
    // Block-art screensaver.
    Mod+Escape { spawn-sh "kitty --class Screensaver -e ~/.local/bin/screensaver.sh"; }

    // --- rice toggles ---
    // repeat=false on these toggles: niri repeats a held bind by default, which
    // fires the toggle several times and cancels it (show-then-hide) - so a held
    // or slow key press "won't hide". One action per physical press now.
    Mod+Shift+C repeat=false hotkey-overlay-title="Caffeine (inhibit idle)" { spawn-sh "~/.local/bin/caffeine-toggle.sh"; }
    Mod+N repeat=false hotkey-overlay-title="Do Not Disturb toggle" { spawn-sh "~/.local/bin/dnd-toggle.sh"; }
    // Scratchpad apps (summon/stash via niri-scratch.sh).
    Mod+M       repeat=false hotkey-overlay-title="Music player (cliamp)" { spawn-sh "~/.local/bin/cliamp-toggle.sh"; }
    Mod+Shift+M repeat=false { spawn-sh "~/.local/bin/cliamp-setup.sh"; }
    Mod+A       repeat=false hotkey-overlay-title="AI window (Mistral Vibe CLI)" { spawn-sh "~/.local/bin/ai-window-toggle.sh"; }
    Mod+Shift+A repeat=false { spawn-sh "~/.local/bin/mistral-vibe-toggle.sh"; }
    // Copilot/AI key (Super+Shift+F23 on recent laptops) -> Claude Desktop.
    Mod+Shift+F23 repeat=false { spawn-sh "~/.local/bin/claude-desktop-toggle.sh"; }

    // --- window management ---
    Mod+Shift+Q repeat=false { close-window; }
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }
    Mod+Shift+Backslash { toggle-window-floating; }
    Mod+Ctrl+Space { switch-focus-between-floating-and-tiling; }
    Mod+C { center-column; }

    // --- focus (columns = left/right, windows in a column = up/down) ---
    Mod+H     { focus-column-left; }
    Mod+L     { focus-column-right; }
    Mod+J     { focus-window-down; }
    Mod+K     { focus-window-up; }
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Down  { focus-window-down; }
    Mod+Up    { focus-window-up; }

    // --- move ---
    Mod+Shift+H     { move-column-left; }
    Mod+Shift+L     { move-column-right; }
    Mod+Shift+J     { move-window-down; }
    Mod+Shift+K     { move-window-up; }
    Mod+Shift+Left  { move-column-left; }
    Mod+Shift+Right { move-column-right; }

    // --- consume / expel windows into and out of the current column ---
    Mod+Comma  { consume-window-into-column; }
    Mod+Period { expel-window-from-column; }
    Mod+BracketLeft  { consume-or-expel-window-left; }
    Mod+BracketRight { consume-or-expel-window-right; }

    // --- column sizing ---
    Mod+R      { switch-preset-column-width; }
    Mod+Minus  { set-column-width "-10%"; }
    Mod+Equal  { set-column-width "+10%"; }
    Mod+Shift+Minus { set-window-height "-10%"; }
    Mod+Shift+Equal { set-window-height "+10%"; }

    // --- multi-monitor ---
    Mod+Ctrl+H { focus-monitor-left; }
    Mod+Ctrl+L { focus-monitor-right; }
    Mod+Ctrl+Shift+H { move-column-to-monitor-left; }
    Mod+Ctrl+Shift+L { move-column-to-monitor-right; }

    // --- workspaces (niri workspaces are a dynamic vertical strip per monitor) ---
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    Mod+Shift+5 { move-column-to-workspace 5; }
    Mod+Shift+6 { move-column-to-workspace 6; }
    Mod+Shift+7 { move-column-to-workspace 7; }
    Mod+Shift+8 { move-column-to-workspace 8; }
    Mod+Shift+9 { move-column-to-workspace 9; }
    Mod+Page_Down { focus-workspace-down; }
    Mod+Page_Up   { focus-workspace-up; }
    Mod+Shift+Page_Down { move-column-to-workspace-down; }
    Mod+Shift+Page_Up   { move-column-to-workspace-up; }

    // --- overview (niri's bird's-eye view of all workspaces) ---
    Mod+Tab { toggle-overview; }

    // --- lock / screenshot / power ---
    Mod+Alt+L hotkey-overlay-title="Lock the screen" { spawn-sh "~/.local/bin/lock.sh --with-screensaver"; }
    // grim + slurp + satty (the rice's editor). niri's own `screenshot` action
    // is still available on Ctrl/Alt+Print below.
    Print { spawn-sh "~/.local/bin/fresh-env ~/.local/bin/screenshot.sh"; }
    Ctrl+Print  { screenshot-screen; }
    Alt+Print   { screenshot-window; }
    Mod+Shift+P { spawn-sh "~/.local/bin/fresh-env ~/.local/bin/powermenu.sh"; }

    // --- colorpicker / clipboard ---
    Mod+Shift+G { spawn-sh "~/.local/bin/colorpicker.sh"; }
    Mod+Shift+V { spawn "copyq" "toggle"; }

    // --- volume / brightness / media ---
    XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "~/.local/bin/osd-volume.sh up"; }
    XF86AudioLowerVolume allow-when-locked=true { spawn-sh "~/.local/bin/osd-volume.sh down"; }
    XF86AudioMute        allow-when-locked=true { spawn-sh "~/.local/bin/osd-volume.sh mute"; }
    XF86MonBrightnessUp   { spawn-sh "~/.local/bin/osd-brightness.sh up"; }
    XF86MonBrightnessDown { spawn-sh "~/.local/bin/osd-brightness.sh down"; }
    XF86AudioPlay allow-when-locked=true { spawn "playerctl" "play-pause"; }
    XF86AudioNext allow-when-locked=true { spawn "playerctl" "next"; }
    XF86AudioPrev allow-when-locked=true { spawn "playerctl" "previous"; }

    // --- session ---
    // Niri live-reloads on save, so there is no manual reload bind.
    Mod+Shift+E { quit; }
}

// --- active theme (applied live by waybar-theme.sh) --------------------------
// Positional include: merged OVER everything above, so the current theme's
// focus-ring palette wins. The installer always seeds this file, so the include
// never dangles.
include "themes/current.kdl"
NIRI_KDL_EOF
# Fill the system keyboard layout and the installed cursor theme into the
# placeholders the config ships with.
__xkb="$(localectl status 2>/dev/null | sed -n 's/.*X11 Layout: *//p' | head -1)"
sed -i "s/@@XKB_LAYOUT@@/${__xkb:-us}/" "$CONF/niri/config.kdl"
sed -i "s/@@CURSOR_THEME@@/${CURSOR_THEME_NAME}/" "$CONF/niri/config.kdl"
# Seed an empty active-theme include so the `include "themes/current.kdl"` line
# never dangles before the first theme is applied (section 6 overwrites it).
if [ ! -f "$CONF/niri/themes/current.kdl" ]; then
  cat > "$CONF/niri/themes/current.kdl" <<'CURKDL_EOF'
// Active desktop theme's niri focus-ring palette. Rewritten by waybar-theme.sh
// on every theme switch; the Catppuccin Mocha defaults below apply until then.
layout {
    focus-ring {
        active-color "#cba6f7"
        inactive-color "#45475a"
    }
}
CURKDL_EOF
fi

# ----------------------------------------------------------------------------
# 3b. xdg-desktop-portal: disable the GlobalShortcuts portal
# ----------------------------------------------------------------------------
# Claude Desktop (and some other apps) request a global shortcut via the
# GlobalShortcuts portal. Only xdg-desktop-portal-gnome implements it, and its
# backend pops an "Add Keyboard Shortcuts" confirmation dialog on every launch.
# This rice summons those apps via niri keybinds, not their own global
# shortcuts, so route GlobalShortcuts to `none` (xdg-desktop-portal >= 1.18).
# A user override replaces the whole file, so the other routings from niri's
# shipped niri-portals.conf are repeated here; screencast/file-chooser stay on
# gnome/gtk.
mkdir -p "$CONF/xdg-desktop-portal"
cat > "$CONF/xdg-desktop-portal/niri-portals.conf" <<'EOF'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
org.freedesktop.impl.portal.GlobalShortcuts=none;
EOF

# ----------------------------------------------------------------------------
# 4. Terminal / lock / screenshot app configs
# ----------------------------------------------------------------------------
log "Writing kitty / swaylock / satty / fastfetch configs..."
mkdir -p "$CONF/kitty"
cat > "$CONF/kitty/kitty.conf" <<'EOF'
font_family      JetBrainsMono Nerd Font
font_size        11.0
background_opacity 0.95
window_padding_width 8
confirm_os_window_close 0
enabled_layouts splits,stack
# allow waybar-theme.sh to push live color changes over the control socket
allow_remote_control yes
listen_on unix:/tmp/kitty-{kitty_pid}
# The active desktop theme's palette (seeded + switched by waybar-theme.sh).
include current.conf
EOF
# A neutral default palette until the first theme is applied.
[ -f "$CONF/kitty/current.conf" ] || cat > "$CONF/kitty/current.conf" <<'EOF'
foreground #cdd6f4
background #1e1e2e
EOF

mkdir -p "$CONF/swaylock"
cat > "$CONF/swaylock/config" <<'EOF'
# Catppuccin Mocha swaylock (github.com/catppuccin/swaylock). lock.sh layers a
# blurred screenshot + fortune quote on top; these colors show through.
ignore-empty-password
indicator
indicator-radius=100
indicator-thickness=7
font=JetBrainsMono Nerd Font
ring-color=1e1e2e
key-hl-color=cba6f7
line-color=00000000
inside-color=00000088
separator-color=00000000
text-color=cdd6f4
ring-ver-color=a6e3a1
inside-ver-color=00000088
text-ver-color=a6e3a1
ring-wrong-color=f38ba8
inside-wrong-color=00000088
text-wrong-color=f38ba8
ring-clear-color=f9e2af
inside-clear-color=00000088
text-clear-color=f9e2af
EOF

mkdir -p "$CONF/satty"
cat > "$CONF/satty/config.toml" <<'EOF'
[general]
early-exit = true
initial-tool = "brush"
output-filename = "~/Pictures/Screenshots/satty-%Y%m%d-%H%M%S.png"
copy-command = "wl-copy"
actions-on-enter = ["save-to-clipboard"]
actions-on-escape = ["exit"]
EOF

mkdir -p "$CONF/fastfetch"
cat > "$CONF/fastfetch/config.jsonc" <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": { "type": "builtin" },
  "modules": [
    "title", "separator", "os", "host", "kernel", "uptime",
    "packages", "shell", "wm", "terminal", "cpu", "memory", "break", "colors"
  ]
}
EOF

# ----------------------------------------------------------------------------
# 5. Helper scripts (~/.local/bin)
# ----------------------------------------------------------------------------
log "Installing helper scripts into $BIN..."

# fresh-env: run a program with the live GTK/cursor theme env, so apps launched
# from niri binds pick up a theme switch without a re-login.
cat > "$BIN/fresh-env" <<'EOF'
#!/usr/bin/env bash
set -u
gt="$(sed -n 's/^GTK_THEME=//p' "$HOME/.config/environment.d/gtk-theme.conf" 2>/dev/null || true)"
[ -n "$gt" ] && export GTK_THEME="$gt"
ct="$(sed -n 's/^XCURSOR_THEME=//p' "$HOME/.config/environment.d/cursor-theme.conf" 2>/dev/null || true)"
[ -n "$ct" ] && export XCURSOR_THEME="$ct"
exec "$@"
EOF
chmod +x "$BIN/fresh-env"

# app-theme-sync: retints the terminal apps that draw their own colors (cliamp,
# Mistral Vibe, Strata) to the active desktop theme. waybar-theme.sh runs it
# after every switch. (Embedded from niri-build/bin; chmod'd by the glob below.)
cat > "$BIN/app-theme-sync.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Brings the terminal apps that draw their OWN colors in line with the
# active desktop theme - kitty's colors alone don't reach them. Run by
# waybar-theme.sh after every theme switch (and once by the setup script),
# reading the theme's kitty palette and niri focus-ring color that
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
BORDERS_CURRENT="$HOME/.config/niri/themes/current.kdl"
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
accent="$(hex "$(awk '/active-color/{ gsub(/[",]/,"",$2); print $2; exit }' "$BORDERS_CURRENT" 2>/dev/null)" "$(hex "$(kc color5)" "$fg")")"

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

if command -v ttt >/dev/null 2>&1; then
  # ttt (terminal IDE, run as `ttt` in any kitty window) is themed by a
  # rice-branded theme plugin: a rebranded, re-pointed copy of ttt's own
  # bundled "omarchy-theme" plugin - the same proven, contrast-safe
  # palette->theme converter - reading the rice palette written below and
  # emitting ~/.config/ttt/themes/rice.json. The stock omarchy-theme plugin is
  # disabled so no Omarchy naming reaches ttt's UI.
  tcfg="$HOME/.config/ttt"
  mkdir -p "$tcfg/themes" "$tcfg/plugins"
  # The rice palette as TOML for the plugin. background is a deepened copy of
  # kitty's: a ttt cell background exactly equal to kitty's own (translucent)
  # default background inherits kitty's background_opacity and shows the
  # wallpaper through the editor - the Strata problem - so deepen it ~18% to
  # render opaque while still reading as the theme's dark base.
  ttt_darken() { printf '#%02x%02x%02x' $(( 16#${1:1:2}*82/100 )) $(( 16#${1:3:2}*82/100 )) $(( 16#${1:5:2}*82/100 )); }
  {
    printf 'background = "%s"\n' "$(ttt_darken "$(hex "$(kc background)" '#1e1e2e')")"
    printf 'foreground = "%s"\n' "$fg"
    printf 'accent = "%s"\n' "$accent"
    for __i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      printf 'color%s = "%s"\n' "$__i" "$(hex "$(kc color$__i)" '#585b70')"
    done
  } > "$tcfg/rice-palette.toml"
  # Derive the rice-theme plugin once from ttt's installed omarchy-theme plugin
  # (ttt fetches that on first launch). Same converter, re-pointed + rebranded.
  if [ -f "$tcfg/plugins/omarchy-theme/init.lua" ] && [ ! -f "$tcfg/plugins/rice-theme/init.lua" ]; then
    mkdir -p "$tcfg/plugins/rice-theme"
    sed -e 's#~/.local/state/omarchy/current/theme/colors.toml#~/.config/ttt/rice-palette.toml#' \
        -e 's#~/.local/state/omarchy/current/theme/vscode-theme.json#~/.config/ttt/rice-tokens.json#' \
        -e 's#{config}/themes/omarchy.json#{config}/themes/rice.json#g' \
        -e 's/~= "omarchy"/~= "rice"/' \
        -e 's/Omarchy theme: /Rice theme: /g' \
        -e 's/Omarchy palette requires/Rice palette requires/' \
        "$tcfg/plugins/omarchy-theme/init.lua" > "$tcfg/plugins/rice-theme/init.lua"
    cat > "$tcfg/plugins/rice-theme/plugin.ttt.json" <<'PJSON'
{
  "name": "rice-theme",
  "displayName": "Rice Theme",
  "description": "Keep a TTT theme in sync with the active desktop rice palette.",
  "version": "0.1.0",
  "author": "linux-postinstall",
  "entry": "init.lua",
  "api": 1,
  "permissions": {
    "fs.read": ["~/.config/ttt"],
    "fs.write": ["{config}/themes"],
    "settings": true,
    "settings_keys": ["theme"],
    "commands": true
  }
}
PJSON
  fi
  # Disable the Omarchy plugin and register rice-theme (only once ttt has
  # created its plugin registry on first launch).
  if [ -f "$tcfg/plugins.ttt.json" ]; then
    python3 - "$tcfg/plugins.ttt.json" "$tcfg/plugins/rice-theme/init.lua" <<'PY' 2>/dev/null || true
import json, os, sys
reg_path, rice_init = sys.argv[1], sys.argv[2]
try:
    reg = json.load(open(reg_path))
    if not isinstance(reg, list):
        raise ValueError
except Exception:
    sys.exit(0)
for r in reg:
    if isinstance(r, dict) and r.get("name") == "omarchy-theme":
        r["enabled"] = False
if os.path.exists(rice_init) and not any(
        isinstance(r, dict) and r.get("name") == "rice-theme" for r in reg):
    reg.append({
        "name": "rice-theme", "displayName": "Rice Theme", "repo": "local",
        "path": "rice-theme", "version": "0.1.0", "enabled": True,
        "permissions": {"commands": True, "fs.read": ["~/.config/ttt"],
                        "fs.write": ["{config}/themes"], "network.http": False,
                        "settings": True, "settings_keys": ["theme"]},
        "grantsVersion": 2})
json.dump(reg, open(reg_path, "w"), indent=2)
open(reg_path, "a").write("\n")
PY
  fi
  # A hand-written fallback theme so ttt is themed even before the plugin runs
  # (or if its omarchy-theme source was never fetched); the plugin overwrites
  # themes/rice.json with a richer, contrast-safe version once active.
  if [ ! -f "$tcfg/themes/rice.json" ]; then
    ttt_bg="$(ttt_darken "$(hex "$(kc background)" '#1e1e2e')")"
    ttt_mut="$(hex "$(kc color8)" '#585b70')"
    cat > "$tcfg/themes/rice.json" <<JSON
{
  "default":   { "fg": "$fg", "bg": "$ttt_bg" },
  "muted":     { "fg": "$ttt_mut" },
  "statusBar": { "fg": "$accent" },
  "tabs":      { "active": { "fg": "$accent", "bold": true } },
  "editor":    { "lineNumber": { "fg": "$ttt_mut" } },
  "syntax": {
    "comment":  { "fg": "$ttt_mut" },
    "string":   { "fg": "$(hex "$(kc color2)" '#a6e3a1')" },
    "keyword":  { "fg": "$(hex "$(kc color5)" '#cba6f7')", "bold": true },
    "number":   { "fg": "$(hex "$(kc color1)" '#f38ba8')" },
    "function": { "fg": "$(hex "$(kc color4)" '#89b4fa')" }
  }
}
JSON
  fi
  # Select the rice theme (ttt merges a partial settings.json over its defaults).
  ttt_settings="$tcfg/settings.json"
  python3 - "$ttt_settings" <<'PY' 2>/dev/null || { [ -f "$ttt_settings" ] || printf '{\n  "theme": "rice"\n}\n' > "$ttt_settings"; }
import json, os, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}
d["theme"] = "rice"
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
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
RICE_EOF

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
cat > "$BIN/swaybg-restore.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Restore the saved wallpaper with swaybg (niri has no built-in wallpaper;
# swaybg is a layer-shell client and works fine under niri). Sources, in order
# (between the first two, whichever pick is newer wins):
#   1. ~/.config/niri/wallpaper-saved     - written by the rofi picker
#   2. ~/.local/share/azote/swaybg.json   - written by azote, one entry per
#      output (azote is the preferred picker when installed)
#   3. ~/.config/niri/wallpaper.png       - seeded by the installer
# niri does not re-run startup spawns on reload, but this is also bound/callable
# directly, so kill any previous swaybg first to avoid stacking.
set -u
CFG="$HOME/.config/niri"
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
# Fall back to the wallpaper seeded by the installer.
[ "${#ARGS[@]}" -eq 0 ] && [ -f "$CFG/wallpaper.png" ] \
  && ARGS=(-i "$CFG/wallpaper.png" -m fill)
[ "${#ARGS[@]}" -eq 0 ] && exit 0

pkill -x swaybg 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swaybg >/dev/null 2>&1 || break; sleep 0.1; done
swaybg "${ARGS[@]}" >/dev/null 2>&1 &
disown || true
RICE_EOF
cat > "$BIN/wallpaper-picker.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Rofi-based wallpaper picker. Lists images from the usual wallpaper dirs, sets
# the pick with swaybg, and saves the path so swaybg-restore.sh brings it back
# on the next login. If azote (the Wayland-native nitrogen equivalent) is
# installed, prefer its GUI instead.
set -uo pipefail

if command -v azote >/dev/null 2>&1; then
  exec azote
fi

DIRS=(
  "$HOME/Pictures/wallpapers"
  "$HOME/Pictures/gh0stzk-wallpapers"
  "$HOME/.config/niri"
  "$HOME/Pictures"
)
SAVED="$HOME/.config/niri/wallpaper-saved"
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
cat > "$BIN/lock.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/screenshot.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Region screenshot for the Niri rice using the Wayland tools: slurp selects a
# region, grim captures it. If satty (a flameshot-style annotation editor,
# github.com/gabm/Satty) is installed, the shot is piped to it for arrows/text/
# blur + save/copy; satty's config.toml sets the save dir (~/Pictures/
# Screenshots), wl-copy as the copy command, and Enter = copy. If satty is
# missing, the shot is saved to ~/Pictures/Screenshots and copied to the
# clipboard directly. Pass `full` to capture the whole output.
#
# (niri also has a built-in interactive screenshot action, bound to
# Ctrl/Alt+Print in the config; this script is the satty-integrated path on the
# bare Print key.)
set -u
# niri's spawn PATH can omit ~/.local/bin, so a satty installed there (rather
# than system-wide) would be invisible and this would silently fall back to a
# plain save. Search both.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# The App Menu's "Screenshot Tool" item stores the chosen default in
# ~/.config/niri/screenshot-tool. "greenshot" hands the Print key to the full
# Wayland Greenshot (github.com/ms4ndst/greenshot_for_linux). Any other value
# (or no file yet) keeps this script's built-in grim+slurp pipeline below.
if grep -qx greenshot "$HOME/.config/niri/screenshot-tool" 2>/dev/null \
  && command -v greenshot >/dev/null 2>&1; then
  if [ "${1:-region}" = "full" ]; then
    exec greenshot capture fullscreen
  else
    exec greenshot capture region
  fi
fi

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"

if [ "${1:-region}" = "full" ]; then
  GEO=""
else
  GEO="$(slurp 2>/dev/null)" || exit 0   # Escape/cancel -> exit quietly
  [ -n "$GEO" ] || exit 0
fi

if command -v satty >/dev/null 2>&1; then
  # satty reads its save path (output-filename), copy command (wl-copy) and
  # key actions from ~/.config/satty/config.toml, so just pipe the capture in.
  if [ -n "$GEO" ]; then grim -g "$GEO" -t ppm - | satty --filename -; else grim -t ppm - | satty --filename -; fi
else
  OUT="$DIR/shot-$(date +%Y%m%d-%H%M%S).png"
  if [ -n "$GEO" ]; then grim -g "$GEO" "$OUT" || exit 1; else grim "$OUT" || exit 1; fi
  wl-copy --type image/png < "$OUT" 2>/dev/null || true
  command -v notify-send >/dev/null && notify-send "Screenshot" "Saved to $OUT and copied to clipboard"
fi
RICE_EOF
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
cat > "$BIN/swayidle-launch.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Idle management for the Niri rice via swayidle (it speaks the wayland idle
# protocol niri implements). Timings:
#   - 20min (1200s): show the screensaver and lock (lock.sh --with-screensaver)
#   - 50min (3000s): power the displays off; power back on when activity resumes
#   - before sleep: lock first so resume lands on the lock screen
# niri does not re-run startup spawns on reload, but this is also callable
# directly, so single-instance it first.
# The idle context inherits niri's login-time PATH, which may not include
# ~/.local/bin - the tools the lock/screensaver chain needs live there, so
# re-add it before exec.
export PATH="$HOME/.local/bin:$PATH"
set -u
pkill -x swayidle 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swayidle >/dev/null 2>&1 || break; sleep 0.1; done

exec swayidle -w \
  timeout 1200 "$HOME/.local/bin/lock.sh --with-screensaver" \
  timeout 3000 'niri msg action power-off-monitors' \
    resume     'niri msg action power-on-monitors' \
  before-sleep "$HOME/.local/bin/lock.sh"
RICE_EOF
cat > "$BIN/waybar-theme.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Lists available themes (~/.config/waybar/themes/*/) via rofi and, on
# selection, applies matching waybar + rofi + kitty + starship + dunst + niri
# focus-ring themes together, so one pick retints the whole desktop instead of
# just the bar. Each is its own COMPLETE, standalone config applied with a plain
# file copy. The niri accent is a focus-ring KDL fragment (themes/<base>.kdl)
# that the installer derived from each theme's palette; niri live-reloads it
# through the `include "themes/current.kdl"` line at the bottom of config.kdl.
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
# The per-theme niri focus-ring fragments (layout { focus-ring { ... } }). The
# config.kdl includes themes/current.kdl; copying over it retints the ring.
# Keyed by base name (no -square/-numbered/-alt).
NIRI_THEMES_DIR="$HOME/.config/niri/themes"
NIRI_CURRENT="$NIRI_THEMES_DIR/current.kdl"
mkdir -p "$NIRI_THEMES_DIR"
NVIM_COLORS_DIR="$HOME/.config/nvim/colors"
NVIM_CURRENT="$NVIM_COLORS_DIR/current.lua"
# The active theme's name; seeded by the installer and re-written on every pick.
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
# for the GTK/niri/nvim palettes (no corner-rounding concept in those).
BASE_NAME="${CHOSEN%-square}"
BASE_NAME="${BASE_NAME%-numbered}"
BASE_NAME="${BASE_NAME%-alt}"
NIRI_FILE="$NIRI_THEMES_DIR/$BASE_NAME.kdl"

if [ ! -d "$WAYBAR_DIR" ]; then
  notify-send "Desktop Theme" "No such theme: $CHOSEN"
  exit 1
fi

# Record the pick up front (not at the end): a mid-switch failure under set -e
# would otherwise leave the name file pointing at the previous theme while the
# bar already runs the new one.
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
# The HANCORE theme styles @import "../omarchy/current/theme/waybar.css" for
# their @background/@foreground/@transparent - copy this theme's own palette
# there too, so the bar follows the switch.
if [ -f "$WAYBAR_DIR/palette.css" ]; then
  mkdir -p "$HOME/.config/omarchy/current/theme"
  cp "$WAYBAR_DIR/palette.css" "$HOME/.config/omarchy/current/theme/waybar.css"
fi
# Some themes @import a sibling palette by RELATIVE path. style.css is copied to
# ~/.config/waybar/, so a relative `./` import resolves against that dir - copy
# every sibling .css there too, or waybar drops the ENTIRE stylesheet.
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
  for sock in /tmp/kitty-*; do
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

# niri focus-ring: copy this theme's KDL fragment over the included current.kdl.
# niri watches the include and live-reloads the ring color on its own - no
# explicit reload needed (and none that would disturb the layout).
if [ -f "$NIRI_FILE" ]; then
  cp "$NIRI_FILE" "$NIRI_CURRENT"
  # Validate quietly; a bad fragment would make niri keep the last good config.
  niri validate >/dev/null 2>&1 || true
else
  notify-send "Desktop Theme" "No niri focus-ring theme for $CHOSEN, keeping previous"
fi

# cliamp and app-mode windows draw their own colors on top of kitty's - bring
# them in line with the kitty/palette files just applied.
~/.local/bin/app-theme-sync.sh || true

NVIM_FILE="$NVIM_COLORS_DIR/rice-$BASE_NAME.lua"
if [ -f "$NVIM_FILE" ]; then
  cp "$NVIM_FILE" "$NVIM_CURRENT"
  for sock in /tmp/nvim-*; do
    [ -S "$sock" ] || continue
    nvim --server "$sock" --remote-expr 'v:lua.vim.cmd("colorscheme current")' >/dev/null 2>&1 || true
  done
else
  notify-send "Desktop Theme" "No neovim theme for $BASE_NAME, keeping previous"
fi

notify-send "Desktop Theme" "Switched to $CHOSEN"
RICE_EOF
cat > "$BIN/niri-mod.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Launch NiriMod - the GTK4 settings editor for niri (github.com/srinivasr/
# NiriMod). Installed by the setup script via NiriMod's own install.sh, which
# drops a `nirimod` launcher on PATH and a .desktop entry. This wrapper keeps
# the keybind stable regardless of exactly how NiriMod was installed.
set -u
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

if command -v nirimod >/dev/null 2>&1; then
  exec nirimod "$@"
elif command -v niri-mod >/dev/null 2>&1; then
  exec niri-mod "$@"
elif command -v flatpak >/dev/null 2>&1 && flatpak info io.github.srinivasr.NiriMod >/dev/null 2>&1; then
  exec flatpak run io.github.srinivasr.NiriMod "$@"
else
  notify-send "NiriMod" "NiriMod is not installed. Re-run the niri setup, or install it from github.com/srinivasr/NiriMod" 2>/dev/null \
    || echo "NiriMod is not installed (github.com/srinivasr/NiriMod)" >&2
  exit 1
fi
RICE_EOF
cat > "$BIN/osd-volume.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Volume control + a dunst OSD popup for the Niri rice. Uses wpctl (PipeWire's
# WirePlumber control); the stacked-tag notification replaces itself so repeated
# key presses update one popup instead of stacking.
set -u
SINK="@DEFAULT_AUDIO_SINK@"
STEP="5%"

case "${1:-}" in
  up)   wpctl set-mute "$SINK" 0; wpctl set-volume -l 1.5 "$SINK" "${STEP}+" ;;
  down) wpctl set-mute "$SINK" 0; wpctl set-volume "$SINK" "${STEP}-" ;;
  mute) wpctl set-mute "$SINK" toggle ;;
  *)    echo "usage: osd-volume.sh up|down|mute" >&2; exit 1 ;;
esac

read -r _ VOL MUTED < <(wpctl get-volume "$SINK" 2>/dev/null)
PCT=$(awk -v v="${VOL:-0}" 'BEGIN{printf "%d", v*100}')
if [ "${MUTED:-}" = "[MUTED]" ] || [ "$PCT" -eq 0 ]; then
  ICON="audio-volume-muted"; TEXT="Muted"
elif [ "$PCT" -lt 34 ]; then
  ICON="audio-volume-low"; TEXT="${PCT}%"
elif [ "$PCT" -lt 67 ]; then
  ICON="audio-volume-medium"; TEXT="${PCT}%"
else
  ICON="audio-volume-high"; TEXT="${PCT}%"
fi

notify-send -h string:x-dunst-stack-tag:osd-volume \
  -h "int:value:$PCT" -i "$ICON" "Volume" "$TEXT" 2>/dev/null || true
RICE_EOF
cat > "$BIN/osd-brightness.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Backlight control + a dunst OSD popup for the Niri rice, via brightnessctl.
# The stacked-tag notification replaces itself so repeated key presses update
# one popup instead of stacking.
set -u
STEP="5%"

command -v brightnessctl >/dev/null 2>&1 || {
  notify-send -h string:x-dunst-stack-tag:osd-brightness "Brightness" "brightnessctl is not installed" 2>/dev/null
  exit 1
}

case "${1:-}" in
  up)   brightnessctl set "${STEP}+" >/dev/null ;;
  down) brightnessctl set "${STEP}-" >/dev/null ;;
  *)    echo "usage: osd-brightness.sh up|down" >&2; exit 1 ;;
esac

CUR=$(brightnessctl get 2>/dev/null)
MAX=$(brightnessctl max 2>/dev/null)
PCT=0
[ -n "${MAX:-}" ] && [ "${MAX:-0}" -gt 0 ] && PCT=$(( CUR * 100 / MAX ))

notify-send -h string:x-dunst-stack-tag:osd-brightness \
  -h "int:value:$PCT" -i "display-brightness-symbolic" "Brightness" "${PCT}%" 2>/dev/null || true
RICE_EOF
cat > "$BIN/screenshot-tool.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# App Menu settings item: pick the default screenshot tool behind the Print
# key. The choice is written to ~/.config/niri/screenshot-tool and read by
# screenshot.sh at Print-key time, so the very next screenshot uses it - no
# No compositor reload needed. Offers:
#   greenshot - the full Wayland Greenshot
#               (github.com/ms4ndst/greenshot_for_linux): region picker with
#               magnifier, the classic Greenshot annotation editor, tray and
#               save/copy/OCR/printer/upload destinations. Not packaged by
#               any distro - built from source by the repo's post-install
#               scripts (needs the .NET 10 SDK) - so it's only listed when
#               actually installed.
#   classic   - this rice's built-in pipeline: slurp region select, grim
#               capture, satty annotation when installed (else a plain save
#               + wl-clipboard). Always available and always the fallback.
set -u
# niri's spawn PATH can be bare (/usr/local/bin:/usr/bin) and omits ~/.local/bin,
# where greenshot's packaging/install.sh links the `greenshot` command.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
STATE="$HOME/.config/niri/screenshot-tool"
mkdir -p "$(dirname "$STATE")"

LABELS=(); TOOLS=()
if command -v greenshot >/dev/null 2>&1; then
  LABELS+=("Greenshot  (region picker, full editor, tray)")
  TOOLS+=(greenshot)
fi
LABELS+=("Built-in  (slurp + grim + satty)")
TOOLS+=(classic)

# Pre-select the row that matches the current choice (rofi -selected-row).
SEL=0
CUR="$(cat "$STATE" 2>/dev/null)"
for i in "${!TOOLS[@]}"; do
  [ "${TOOLS[$i]}" = "$CUR" ] && SEL=$i
done

CHOSEN="$(printf '%s\n' "${LABELS[@]}" | rofi -dmenu -i -p "Screenshot Tool" -selected-row "$SEL" -theme ~/.config/rofi/current.rasi)"
[ -z "$CHOSEN" ] && exit 0

for i in "${!LABELS[@]}"; do
  if [ "${LABELS[$i]}" = "$CHOSEN" ]; then
    echo "${TOOLS[$i]}" > "$STATE"
    command -v notify-send >/dev/null && notify-send "Screenshot Tool" "Default set to: $CHOSEN"
    exit 0
  fi
done
RICE_EOF
cat > "$BIN/niri-scratch.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Scratchpad emulation for niri. Niri has no scratchpad or minimize, so this
# uses a dedicated named "scratch" workspace (defined in config.kdl) as the
# hidden stash. Toggle semantics mirror the Sway rice's scratchpad toggles:
#   - no window matching the app-id    -> run the spawn command (summon fresh)
#   - matching window parked on scratch -> move it to the current workspace +
#                                          focus it (show)
#   - matching window visible elsewhere -> move it to scratch, focus stays put
#                                          (hide, without killing it)
# Hiding to another workspace keeps the process alive (and MPRIS/IPC live), so
# a playing cliamp or an in-progress chat is just tucked away, not lost.
#
# Usage: niri-scratch.sh <app-id-regex> <spawn command...>
set -u
command -v jq >/dev/null 2>&1 || { echo "niri-scratch.sh: jq is required" >&2; exit 1; }

APPID_RE="${1:-}"; shift || true
[ -n "$APPID_RE" ] && [ "$#" -ge 1 ] || {
  echo "usage: niri-scratch.sh <app-id-regex> <cmd...>" >&2; exit 1; }

# Debounce. A flaky AI/Copilot key (and some keyboards) emits a single press as
# two events a few ms apart; unguarded, the second invocation races the first
# and cancels the toggle (hide then show = "won't hide") or spawns a duplicate.
# A repeat within DEBOUNCE_MS of the previous run is dropped; an intentional
# re-press (~1s later) still works.
#
# The flock only guards the stamp read-modify-write and is released IMMEDIATELY
# after (fd 9 closed): the toggle may end in `exec "$@"`, and a held lock would
# be inherited by the long-lived spawned app, blocking every later press until
# that app closes.
DEBOUNCE_MS=500
__tag="$(printf '%s' "$APPID_RE" | tr -c 'A-Za-z0-9' '_')"
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/niri-scratch.$__tag.lock"
flock 9
__stamp="${XDG_RUNTIME_DIR:-/tmp}/niri-scratch.$__tag.stamp"
__now=$(date +%s%3N)
if [ -f "$__stamp" ]; then
  __last="$(cat "$__stamp" 2>/dev/null || echo 0)"
  if [ $(( __now - __last )) -lt "$DEBOUNCE_MS" ]; then exec 9>&-; exit 0; fi
fi
echo "$__now" > "$__stamp"
exec 9>&-   # release the lock before any find/spawn/exec below

windows="$(niri msg --json windows 2>/dev/null || echo '[]')"
read -r wid wws < <(printf '%s' "$windows" | jq -r --arg re "$APPID_RE" '
  ([ .[] | select(.app_id != null and (.app_id | test($re))) ] | .[0]) as $w
  | if $w == null then "" else "\($w.id) \($w.workspace_id)" end')

# Not running yet -> summon it. The window-rule in config.kdl opens it floating.
if [ -z "${wid:-}" ]; then
  exec "$@"
fi

# Decide by WHERE the window is relative to the CURRENT workspace, not merely
# whether it sits on "scratch". A window left on another desktop (because you
# switched desktops after summoning it) must be summoned here, not hidden -
# hiding it then would do nothing visible and feel like "the toggle is broken".
# Compare workspace ids (stable across niri's index renumbering); move by the
# focused workspace's index.
read -r cur_id cur_idx < <(niri msg --json workspaces 2>/dev/null \
  | jq -r '.[] | select(.is_focused) | "\(.id) \(.idx)"')

if [ -n "${cur_id:-}" ] && [ "${wws:-}" = "$cur_id" ]; then
  # On the current workspace (visible here) -> stash it on the trailing empty
  # workspace niri keeps at the end of the focused output (past the user's
  # desktops), keeping focus where it is. niri has no truly-hidden workspace,
  # and a named stash would be pinned to the front (desktop 1) and clutter the
  # bar, so the trailing workspace is the least-intrusive dynamic option.
  __out="$(niri msg --json workspaces 2>/dev/null | jq -r '.[] | select(.is_focused) | .output')"
  __last="$(niri msg --json workspaces 2>/dev/null \
    | jq -r --arg o "$__out" '[ .[] | select(.output==$o) | .idx ] | max')"
  niri msg action move-window-to-workspace --window-id "$wid" --focus false "${__last:-1}" >/dev/null 2>&1 || true
else
  # On another desktop (or stashed at the end) -> bring it here and focus it.
  niri msg action move-window-to-workspace --window-id "$wid" --focus true "${cur_idx:-1}" >/dev/null 2>&1 || true
  niri msg action focus-window --id "$wid" >/dev/null 2>&1 || true
fi
RICE_EOF
cat > "$BIN/cliamp-toggle.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Summon/stash the floating Cliamp window (Mod+M) via the niri scratchpad
# emulation, instead of leaving "quit the TUI" as the only way to get it out of
# the way (kitty exits the moment its child does, so closing has always meant
# killing playback). cliamp keeps MPRIS + its IPC socket alive while parked on
# the scratch workspace, so hiding it doesn't stop playback or lose control.
# Quitting cliamp itself (q in the TUI) still fully stops it.
exec ~/.local/bin/niri-scratch.sh '^Cliamp$' kitty --class Cliamp -e cliamp
RICE_EOF
cat > "$BIN/cliamp-setup.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Opens cliamp's own provider-configuration wizard (`cliamp setup`) in a
# floating window (Mod+Shift+M) - a genuinely different command from bare
# `cliamp` (Mod+M via cliamp-toggle.sh). Picking/configuring a remote source
# (Navidrome, Plex, Spotify, ...) only happens inside `cliamp setup`'s own
# screen, which the player's TUI has no path to. Not scratchpad-toggled - the
# wizard is a one-shot flow that exits on its own, so it's launched fresh.
exec kitty --class CliampSetup -e cliamp setup
RICE_EOF
cat > "$BIN/ai-window-toggle.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Summon/stash a floating "AI window" running the Mistral Vibe CLI (`vibe`)
# (Mod+A) via the niri scratchpad emulation, so an in-progress Vibe session
# isn't lost by just tucking the window away. The startup folder is configurable
# via the app menu's "Set AI Window Folder" entry (set-ai-window-folder.sh);
# $HOME if never set. `vibe --workdir` is its own documented flag for this.
exec ~/.local/bin/niri-scratch.sh '^AIVibe$' \
  sh -c 'exec kitty --class AIVibe -e vibe --workdir "$(cat "$HOME/.config/ai-window/workdir" 2>/dev/null || echo "$HOME")"'
RICE_EOF
cat > "$BIN/claude-desktop-toggle.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Summon/stash Claude Desktop via the niri scratchpad emulation (Copilot/AI key,
# or Mod+Shift+F23), so an in-progress conversation isn't lost by tucking the
# window away. Matches the native-Wayland app-id and the XWayland class.
exec ~/.local/bin/niri-scratch.sh '^(com\.anthropic\.Claude|claude)$' claude-desktop-unofficial
RICE_EOF
cat > "$BIN/mistral-vibe-toggle.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Summon/stash the Mistral Vibe web app (chat.mistral.ai) via the niri
# scratchpad emulation (Mod+Shift+A). Mistral ships no Linux desktop app, so it
# runs in a Chromium-family browser's --app mode (no tabs/toolbar) in its own
# profile dir, so --class takes effect and the sign-in is kept between launches.
set -u
profile="$HOME/.local/share/mistral-vibe-app"
url="https://chat.mistral.ai"

# Resolve a browser once so the spawn command handed to niri-scratch is concrete.
browser=""
for b in google-chrome-stable google-chrome chromium chromium-browser brave-browser microsoft-edge-stable vivaldi-stable vivaldi; do
  if command -v "$b" >/dev/null 2>&1; then browser="$b"; break; fi
done
if [ -z "$browser" ]; then
  notify-send "Mistral Vibe" "Needs a Chromium-based browser (Chrome, Chromium, Brave, Edge or Vivaldi) - install one from the post-install script's Browsers category." 2>/dev/null
  exit 1
fi

# --ozone-platform=x11 is deliberate: under native Wayland, Chromium/Vivaldi
# ignore --class for the app_id (it becomes vivaldi-<hash>-Default), so neither
# the floating window-rule nor the scratchpad could match. Forcing XWayland
# makes WM_CLASS=MistralVibe, which niri reports as app_id MistralVibe - so the
# window floats and the scratch toggle can find it.
exec ~/.local/bin/niri-scratch.sh '^MistralVibe$' \
  "$browser" --user-data-dir="$profile" --class=MistralVibe --ozone-platform=x11 \
  --no-first-run --no-default-browser-check --app="$url"
RICE_EOF
cat > "$BIN/caffeine-toggle.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/caffeine-state.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/dnd-toggle.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/dnd-indicator.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Waybar custom/notification-silencing-indicator backend: reports dunst's
# pause state as waybar JSON so the bar always shows a small bell -
# normal text color while notifications flow, the theme accent while
# muted (Mod+N / dnd-toggle.sh), however the toggle was triggered -
# keybind, widget click, or a bare dunstctl. The themes' CSS (plus the
# installer-appended accent rule) paints .active.
if [ "$(dunstctl is-paused)" = "true" ]; then
  printf '{"text":"","class":"active","tooltip":"Do Not Disturb: notifications muted (Mod+N or click to unmute)"}\n'
else
  printf '{"text":"","class":"","tooltip":"Notifications: on (Mod+N or click to mute)"}\n'
fi
RICE_EOF
cat > "$BIN/wifi-toggle.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/wifi-menu.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/software-update.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/notification-center.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/blueman-applet-guard.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/fix-mx-scroll.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/battwatch.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/weather-float.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Toggle a floating weather window from the waybar weather widget. First click
# opens a wttr.in-style report - the same ASCII-art condition pictures wttr.in
# draws - but rendered locally from open-meteo.com data (free, no API key),
# because wttr.in itself is frequently down or blocked on corporate networks.
# Clicking the widget again closes it (any key closes it too).
#
# The art is the wego icon set (plain ANSI colours + box chars, no Nerd-Font
# glyphs), so it renders in any font. Location: a city name resolved via
# open-meteo geocoding, or a literal "lat,lon"; set WEATHER_LOCATION or
# ~/.config/weather/location (default: Stockholm).
set -u

if [ "${1:-}" = "--show" ]; then
  python3 -I - <<'PYEOF'
import json, os, re, urllib.parse, urllib.request
from datetime import datetime

R = "\033[0m"
def paint(code, lines):
    return ["\033[%sm%s%s" % (code, ln, R) for ln in lines]

# wego / wttr.in ASCII art, 5 lines x 13 cols each.
ART = {
 "sunny": paint("38;5;226", ["    \\   /    ","     .-.     ","  ― (   ) ―  ","     `-'     ","    /   \\    "]),
 "partly": paint("38;5;250", ["   \\  /      "," _ /\"\".-.    ","   \\_(   ).  ","   /(___(__) ","             "]),
 "cloudy": paint("38;5;250", ["             ","     .--.    ","  .-(    ).  "," (___.__)__) ","             "]),
 "overcast": paint("38;5;240;1", ["             ","     .--.    ","  .-(    ).  "," (___.__)__) ","             "]),
 "fog": paint("38;5;251", ["             "," _ - _ - _ - ","  _ - _ - _  "," _ - _ - _ - ","             "]),
 "rain": paint("38;5;111", ["     .-.     ","    (   ).   ","   (___(__)  ","    ‘ ‘ ‘ ‘  ","   ‘ ‘ ‘ ‘   "]),
 "heavyrain": paint("38;5;21;1", ["     .-.     ","    (   ).   ","   (___(__)  ","  ‚‘‚‘‚‘‚‘   ","  ‚’‚’‚’‚’   "]),
 "snow": paint("38;5;255", ["     .-.     ","    (   ).   ","   (___(__)  ","    *  *  *  ","   *  *  *   "]),
 "sleet": paint("38;5;255", ["     .-.     ","    (   ).   ","   (___(__)  ","    ‘ * ‘ *  ","   * ‘ * ‘   "]),
 "thunder": paint("38;5;228", ["     .-.     ","    (   ).   ","   (___(__)  ","  ⚡‘‘⚡‘‘   ","  ‘⚡‘‘⚡‘   "]),
 "unknown": ["    .-.      ","     __)     ","    (        ","     `-'     ","      •      "],
}
# WMO weather code -> (text description, art key).
WMO = {
 0:("Clear","sunny"),1:("Mainly clear","sunny"),2:("Partly cloudy","partly"),
 3:("Overcast","overcast"),45:("Fog","fog"),48:("Rime fog","fog"),
 51:("Light drizzle","rain"),53:("Drizzle","rain"),55:("Heavy drizzle","rain"),
 56:("Freezing drizzle","sleet"),57:("Freezing drizzle","sleet"),
 61:("Light rain","rain"),63:("Rain","rain"),65:("Heavy rain","heavyrain"),
 66:("Freezing rain","sleet"),67:("Freezing rain","sleet"),
 71:("Light snow","snow"),73:("Snow","snow"),75:("Heavy snow","snow"),
 77:("Snow grains","snow"),80:("Rain showers","rain"),81:("Rain showers","rain"),
 82:("Violent showers","heavyrain"),85:("Snow showers","snow"),86:("Snow showers","snow"),
 95:("Thunderstorm","thunder"),96:("Thunderstorm, hail","thunder"),99:("Thunderstorm, hail","thunder"),
}
ARROWS = ["↓","↙","←","↖","↑","↗","→","↘"]

def getj(u):
    req = urllib.request.Request(u, headers={"User-Agent": "wttrbar-shim"})
    with urllib.request.urlopen(req, timeout=12) as r:
        return json.load(r)

def resolve():
    loc = os.environ.get("WEATHER_LOCATION")
    if not loc:
        try:
            loc = open(os.path.expanduser("~/.config/weather/location")).read().strip()
        except Exception:
            loc = ""
    loc = loc or "Stockholm"
    m = re.match(r"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$", loc)
    if m:
        return float(m.group(1)), float(m.group(2)), loc
    r = getj("https://geocoding-api.open-meteo.com/v1/search?name="
             + urllib.parse.quote(loc) + "&count=1&language=en&format=json")
    hit = (r.get("results") or [None])[0]
    if not hit:
        raise ValueError("unknown location: %r" % loc)
    label = hit["name"] + ((", " + hit["country_code"]) if hit.get("country_code") else "")
    return hit["latitude"], hit["longitude"], label

def center(s, w):
    s = s[:w]
    pad = w - len(s)
    return " " * (pad // 2) + s + " " * (pad - pad // 2)

try:
    lat, lon, label = resolve()
    d = getj("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
             "&current=temperature_2m,apparent_temperature,weather_code,"
             "wind_speed_10m,wind_direction_10m,precipitation,relative_humidity_2m"
             "&daily=weather_code,temperature_2m_max,temperature_2m_min"
             "&forecast_days=4&wind_speed_unit=kmh&timezone=auto"
             % (lat, lon))
    cur = d["current"]
    desc, key = WMO.get(int(cur["weather_code"]), ("Unknown", "unknown"))
    art = ART.get(key, ART["unknown"])
    arrow = ARROWS[int((cur.get("wind_direction_10m", 0) % 360) / 45 + 0.5) % 8]
    info = [
        desc,
        "%d °C  (feels %d °C)" % (round(cur["temperature_2m"]), round(cur["apparent_temperature"])),
        "%s %d km/h" % (arrow, round(cur.get("wind_speed_10m", 0))),
        "%.1f mm  •  %d%% hum" % (cur.get("precipitation", 0.0), round(cur.get("relative_humidity_2m", 0))),
        "",
    ]
    print()
    print("  Weather report: " + label)
    print()
    for i in range(5):
        print("  %s   %s" % (art[i], info[i]))
    print()

    dy = d["daily"]
    cols = []
    for i, day in enumerate(dy["time"]):
        ddesc, dkey = WMO.get(int(dy["weather_code"][i]), ("Unknown", "unknown"))
        da = ART.get(dkey, ART["unknown"])
        name = datetime.strptime(day, "%Y-%m-%d").strftime("%A")
        lo = round(dy["temperature_2m_min"][i]); hi = round(dy["temperature_2m_max"][i])
        col = [center(name, 13)] + da + [center("%d / %d °C" % (hi, lo), 13)]
        cols.append(col)
    for r in range(len(cols[0])):
        print("  " + "  ".join(col[r] for col in cols))
    print()
    print("  (press any key to close)")
except Exception as e:
    print()
    print("  Weather unavailable — %s" % e)
    print("  Set a city with WEATHER_LOCATION or ~/.config/weather/location.")
    print()
    print("  (press any key to close)")
PYEOF
  read -rsn1 _ 2>/dev/null || true
  exit 0
fi

# Toggle: if a WeatherFloat window is open, close it; otherwise open one.
__wid="$(niri msg --json windows 2>/dev/null | jq -r '[.[] | select(.app_id=="WeatherFloat")][0].id // empty' 2>/dev/null)"
if [ -n "${__wid:-}" ]; then
  niri msg action focus-window --id "$__wid" >/dev/null 2>&1
  niri msg action close-window >/dev/null 2>&1
else
  kitty --class WeatherFloat \
        -o background_opacity=1.0 \
        -o window_padding_width=14 \
        -o font_size=12 \
        -e "$0" --show >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
RICE_EOF
cat > "$BIN/screensaver.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/set-screensaver-text.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/set-ai-window-folder.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/icon-theme.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/cursor-theme.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Switches the mouse cursor theme between the 6 real Qogir variants installed
# during setup (the -Light variants are cursor-identical aliases, so not
# offered). Applies live: niri reads its pointer theme from the `cursor` block
# in config.kdl, so rewriting that line makes niri live-reload the new cursor;
# environment.d + GTK settings carry it to newly started apps.
#
# Usage:
#   cursor-theme.sh          # prompts via rofi
#   cursor-theme.sh <name>   # applies directly, no prompt
set -euo pipefail

THEMES=(Qogir Qogir-Dark Qogir-Manjaro Qogir-Manjaro-Dark Qogir-Ubuntu Qogir-Ubuntu-Dark)
NIRI_CONFIG="$HOME/.config/niri/config.kdl"

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

# Rewrite the xcursor-theme line in the niri config; niri watches the file and
# live-reloads the pointer on save (keeps the pick across reloads/relogin).
if [ -f "$NIRI_CONFIG" ]; then
  sed -i -E "s|(xcursor-theme)[[:space:]]+\"[^\"]*\"|\1 \"$CHOSEN\"|" "$NIRI_CONFIG"
fi

for gtk_settings in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  [ -f "$gtk_settings" ] && sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CHOSEN/" "$gtk_settings"
done
gsettings set org.gnome.desktop.interface cursor-theme "$CHOSEN" 2>/dev/null || true

# Make apps launched via systemd/dbus (portals, search providers) pick up the
# new theme without a re-login too.
systemctl --user set-environment XCURSOR_THEME="$CHOSEN" XCURSOR_SIZE=24 2>/dev/null || true

notify-send "Cursor Theme" "Switched to $CHOSEN"
RICE_EOF
cat > "$BIN/powermenu.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/app-menu.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Floating rofi menu for reaching this rice's own utility scripts in one place -
# inspired by Omarchy's Super-key menu, scoped to actions that exist here.
# Actions needing interactive input open in their own floating kitty window
# (see the AppMenuTask window-rule in config.kdl); everything else runs directly.
LABELS=(
  $'  Desktop Theme'
  $'  Cursor Theme'
  $'  Icon Theme'
  $'  Set Screensaver Text/Image'
  $'  Preview Screensaver'
  $'  Set AI Window Folder'
  $'  AI API Keys'
  $'  Toggle Caffeine'
  $'  Toggle Do Not Disturb'
  $'  Music Player'
  $'  Clipboard History'
  $'  Colorpicker'
  $'  Screenshot Tool'
  $'  Lock Screen'
  $'  Power Menu'
  $'  Niri Settings (NiriMod)'
  $'  Restart Waybar'
  $'  Keybinding Help'
  $'  Arrange Displays'
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
RICE_EOF
cat > "$BIN/keybindings-help.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/arrange-displays.sh" <<'RICE_EOF'
#!/usr/bin/env bash
# Display arrangement for niri. Unlike Sway, niri has no runtime "set output
# position" IPC - monitor layout lives in config.kdl's `output` blocks (niri
# auto-arranges left-to-right by default). So this opens a GUI editor when one
# is available (nwg-displays supports niri and writes the output blocks for
# you), and otherwise points at NiriMod + prints the current outputs.
set -u
if command -v nwg-displays >/dev/null 2>&1; then
  exec nwg-displays
fi
if command -v niri-mod.sh >/dev/null 2>&1 || command -v nirimod >/dev/null 2>&1; then
  notify-send "Displays" "Open NiriMod (Mod+Shift+S) to arrange monitors, or install nwg-displays for a drag-and-drop editor." 2>/dev/null
  exec ~/.local/bin/niri-mod.sh
fi
# Last resort: list outputs so the user can hand-edit config.kdl output blocks.
OUT="$(niri msg outputs 2>/dev/null)"
notify-send "Displays" "Install nwg-displays (drag-and-drop) or use NiriMod. Outputs:\n$OUT" 2>/dev/null \
  || printf '%s\n' "$OUT"
RICE_EOF
cat > "$BIN/calendar-reminder-daemon-launch.sh" <<'RICE_EOF'
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
RICE_EOF
cat > "$BIN/calendar-reminder-daemon.py" <<'RICE_EOF'
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
RICE_EOF
chmod +x "$BIN"/*.sh "$BIN/fresh-env" "$BIN/calendar-reminder-daemon.py"

# ----------------------------------------------------------------------------
# 6. Desktop theme collection - HANCORE-linux/waybar-themes
# ----------------------------------------------------------------------------
# The same engine the Sway rice uses: hancore-theme-gen.py adapts every
# HANCORE-linux/waybar-themes theme and writes matching waybar/rofi/kitty/dunst/
# starship files plus a sway border fragment per theme, seeding the first as
# active. On niri we then (a) rewrite the generated waybar configs' sway module
# names to their niri equivalents, and (b) convert each sway border fragment
# into a niri focus-ring KDL fragment (themes/<name>.kdl) that the switcher
# includes. The sway-named intermediate files are harmless palette data here.
if [ "$CLEAN_THEMES" = "1" ]; then
  log "Cleaning out existing desktop themes..."
  rm -rf "$CONF/waybar/themes" "$CONF/rofi/themes" "$CONF/kitty/themes" \
         "$CONF/dunst/themes" "$CONF/starship/themes" "$CONF/sway/themes" \
         "$CONF/niri/themes" "$CONF/polybar/themes"
  mkdir -p "$CONF/niri/themes"
  rm -f "$CONF/rofi/current.rasi" "$CONF/rofi/current-powermenu.rasi" \
         "$CONF/kitty/current.conf" "$CONF/dunst/dunstrc" \
         "$CONF/starship.toml" "$CONF/waybar/current-theme-name"
  if [ -d "$HOME/.themes" ]; then
    find "$HOME/.themes" -mindepth 1 -maxdepth 1 -type d -name 'Rice-*' -exec rm -rf {} + 2>/dev/null || true
  fi
  if [ -d "$CONF/nvim/colors" ]; then
    find "$CONF/nvim/colors" -maxdepth 1 -name 'rice-*.lua' -delete 2>/dev/null || true
  fi
fi

log "Fetching HANCORE waybar themes (github.com/HANCORE-linux/waybar-themes)..."
HANCORE_TMP="$(mktemp -d)"
if git clone --depth 1 -q https://github.com/HANCORE-linux/waybar-themes.git "$HANCORE_TMP"; then
  log "Adapting themes + generating matching rofi/kitty/dunst/starship/border themes..."
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

    # 1b. sway/window has no {class} format argument - that is a
    #     hyprland/window token. Left in place, waybar logs
    #     "sway/window: argument not found" and the module renders EMPTY,
    #     so the focused-window title silently vanishes on every window
    #     (31 of the upstream themes hit this). Sway's equivalent is
    #     {app_id}, which also yields the reverse-DNS values the rewrite
    #     rules already match (com.mitchellh.ghostty, org.gnome.Nautilus,
    #     com.obsproject.Studio, ...), so the per-app icon rewrites keep
    #     working for native Wayland apps.
    win = cfg.get("sway/window")
    if isinstance(win, dict) and isinstance(win.get("format"), str):
        win["format"] = win["format"].replace("{class}", "{app_id}")

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

    # 3f1. network: the upstream themes leave the network widget click-less, so
    #      clicking it did nothing. Wire it to this rice's own tools (present on
    #      both the Sway and niri rices): left opens the rofi Wi-Fi picker,
    #      right opens nm-connection-editor (full settings), middle toggles the
    #      Wi-Fi radio.
    nx = cfg.get("network")
    if isinstance(nx, dict):
        nx.setdefault("on-click", "~/.local/bin/wifi-menu.sh")
        nx.setdefault("on-click-right", "nm-connection-editor")
        nx.setdefault("on-click-middle", "~/.local/bin/wifi-toggle.sh")

    # 3f2. cpu/memory: raise the "warning" (orange background) threshold from the
    #      upstream 50% to 70%, so the widget only warms up under real sustained
    #      load instead of on routine half-usage. "critical" (red) stays at 80.
    for mk in ("cpu", "memory"):
        blk = cfg.get(mk)
        if isinstance(blk, dict) and isinstance(blk.get("states"), dict) \
                and "warning" in blk["states"]:
            blk["states"]["warning"] = 70

    # 3f3. Vertical bars (position left/right): most widgets are icons or
    #      \n-stacked, but the mpris now-playing text ("<icon> artist - title")
    #      is horizontal and blows out the narrow bar's width / clips. Rotate it
    #      90 so it reads along the bar, and cap its length so a long title
    #      can't make the whole bar wide.
    if cfg.get("position") in ("left", "right") and isinstance(cfg.get("mpris"), dict):
        cfg["mpris"]["rotate"] = 90
        cfg["mpris"].setdefault("max-length", 25)

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

    # Fix a malformed comment in HANCORE's v2.9e style.css: a "/* remove comment
    # for cava color transmissions" block (meant to keep the #mpris cava rule
    # disabled by default) is never closed AND nests a /*optional*/ inline
    # comment inside it, so GTK rejects the whole stylesheet and the bar renders
    # unstyled. De-nest the inline note and close the block after the #mpris
    # rule, keeping it disabled as the author intended. Harmless no-op on every
    # other theme (the anchor strings don't occur).
    if "/* remove comment for cava color transmissions" in css_text:
        css_text = css_text.replace(
            "background-color: @red; /*optional use @red for omarchy logo "
            "consistencie or @fg to match other themes colors*/",
            "background-color: @red;")
        css_text = css_text.replace(
            "}\n\n\n#network.disconnected,", "}\n*/\n\n\n#network.disconnected,", 1)

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
    css_text, n_palette = re.subn(r'^@import\s+"[^"]*omarchy[^"]*"\s*;?\s*$',
                                  palette_inline, css_text, count=1, flags=re.M)
    if n_palette == 0:
        # No omarchy @import to swap the palette into: these themes @import
        # a sibling palette (e.g. rose-pine.css) that only defines colors,
        # so the base text-color rule never landed and unstyled widget text
        # (the focused-window title, the idle DND bell) fell back to GTK's
        # near-black default - invisible on the dark bar. Append the palette
        # at the very end (last rule wins only for inherited defaults, so it
        # never shadows the theme's explicit per-widget colors).
        css_text = css_text.rstrip("\n") + "\n\n" + palette_inline
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

    # Some themes (e.g. v1.9b, v1.9c) reference window_pill.py in their
    # config's exec but upstream never bundles the script in the theme dir,
    # so rewrite_cmd points exec at a path that doesn't exist and the module
    # stays dead. Synthesize the pill from the template whenever the config
    # asks for it but the bundled-extras copy above didn't produce it.
    if "window_pill.py" in out_cfg and not (tdir / "window_pill.py").exists():
        write_text(tdir / "window_pill.py",
                   WINDOW_PILL_TEMPLATE.replace("@ACCENT@", palette["accent"]).replace("@TEXT@", palette["text"]))
        (tdir / "window_pill.py").chmod(0o755)
    # cava.sh / scrolling-mpris.py have no template - if a config ever
    # references one without bundling it, surface the stale ref loudly.
    for _s in ("cava.sh", "scrolling-mpris.py"):
        if _s in out_cfg and not (tdir / _s).exists():
            print("WARNING theme %s references %s but it was not bundled"
                  % (name, _s), file=sys.stderr)

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

  # (a) Rewrite the generated waybar configs' Sway module names to niri's. The
  # HANCORE generator emits sway/workspaces|window|language (it targets the Sway
  # rice); niri ships its own waybar modules with the same shape. swaymsg in any
  # custom module becomes `niri msg`. Leftover sway/mode|scratchpad references
  # (no niri analog) are simply inert - waybar warns once and skips them.
  if [ -d "$CONF/waybar/themes" ]; then
    while IFS= read -r -d '' cfg; do
      sed -i \
        -e 's#"sway/workspaces"#"niri/workspaces"#g' \
        -e 's#"sway/window"#"niri/window"#g' \
        -e 's#"sway/language"#"niri/language"#g' \
        -e 's#\bswaymsg\b#niri msg#g' \
        "$cfg"
    done < <(find "$CONF/waybar/themes" -name config.jsonc -print0 2>/dev/null)
    # The active config.jsonc was seeded as a copy before this pass - redo it.
    ACTIVE_NAME="$(cat "$CONF/waybar/current-theme-name" 2>/dev/null || true)"
    if [ -n "$ACTIVE_NAME" ] && [ -f "$CONF/waybar/themes/$ACTIVE_NAME/config.jsonc" ]; then
      cp "$CONF/waybar/themes/$ACTIVE_NAME/config.jsonc" "$CONF/waybar/config.jsonc"
    fi
  fi

  # (b) Convert each sway border fragment (client.focused/unfocused color lines)
  # into a niri focus-ring KDL fragment. client.focused's border color (field 2)
  # is the accent; client.unfocused's is the inactive ring.
  if [ -d "$CONF/sway/themes" ]; then
    for frag in "$CONF/sway/themes"/*.conf; do
      [ -f "$frag" ] || continue
      base="$(basename "$frag" .conf)"
      active="$(awk '$1=="client.focused"{print $2; exit}' "$frag")"
      inactive="$(awk '$1=="client.unfocused"{print $2; exit}' "$frag")"
      [ -n "$active" ] || active="#cba6f7"
      [ -n "$inactive" ] || inactive="#45475a"
      cat > "$CONF/niri/themes/$base.kdl" <<EOF
// niri focus-ring palette for the "$base" desktop theme (generated from the
// HANCORE theme's accent). Applied by waybar-theme.sh.
layout {
    focus-ring {
        active-color "$active"
        inactive-color "$inactive"
    }
}
EOF
    done
    # Seed the active theme's focus-ring as current.kdl.
    ACTIVE_NAME="$(cat "$CONF/waybar/current-theme-name" 2>/dev/null || true)"
    ACTIVE_BASE="${ACTIVE_NAME%-square}"; ACTIVE_BASE="${ACTIVE_BASE%-numbered}"; ACTIVE_BASE="${ACTIVE_BASE%-alt}"
    if [ -n "$ACTIVE_BASE" ] && [ -f "$CONF/niri/themes/$ACTIVE_BASE.kdl" ]; then
      cp "$CONF/niri/themes/$ACTIVE_BASE.kdl" "$CONF/niri/themes/current.kdl"
    fi
  fi
else
  warn "git clone of HANCORE-linux/waybar-themes failed (network issue?) - no bar themes installed; re-run later."
fi
rm -rf "$HANCORE_TMP"

# ----------------------------------------------------------------------------
# 7. Helper shims the adapted themes' modules exec by name (~/.local/bin)
# ----------------------------------------------------------------------------
cat > "$BIN/wttrbar" <<'HANCORESHIM_EOF'
#!/usr/bin/env python3
"""wttrbar shim for the HANCORE waybar themes.

The real wttrbar (github.com/bjesus/wttrbar) is a Go binary not packaged for
Fedora. This implements the subset of its CLI the HANCORE configs use
(--nerd, --location <name>, --custom-indicator <json>, --fahrenheit) and its
JSON output shape, so the themes' custom/weather modules work as-is:
  {"text": "15°", "alt": "Sunny", "tooltip": "Sunny: 15°C (feels 14°)"}

Data source: open-meteo.com (free, no API key). The original wttr.in backend is
a single host that is frequently down or blocked on corporate networks (a
connection-refused there is what makes the widget show nothing); open-meteo is
reliable and reachable. Location is a city name resolved via open-meteo's
geocoding API (cached), or a literal "lat,lon"; pick it with --location, the
WEATHER_LOCATION env var, or ~/.config/weather/location (default: Stockholm).

Called by waybar every 60s; a fetch failure prints the last good value when
cached, else an empty placeholder so the module just hides.
"""
import json
import os
import re
import sys
import urllib.parse
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

# WMO weather code -> (description, icon keyword matched against NERD_ICONS).
WMO = {
    0: ("Clear", "clear"), 1: ("Mainly clear", "clear"),
    2: ("Partly cloudy", "cloudy"), 3: ("Overcast", "overcast"),
    45: ("Fog", "fog"), 48: ("Rime fog", "fog"),
    51: ("Light drizzle", "drizzle"), 53: ("Drizzle", "drizzle"),
    55: ("Heavy drizzle", "drizzle"),
    56: ("Freezing drizzle", "sleet"), 57: ("Freezing drizzle", "sleet"),
    61: ("Light rain", "rain"), 63: ("Rain", "rain"), 65: ("Heavy rain", "rain"),
    66: ("Freezing rain", "sleet"), 67: ("Freezing rain", "sleet"),
    71: ("Light snow", "snow"), 73: ("Snow", "snow"), 75: ("Heavy snow", "snow"),
    77: ("Snow grains", "snow"),
    80: ("Rain showers", "shower"), 81: ("Rain showers", "shower"),
    82: ("Violent showers", "pouring"),
    85: ("Snow showers", "snow"), 86: ("Snow showers", "snow"),
    95: ("Thunderstorm", "thunder"),
    96: ("Thunderstorm, hail", "thunder"), 99: ("Thunderstorm, hail", "thunder"),
}

CACHE_DIR = os.path.expanduser("~/.cache")
GEO_CACHE = os.path.join(CACHE_DIR, "weather-geocode.json")
LAST_CACHE = os.path.join(CACHE_DIR, "wttrbar-last.json")


def parse_args(argv):
    opts = {"location": None, "nerd": False, "fahrenheit": False,
            "custom_indicator": None, "main_indicator": "weatherDesc"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--nerd":
            opts["nerd"] = True
        elif a == "--fahrenheit":
            opts["fahrenheit"] = True
        elif a in ("--location", "--loc") and i + 1 < len(argv):
            opts["location"] = argv[i + 1]; i += 1
        elif a.startswith("--location="):
            opts["location"] = a.split("=", 1)[1]
        elif a in ("--custom-indicator", "--custom-indicator-text") and i + 1 < len(argv):
            try:
                opts["custom_indicator"] = json.loads(argv[i + 1])
            except ValueError:
                pass
            i += 1
        elif a == "--main-indicator" and i + 1 < len(argv):
            opts["main_indicator"] = argv[i + 1]; i += 1
        i += 1
    return opts


def icon_for(keyword):
    k = keyword.lower()
    for key, glyph in NERD_ICONS:
        if key in k:
            return glyph
    return FALLBACK_ICON


def _get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "wttrbar-shim"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def _read_cache(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _write_cache(path, obj):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f)
    except Exception:
        pass


def resolve_location(opts):
    """Return (lat, lon, label). Accepts 'lat,lon' or a city name (geocoded)."""
    loc = opts["location"] or os.environ.get("WEATHER_LOCATION")
    if not loc:
        try:
            with open(os.path.expanduser("~/.config/weather/location"),
                      encoding="utf-8") as f:
                loc = f.read().strip()
        except Exception:
            loc = ""
    loc = loc or "Stockholm"

    m = re.match(r"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$", loc)
    if m:
        return float(m.group(1)), float(m.group(2)), loc

    cache = _read_cache(GEO_CACHE)
    if loc in cache:
        c = cache[loc]
        return c[0], c[1], c[2]

    url = ("https://geocoding-api.open-meteo.com/v1/search?name="
           + urllib.parse.quote(loc) + "&count=1&language=en&format=json")
    res = _get_json(url)
    hit = (res.get("results") or [None])[0]
    if not hit:
        raise ValueError("no geocoding result for %r" % loc)
    label = hit.get("name", loc)
    if hit.get("country_code"):
        label = "%s, %s" % (label, hit["country_code"])
    lat, lon = hit["latitude"], hit["longitude"]
    cache[loc] = [lat, lon, label]
    _write_cache(GEO_CACHE, cache)
    return lat, lon, label


def main():
    opts = parse_args(sys.argv[1:])
    unit = "°F" if opts["fahrenheit"] else "°C"
    tunit = "fahrenheit" if opts["fahrenheit"] else "celsius"
    try:
        lat, lon, label = resolve_location(opts)
        url = ("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
               "&current=temperature_2m,apparent_temperature,weather_code"
               "&temperature_unit=%s&timezone=auto" % (lat, lon, tunit))
        cur = _get_json(url).get("current", {})
        code = int(cur.get("weather_code", -1))
        temp = round(cur.get("temperature_2m"))
        feels = round(cur.get("apparent_temperature"))
    except Exception:
        last = _read_cache(LAST_CACHE)
        if last.get("text"):
            print(json.dumps(last))
        else:
            print(json.dumps({"text": "", "alt": "", "tooltip": "weather unavailable"}))
        return

    desc, icon_key = WMO.get(code, ("Unknown", "cloudy"))
    glyph = icon_for(icon_key)
    if opts["custom_indicator"]:
        glyph = opts["custom_indicator"].get(desc, glyph)
    if not opts["nerd"]:
        glyph = ""  # non-nerd fonts would show a tofu box for the glyphs

    out = {
        "text": "%s %s%s" % (glyph, temp, unit),
        "alt": desc,
        "tooltip": "%s: %s%s (feels %s%s) — %s" % (desc, temp, unit, feels, unit, label),
    }
    print(json.dumps(out))
    _write_cache(LAST_CACHE, out)


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

# ----------------------------------------------------------------------------
# 8. NiriMod - GTK4 settings editor for niri (github.com/srinivasr/NiriMod)
# ----------------------------------------------------------------------------
# NiriMod graphically edits ~/.config/niri/config.kdl (validated through
# `niri validate`, comments preserved). Its install.sh builds a uv venv and
# drops a `nirimod` launcher + .desktop entry. We install its runtime deps via
# dnf first, then run install.sh with --skip-deps so it doesn't try to.
log "Installing NiriMod (niri settings editor)..."
if command -v nirimod >/dev/null 2>&1; then
  log "NiriMod already installed, skipping."
else
  # uv drives NiriMod's venv; try dnf, then the official installer, else warn.
  if ! command -v uv >/dev/null 2>&1; then
    sudo dnf install -y uv >/dev/null 2>&1 \
      || curl -fsSL https://astral.sh/uv/install.sh 2>/dev/null | sh >/dev/null 2>&1 \
      || warn "Could not install 'uv' - NiriMod's installer may fail; install uv manually then re-run."
  fi
  NIRIMOD_TMP="$(mktemp -d)"
  if git clone --depth 1 -q https://github.com/srinivasr/NiriMod.git "$NIRIMOD_TMP/NiriMod" 2>/dev/null; then
    # Run NiriMod's own installer non-interactively, skipping system deps (we
    # installed GTK4/libadwaita/PyGObject/Pycairo above). Pass the repo path as
    # the working dir; it installs into ~/.local.
    if ( cd "$NIRIMOD_TMP/NiriMod" && bash install.sh --install --skip-deps ) >/dev/null 2>&1; then
      log "NiriMod installed - launch with Mod+Shift+S (or run: nirimod)."
    else
      warn "NiriMod install.sh failed - install it manually: github.com/srinivasr/NiriMod (needs uv + GTK4/libadwaita)."
    fi
  else
    warn "git clone of NiriMod failed (network issue?) - install it later from github.com/srinivasr/NiriMod."
  fi
  rm -rf "$NIRIMOD_TMP"
fi

# ----------------------------------------------------------------------------
# 9. Base GTK theme + wallpaper seed
# ----------------------------------------------------------------------------
# Point GTK at the active rice theme if the generators produced one; otherwise
# leave the system default. Cosmetic, best-effort.
mkdir -p "$CONF/gtk-3.0" "$CONF/gtk-4.0" "$CONF/environment.d"
GTK_THEME_NAME="Rice-$(cat "$CONF/waybar/current-theme-name" 2>/dev/null | sed -e 's/-square$//' -e 's/-numbered$//' -e 's/-alt$//')"
if [ -d "$HOME/.themes/$GTK_THEME_NAME/gtk-3.0" ]; then
  printf '[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=Papirus-Dark\ngtk-cursor-theme-name=%s\n' \
    "$GTK_THEME_NAME" "$CURSOR_THEME_NAME" > "$CONF/gtk-3.0/settings.ini"
  printf '[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=Papirus-Dark\ngtk-cursor-theme-name=%s\n' \
    "$GTK_THEME_NAME" "$CURSOR_THEME_NAME" > "$CONF/gtk-4.0/settings.ini"
  printf 'GTK_THEME=%s\n' "$GTK_THEME_NAME" > "$CONF/environment.d/gtk-theme.conf"
  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" 2>/dev/null || true
fi
printf 'XCURSOR_THEME=%s\n' "$CURSOR_THEME_NAME" > "$CONF/environment.d/cursor-theme.conf"

# A solid Catppuccin-base wallpaper so swaybg has something to show on first
# login; press Mod+Shift+W any time to pick a real image.
if [ ! -f "$CONF/niri/wallpaper.png" ] && command -v magick >/dev/null 2>&1; then
  magick -size 1920x1080 xc:'#1e1e2e' "$CONF/niri/wallpaper.png" 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# 9b. Screensaver dependency (Terminal Text Effects) via pipx
# ----------------------------------------------------------------------------
if command -v pipx >/dev/null 2>&1; then
  pipx install terminaltexteffects >/dev/null 2>&1 \
    || warn "pipx install terminaltexteffects failed - the screensaver (Mod+Escape / before an idle lock) won't animate until you run it manually."
else
  warn "pipx not found - skipping the screensaver's tte dependency."
fi

# ----------------------------------------------------------------------------
# 9c. Disable redundant tray applets' autostart + evolution's own alarm popup
# ----------------------------------------------------------------------------
# nm-applet/blueman ship their own /etc/xdg/autostart entries; dex-autostart
# (run at niri startup) would relaunch them, re-adding tray icons waybar's own
# widgets already replace. Per-user Hidden=true overrides suppress them.
mkdir -p "$CONF/autostart"
for entry in nm-applet blueman; do
  cat > "$CONF/autostart/$entry.desktop" <<EOF
[Desktop Entry]
Name=$entry
Exec=$entry
Type=Application
Hidden=true
EOF
done
# evolution-alarm-notify's own GTK reminder popup is replaced by
# calendar-reminder-daemon.py (themed dunst notifications). It is D-Bus
# activatable, so masking the user unit is needed in addition to Hidden=true.
cat > "$CONF/autostart/org.gnome.Evolution-alarm-notify.desktop" <<EOF
[Desktop Entry]
Name=Evolution Alarm Notify
Exec=evolution-alarm-notify
Type=Application
Hidden=true
EOF
systemctl --user mask evolution-alarm-notify.service >/dev/null 2>&1 || true

# ----------------------------------------------------------------------------
# 9d. Qogir cursor theme (6 variants) - cursor-theme.sh switches between them
# ----------------------------------------------------------------------------
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
      rm -rf "$qdest"; mkdir -p "$qdest"
      cp "$QOGIR_TMPDIR/COPYING" "$QOGIR_TMPDIR/AUTHORS" "$qdest/" 2>/dev/null || true
      cp -r "$QOGIR_TMPDIR/src/cursors/dist${QOGIR_THEME_SUFFIXES[$i]}${QOGIR_COLOR_SUFFIXES[$i]}/cursors" "$qdest/"
      printf '[Icon Theme]\nName=%s\n' "$qname" > "$qdest/index.theme"
    done
  else
    warn "Qogir cursor download failed - the pointer falls back to the configured default; install manually from github.com/vinceliuice/Qogir-icon-theme."
  fi
  rm -rf "$QOGIR_TMPDIR"
else
  log "Qogir cursor theme already present, skipping."
fi
# Legacy ~/.icons path (libxcb-cursor only checks there) + Xresources, so
# XWayland/XCB apps resolve the pointer too.
mkdir -p "$HOME/.icons"
for qvariant in Qogir Qogir-Dark Qogir-Manjaro Qogir-Manjaro-Dark Qogir-Ubuntu Qogir-Ubuntu-Dark; do
  [ -d "$HOME/.local/share/icons/$qvariant" ] && ln -sfn "$HOME/.local/share/icons/$qvariant" "$HOME/.icons/$qvariant"
done
cat > "$HOME/.Xresources" <<EOF
Xcursor.theme: $CURSOR_THEME_NAME
Xcursor.size: 24
EOF
# GTK2 apps (rare, not extinct) - a separate file from gtk-3/4 settings.
if [ ! -f "$HOME/.gtkrc-2.0" ]; then
  printf 'gtk-theme-name="%s"\ngtk-icon-theme-name="Papirus-Dark"\ngtk-font-name="Sans 10"\n' \
    "$GTK_THEME_NAME" > "$HOME/.gtkrc-2.0"
fi

# ----------------------------------------------------------------------------
# 9e. CLIamp (terminal music player) - Mod+M
# ----------------------------------------------------------------------------
if ! command -v cliamp >/dev/null 2>&1; then
  log "Installing CLIamp (terminal music player)..."
  if curl -fsSL https://cliamp.stream/install.sh | sh >/dev/null 2>&1 \
      && command -v cliamp >/dev/null 2>&1; then
    log "CLIamp installed - summon with Mod+M."
  else
    warn "CLIamp install failed (network issue) - install manually from cliamp.stream if you want it."
  fi
else
  log "CLIamp already installed, skipping."
fi

# ----------------------------------------------------------------------------
# 9f. Strata (GTK4 file manager, Mod+E) - github.com/lgse/strata
# ----------------------------------------------------------------------------
if command -v strata >/dev/null 2>&1; then
  log "Strata already installed, skipping."
else
  log "Installing Strata (GTK4 file manager)..."
  sudo dnf install -y \
    gtk4 gtksourceview5 poppler-glib bubblewrap gvfs \
    gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugin-libav \
    ffmpeg-free ffmpegthumbnailer LibRaw \
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
      mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" \
        "$HOME/.local/share/icons/hicolor/scalable/apps"
      install -Dm755 "$__strata_src/strata" "$HOME/.local/bin/strata"
      sed "s|^Exec=.*|Exec=$HOME/.local/bin/strata %U|" \
        "$__strata_src/io.github.lgse.Strata.desktop" \
        > "$HOME/.local/share/applications/io.github.lgse.Strata.desktop"
      install -Dm644 "$__strata_src/io.github.lgse.Strata.svg" \
        "$HOME/.local/share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg"
      update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
      gtk-update-icon-cache -qtf "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
      command -v strata >/dev/null 2>&1 && { log "Strata installed."; __strata_ok=1; }
    fi
    rm -rf "$__strata_dir"
  fi
  [ -n "$__strata_ok" ] || warn "Strata install failed (network/checksum) - install manually from github.com/lgse/strata/releases."
fi
if command -v strata >/dev/null 2>&1; then
  xdg-mime default io.github.lgse.Strata.desktop inode/directory 2>/dev/null || true
  xdg-mime default io.github.lgse.Strata.desktop inode/mount-point 2>/dev/null || true
  mkdir -p "$HOME/.local/share/dbus-1/services"
  cat > "$HOME/.local/share/dbus-1/services/org.freedesktop.FileManager1.service" <<STRATA_DBUS_EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=$HOME/.local/bin/strata --gapplication-service
STRATA_DBUS_EOF
fi

# ----------------------------------------------------------------------------
# 9g. Audio: pin the Jabra Link 380 to its analog profile (harmless if absent)
# ----------------------------------------------------------------------------
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
systemctl --user is-active --quiet wireplumber 2>/dev/null \
  && systemctl --user restart wireplumber 2>/dev/null || true

# ----------------------------------------------------------------------------
# 9h. HP printer plugin check (best-effort - only if an HP device is present)
# ----------------------------------------------------------------------------
if command -v hp-plugin >/dev/null 2>&1 \
    && (lpinfo -v 2>/dev/null | grep -qi "hp\|hewlett" || lsusb 2>/dev/null | grep -qi "03f0"); then
  if grep -qx "installed = 1" /var/lib/hp/hplip.state 2>/dev/null; then
    log "HP proprietary plugin already installed."
  else
    log "HP printer detected - running hp-plugin (accept the prompts)..."
    hp-plugin -i || warn "hp-plugin failed/cancelled - re-run 'hp-plugin -i' if print jobs silently stall."
  fi
fi

# ----------------------------------------------------------------------------
# 9i. GTK / Neovim / VS Code themes matching every installed bar theme
# ----------------------------------------------------------------------------
# hancore-theme-gen.py wrote a [colors] ini per theme into
# ~/.config/polybar/themes/ (heritage path, load-bearing); rice-gen-driver.py
# feeds those to the repo's generate-{gtk,nvim,vscode}-themes.py. Best-effort:
# only works when run from a clone of this repo (the generators live at its
# root); a missing repo dir just warns.
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
if [ -s "$RICEGEN_TMP/rice-gen-driver.py" ] \
   && python3 -I "$RICEGEN_TMP/rice-gen-driver.py" "$REPO_DIR" >/dev/null 2>&1; then
  log "Matching GTK (Rice-*), Neovim (rice-*) and VS Code themes generated."
else
  warn "GTK/Neovim/VS Code theme generation skipped/failed (run from a repo clone to enable it): python3 sway-build/rice-gen-driver.py \"$REPO_DIR\""
fi
rm -rf "$RICEGEN_TMP"

# ----------------------------------------------------------------------------
# 10. Done
# ----------------------------------------------------------------------------
log "Done."
printf '\n'
log "Log out and pick \"niri\" from your display manager's session list, or run"
log "  niri-session   (from a TTY)   to start it."
printf '\n'
log "Keys: Mod=Super. Mod+Return terminal, Mod+Space launcher, Mod+Q close,"
log "      Mod+1..9 workspaces, Mod+H/L columns, Mod+J/K windows, Mod+R width,"
log "      Mod+Tab overview, Print screenshot, Mod+Alt+L lock,"
log "      Mod+Shift+S NiriMod (settings), Mod+Shift+/ keybind cheat-sheet."
log "Theme switcher: run ~/.local/bin/waybar-theme.sh (bind it or run from a term)."
