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
#           systray, switchable via the app menu between 21 complete
#           themes - Catppuccin Mocha's own segmented powerline pills,
#           flat Dracula/grouped-island Nord reskins modeled on those
#           projects' real i3 setups, a rounded-capsule Archcraft reskin
#           modeled on archcraft-i3wm's real polybar config, 16 more
#           reskins ported from rices in gh0stzk/dotfiles (a real
#           18-theme bspwm collection), and a hidrot reskin ported from
#           Murzchnvok/polybar-collection - each a full
#           color+layout+module-styling package, not just a palette swap),
#           plus a square "-square" counterpart for every one of those 21
#           (42 total) with every rounded bar corner, pill end-cap, and
#           rofi window/element corner squared off - same colors and
#           layout, zero curves,
#           CLIamp terminal music player (Mod+m), an
#           Omarchy-style app menu (Mod+alt+space) for this rice's own
#           utility scripts (including a floating on-screen keybinding
#           cheat sheet), + always-visible window borders and tightened
#           gaps.
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
  jetbrains-mono-fonts \
  plymouth-plugin-script

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
# 2b. Plymouth boot theme (Catppuccin Mocha) - themes the LUKS decrypt prompt
#     and boot splash, not just the desktop session. Built in the style of
#     Omarchy's own Plymouth theme (github.com/basecamp/omarchy, MIT) rather
#     than a plain colored splash: a big pixel-art wordmark, a lock icon +
#     bordered password-entry box with a dot per keystroke, and a fake-
#     progress bar that eases toward ~70% during LUKS decryption (which
#     reports no real progress of its own) before real boot progress takes
#     over - all driven by Plymouth's "script" module (plymouth-plugin-
#     script, added to the dnf list above), not the simpler "two-step"
#     module Fedora's own stock themes use.
#
#     Omarchy's actual template assets (bullet/entry/lock/progress bar+box
#     images, and its .script animation logic) are reused verbatim below -
#     MIT-licensed, so a permitted, credited reuse - but NOT its "OMARCHY"
#     wordmark or its font: that font's glyph set only covers the letters
#     in the word "omarchy" and nothing else (confirmed by inspecting its
#     cmap table), so it can't render anything else. The wordmark here is
#     generated fresh instead - JetBrainsMono ExtraBold rendered small,
#     alpha-thresholded to kill anti-aliasing, then upscaled with nearest-
#     neighbor - the same hard-pixel-edge technique Omarchy's own font
#     produces, applied to different text in a different font so nothing
#     is copied, only the *look*. Every UI element (bullet/entry/lock/
#     progress bar) is recolored to this rice's Mocha text color (#cdd6f4)
#     via ImageMagick, exactly how Omarchy's own theme-switcher does it;
#     the background is Mocha base (#1e1e2e). All assets are embedded
#     below as base64 (a few KB total) rather than downloaded at setup
#     time - there's no upstream release to track the way the Nerd Font
#     download has, so there's nothing to fetch over the network here.
#
#     To revert to the stock boot splash later:
#       sudo plymouth-set-default-theme -R bgrt
# ----------------------------------------------------------------------------
if [ ! -d /usr/share/plymouth/themes/catppuccin-mocha ]; then
  log "Installing Catppuccin Mocha Plymouth (boot splash / LUKS prompt) theme..."
  TMPPLYMOUTH="$(mktemp -d)"

  cat > "$TMPPLYMOUTH/catppuccin-mocha.plymouth" <<'PLYMOUTHEOF'
[Plymouth Theme]
Name=catppuccin-mocha
Description=Catppuccin Mocha splash screen with an animated password entry, in the style of Omarchy's own boot theme.
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/catppuccin-mocha
ScriptFile=/usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.script
ConsoleLogBackgroundColor=0x1e1e2e
MonospaceFont=Noto Sans 11
Font=Noto Sans 11
PLYMOUTHEOF

  cat > "$TMPPLYMOUTH/catppuccin-mocha.script" <<'SCRIPTEOF'
# Omarchy Plymouth Theme Script

Window.SetBackgroundTopColor(0.118, 0.118, 0.180);
Window.SetBackgroundBottomColor(0.118, 0.118, 0.180);

logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2);
logo.sprite.SetOpacity(1);

# Use these to adjust the progress bar timing
global.fake_progress_limit = 0.7;  # Target percentage for fake progress (0.0 to 1.0)
global.fake_progress_duration = 15.0;  # Duration in seconds to reach limit

# Progress bar animation variables
global.animation_frame = 0;
global.fake_progress = 0.0;
global.real_progress = 0.0;
global.fake_progress_active = 0;
global.fake_progress_start_time = 0.0;  # Track when fake progress started
global.password_shown = 0;  # Track if password dialog has been shown
global.max_progress = 0.0;  # Track the maximum progress reached to prevent backwards movement

fun refresh_callback() {
  global.animation_frame++;

  # Animate fake progress to limit over time with easing
  if (global.fake_progress_active == 1) {
    # Calculate elapsed time since start
    elapsed_time = global.animation_frame / 50.0;  # Convert frames to seconds (50 FPS)

    # Calculate linear progress ratio (0 to 1) based on time
    time_ratio = elapsed_time / global.fake_progress_duration;
    if (time_ratio > 1.0) time_ratio = 1.0;

    # Apply easing curve: ease-out quadratic
    # Formula: 1 - (1 - x)^2
    eased_ratio = 1 - ((1 - time_ratio) * (1 - time_ratio));

    # Calculate fake progress based on eased ratio
    global.fake_progress = eased_ratio * global.fake_progress_limit;

    # Update progress bar with fake progress
    update_progress_bar(global.fake_progress);
  }
}

Plymouth.SetRefreshFunction(refresh_callback);

#----------------------------------------- Helper Functions --------------------------------

fun update_progress_bar(progress) {
  # Only update if progress is moving forward
  if (progress > global.max_progress) {
    global.max_progress = progress;

    width = Math.Int(progress_bar.original_image.GetWidth() * progress);
    if (width < 1) width = 1;  # Ensure minimum width of 1 pixel

    progress_bar.image = progress_bar.original_image.Scale(width, progress_bar.original_image.GetHeight());
    progress_bar.sprite.SetImage(progress_bar.image);
  }
}

fun show_progress_bar() {
  progress_box.sprite.SetOpacity(1);
  progress_bar.sprite.SetOpacity(1);
}

fun hide_progress_bar() {
  progress_box.sprite.SetOpacity(0);
  progress_bar.sprite.SetOpacity(0);
}

fun show_password_dialog() {
  lock.sprite.SetOpacity(1);
  entry.sprite.SetOpacity(1);
}

fun hide_password_dialog() {
  lock.sprite.SetOpacity(0);
  entry.sprite.SetOpacity(0);

  for (index = 0; bullet.sprites[index]; index++) {
    bullet.sprites[index].SetOpacity(0);
  }
}

fun start_fake_progress() {
  global.fake_progress_active = 1;

  # Reset fake progress
  global.animation_frame = 0;
  global.max_progress = 0.0;
  global.fake_progress = 0.0;
  global.fake_progress_start_time = 0.0;
}

fun stop_fake_progress() {
  global.fake_progress_active = 0;
}

#----------------------------------------- Dialogue --------------------------------

lock.image = Image("lock.png");
entry.image = Image("entry.png");
bullet.image = Image("bullet.png");

entry.sprite = Sprite(entry.image);
entry.x = Window.GetWidth() / 2 - entry.image.GetWidth() / 2;
entry.y = logo.sprite.GetY() + logo.image.GetHeight() + 40;
entry.sprite.SetPosition(entry.x, entry.y, 10001);
entry.sprite.SetOpacity(0);

# Scale lock to be slightly shorter than entry field height
# Original lock is 84x96, entry height determines scale
lock_height = entry.image.GetHeight() * 0.8;
lock_scale = lock_height / 96;
lock_width = 84 * lock_scale;

scaled_lock = lock.image.Scale(lock_width, lock_height);
lock.sprite = Sprite(scaled_lock);
lock.x = entry.x - lock_width - 15;
lock.y = entry.y + entry.image.GetHeight() / 2 - lock_height / 2;
lock.sprite.SetPosition(lock.x, lock.y, 10001);
lock.sprite.SetOpacity(0);

# Bullet array
bullet.sprites = [];

fun display_normal_callback() {
  hide_password_dialog();

  # Get current mode
  mode = Plymouth.GetMode();

  # Only show progress bar for boot and resume modes
  if ((mode == "boot" || mode == "resume") && global.password_shown == 1) {
    show_progress_bar();
    start_fake_progress();
  }
}

fun display_password_callback(prompt, bullets) {
  global.password_shown = 1;  # Mark that password dialog has been shown

  # Stop fake progress when password dialog appears
  stop_fake_progress();
  hide_progress_bar();
  show_password_dialog();

  # Clear all bullets first
  for (index = 0; bullet.sprites[index]; index++) {
    bullet.sprites[index].SetOpacity(0);
  }

  # Create and show bullets for current password (max 21)
  max_bullets = 21;
  bullets_to_show = bullets;
  if (bullets_to_show > max_bullets) {
    bullets_to_show = max_bullets;
  }

  for (index = 0; index < bullets_to_show; index++) {
    if (!bullet.sprites[index]) {
      # Scale bullet image to 7x7 pixels
      scaled_bullet = bullet.image.Scale(7, 7);
      bullet.sprites[index] = Sprite(scaled_bullet);
      bullet.x = entry.x + 20 + index * (7 + 5);
      bullet.y = entry.y + entry.image.GetHeight() / 2 - 3.5;
      bullet.sprites[index].SetPosition(bullet.x, bullet.y, 10002);
    }

    bullet.sprites[index].SetOpacity(1);
  }
}

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);

#----------------------------------------- Progress Bar --------------------------------

progress_box.image = Image("progress_box.png");
progress_box.sprite = Sprite(progress_box.image);

progress_box.x = Window.GetWidth() / 2 - progress_box.image.GetWidth() / 2;
progress_box.y = entry.y + entry.image.GetHeight() / 2 - progress_box.image.GetHeight() / 2;
progress_box.sprite.SetPosition(progress_box.x, progress_box.y, 0);
progress_box.sprite.SetOpacity(0);

progress_bar.original_image = Image("progress_bar.png");
progress_bar.sprite = Sprite();
progress_bar.image = progress_bar.original_image.Scale(1, progress_bar.original_image.GetHeight());

progress_bar.x = Window.GetWidth() / 2 - progress_bar.original_image.GetWidth() / 2;
progress_bar.y = progress_box.y + (progress_box.image.GetHeight() - progress_bar.original_image.GetHeight()) / 2;
progress_bar.sprite.SetPosition(progress_bar.x, progress_bar.y, 1);
progress_bar.sprite.SetOpacity(0);

fun progress_callback(duration, progress) {
  # Track when fake progress starts
  # Needed because duration and progress freeze during drive decryption
  if (global.fake_progress_start_time == 0.0) {
    global.fake_progress_start_time = duration;
  }

  global.real_progress = progress;

  # Use real progress once its unfrozen and exceeds fake progress
  if (duration > global.fake_progress_start_time && progress > global.fake_progress) {
    stop_fake_progress();
    update_progress_bar(progress);
  }
}

Plymouth.SetBootProgressFunction(progress_callback);

#----------------------------------------- Message --------------------------------

message_sprite = Sprite();
message_sprite.SetPosition(10, 10, 10000);

fun display_message_callback(text) {
  message = Image.Text(text, 1, 1, 1);
  message_sprite.SetImage(message);
  message_sprite.SetOpacity(1);
}

fun hide_message_callback(text) {
  message_sprite.SetOpacity(0);
}

Plymouth.SetDisplayMessageFunction(display_message_callback);
Plymouth.SetHideMessageFunction(hide_message_callback);
SCRIPTEOF

  base64 -d > "$TMPPLYMOUTH/bullet.png" <<'B64EOF'
iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOBAMAAADtZjDiAAAAIGNIUk0AAHomAACAhAAA+gAAAIDo
AAB1MAAA6mAAADqYAAAXcJy6UTwAAAAkUExURc3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W
9M3W9P///1tQ9skAAAAKdFJOUwAaiNX5WvL+1Pi2UgdyAAAAAWJLR0QLH9fEwAAAAAd0SU1FB+oJ
BAwZKrDY/sgAAAAldEVYdGRhdGU6Y3JlYXRlADIwMjYtMDktMDRUMTI6MjM6NTQrMDA6MDCGuJGg
AAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI2LTA5LTA0VDEyOjIzOjU0KzAwOjAw9+UpHAAAACh0RVh0
ZGF0ZTp0aW1lc3RhbXAAMjAyNi0wOS0wNFQxMjoyNTo0MiswMDowMAKUTSAAAABDSURBVAjXY2Bg
VHYxEmBgYAhbtWpVKgMDa9WqVauWBzCIrQKBRAYtML2IoQtMr2DwAtMrofQSuDhMHUwfzByYuVB7
AECVLwrIOLMnAAAAAElFTkSuQmCC
B64EOF

  base64 -d > "$TMPPLYMOUTH/entry.png" <<'B64EOF'
iVBORw0KGgoAAAANSUhEUgAAAR4AAAAwBAMAAAA1NggXAAAAIGNIUk0AAHomAACAhAAA+gAAAIDo
AAB1MAAA6mAAADqYAAAXcJy6UTwAAAAPUExURc3W9M3W9M3W9M3W9P///zoVMFEAAAADdFJOUyiV
Db6v0WQAAAABYktHRASPaNlRAAAAB3RJTUUH6gkEDBkqsNj+yAAAACV0RVh0ZGF0ZTpjcmVhdGUA
MjAyNi0wOS0wNFQxMjoyMzo1NCswMDowMIa4kaAAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMDkt
MDRUMTI6MjM6NTQrMDA6MDD35SkcAAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTA5LTA0VDEy
OjI1OjQyKzAwOjAwApRNIAAAAFxJREFUWMPt2UEVgDAMRMHgAIgCcNBX/956pgJIDrMK5u31x3F1
2hk5O21EVl/y2Yi83z57eHh4eHh4eHh4eHh4eHgajIeHh4eHh4fnD091Ith7QXVC2XpKs960AMBz
eeQ4rySWAAAAAElFTkSuQmCC
B64EOF

  base64 -d > "$TMPPLYMOUTH/lock.png" <<'B64EOF'
iVBORw0KGgoAAAANSUhEUgAAAFQAAABgCAMAAAC0XqVIAAAAIGNIUk0AAHomAACAhAAA+gAAAIDo
AAB1MAAA6mAAADqYAAAXcJy6UTwAAAFNUExURc3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W
9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W
9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W
9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W
9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W
9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W9M3W
9M3W9M3W9M3W9M3W9M3W9P///wWUAcQAAABtdFJOUwACLlqAnq+7C12s7Sic9CGo/gZ798pF71f6
RyPyB82FrnlVRMRRteFMMbIRq50DFPtr3A3AQgj4t0FAb+IBlZm5YcU70SrgIF6m1PAKg93z8QTP
aN46lgzqNvw5okgeECRWZstuQ7ifKclNsBIPqNYOAAAAAWJLR0RuIg9RFwAAAAlwSFlzAAALEwAA
CxMBAJqcGAAAAAd0SU1FB+oJBAwZKrDY/sgAAAAldEVYdGRhdGU6Y3JlYXRlADIwMjYtMDktMDRU
MTI6MjM6NTQrMDA6MDCGuJGgAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI2LTA5LTA0VDEyOjIzOjU0
KzAwOjAw9+UpHAAAACh0RVh0ZGF0ZTp0aW1lc3RhbXAAMjAyNi0wOS0wNFQxMjoyNTo0MiswMDow
MAKUTSAAAAKeSURBVFjD7dhXV/JAEIDhVVQsWAARUVTsYkEFbETsKBi7Yu8FFJj/f+sRlUyAZBeY
m88vc8ub5+QEzK7LGH+qqk01tXVmc11tjam6SuAC7tQ3NDYBmqbGhvoKSUtzCxRMS7OlArK1zQpF
x9rWWiZps7eD5rTbbWXdpgN0x1HGzXY4gTPOjlLNThfPBHB1lmaarHwTwGoqxewSuM/svXaJm91u
MRPA3S1q9vSKmgC9PYJoX+EX7ekfGBwc6PcU/iT6xExL/gMdGs790G3DQ/mPVexPdkR91eiY+uOx
UfXnIyKmV33N+ER+MDGuLrwC6KTqiilfYeGbUiWTfHN6Bl/g8RVrfB7czExz0Vnc+wPFo4AfV7Nc
NIjzOa1qDldBnjm/gOpF7W4RZQvzHHQJ30JIuwvhbomDSqhdDmt34WUUShx0BbWreuEqClc46Bpq
1/XCdRSucdAN1G7qhZso3OCgW6iN6IURFG5x0G3U7uiFOyjcNlAD/YfRQDS265RlGe+h3LLO4E2M
VZZl524sql4n9vZlIBh5f08xvQcU5Ncc5Nbr0CGVCXD4s1pYjuhMgKPsNuj4hNIEODlmjJ3SmgCn
jIXPqNGzMItTmwBxZqdH7SxGj8aYmR41qzdkNBM00L+Fus7jFxfxc7H/gwXRy6vvt+TVJR16ffP7
Pr+5JkNvlZXnlgy9U9A7MvReQe/J0AcFfTBQAzXQ/wd9VNBHMvRJQZ/IULOCiuySBNeo6K8ZFakF
Uddz9uAn/Cy0nAqv+y+vb2+vL2Lt39uhGGgpaIIeTbAkPZpUHZgSjcTe6dF3xj6ozQ/GWIoaTX29
e9K0Zjr7jsz4Cajc+DM/51aEqj93QpYhewLpDDrtSjkIRHCk8s7lIlIyEaxgEkkpdzD+CVjoSax0
GuV9AAAAAElFTkSuQmCC
B64EOF

  base64 -d > "$TMPPLYMOUTH/logo.png" <<'B64EOF'
iVBORw0KGgoAAAANSUhEUgAAAxAAAACoCAYAAABwiAh4AAAFA0lEQVR4nO3dwW3cMBBA0TjIxQWl
mRToZlyQj845AbL6iCwMuXqvAFteci18EOC8fAOAJ/T+9vF55c//+ev15cqfD7Cq79MPAAAA7ENA
AAAAmYAAAAAyAQEAAGQCAgAAyAQEAACQCQgAACB7ufqebM6Zvmfc/lib/bG36fWbdvf98+zrf/f1
PevZ98fVdt9/q6+/EwgAACATEAAAQCYgAACATEAAAACZgAAAADIBAQAAZAICAADIfkw/AMBdnb2n
fPV7wne/h/1qz77+nGN/3NvR+k+vrxMIAAAgExAAAEAmIAAAgExAAAAAmYAAAAAyAQEAAGQCAgAA
yMyBAAB4MqvPEWBvTiAAAIBMQAAAAJmAAAAAMgEBAABkAgIAAMgEBAAAkAkIAAAgW34OhHuK7836
88jV++PoHvVp0/e8r/75PPvfP73+q5v++6f3B1zJCQQAAJAJCAAAIBMQAABAJiAAAIBMQAAAAJmA
AAAAMgEBAABk43Mgpu9pBviXs/+f3AN/ren3x9Hvt/73Zn9cy+c3ywkEAACQCQgAACATEAAAQCYg
AACATEAAAACZgAAAADIBAQAAZONzIAAAYCd3n/PhBAIAAMgEBAAAkAkIAAAgExAAAEAmIAAAgExA
AAAAmYAAAAAycyAAAGAjR3MmjuZUnOUEAgAAyAQEAACQCQgAACATEAAAQCYgAACATEAAAACZgAAA
ADIBAQAAZAICAADIBAQAAJAJCAAAIBMQAABAJiAAAIBMQAAAAJmAAAAAsh/TD/D+9vE5/QyTfv56
fZl+hpXZH/YHwIru/n56dt6/jzmBAAAAMgEBAABkAgIAAMgEBAAAkAkIAAAgExAAAEAmIAAAgGx8
DgQAwFe7+5yG3ecY7L5+R5//7n+fEwgAACATEAAAQCYgAACATEAAAACZgAAAADIBAQAAZAICAADI
zIEAAIAncjRn4uycECcQAABAJiAAAIBMQAAAAJmAAAAAMgEBAABkAgIAAMgEBAAAkJkDwdbO3mMM
ACvyfmNlTiAAAIBMQAAAAJmAAAAAMgEBAABkAgIAAMgEBAAAkAkIAAAgG58D4Z5jHrE/APgfZ98f
728fn1/3NOzG+j/mBAIAAMgEBAAAkAkIAAAgExAAAEAmIAAAgExAAAAAmYAAAACy8TkQAAD86WgO
we5zksxZ2JsTCAAAIBMQAABAJiAAAIBMQAAAAJmAAAAAMgEBAABkAgIAAMjMgQAA+MvRnAVzDNjZ
2TkjTiAAAIBMQAAAAJmAAAAAMgEBAABkAgIAAMgEBAAAkAkIAAAgMwcC4D+5Bx6YcvYe/7tb/fNZ
/f3iBAIAAMgEBAAAkAkIAAAgExAAAEAmIAAAgExAAAAAmYAAAAAycyBY2ur3IE9b/R7rq9kf93Z2
/Y++P/YXj9g/3JkTCAAAIBMQAABAJiAAAIBMQAAAAJmAAAAAMgEBAABkAgIAAMjMgQDY1PQckN3v
wV/9+Y5Mrz9rO9rfV++f3b9fPOYEAgAAyAQEAACQCQgAACATEAAAQCYgAACATEAAAACZgAAAADJz
IAAWtfs9/7vPiZi2+/rfnf0/y/fnnKP96QQCAADIBAQAAJAJCAAAIBMQAABAJiAAAIBMQAAAAJmA
AAAAMnMgAC7iHvLH7n5Pvv3BpKPvl/05a/X/j04gAACATEAAAACZgAAAADIBAQAAZAICAADIBAQA
AJAJCAAAIPsNkKzjPs4xlakAAAAASUVORK5CYII=
B64EOF

  base64 -d > "$TMPPLYMOUTH/progress_bar.png" <<'B64EOF'
iVBORw0KGgoAAAANSUhEUgAAASwAAAAKAQMAAAA0MfGpAAAAIGNIUk0AAHomAACAhAAA+gAAAIDo
AAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGUExURc3W9P///wcemb4AAAABYktHRAH/Ai3eAAAAB3RJ
TUUH6gkEDBkqsNj+yAAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0wOS0wNFQxMjoyMzo1NCswMDow
MIa4kaAAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMDktMDRUMTI6MjM6NTQrMDA6MDD35SkcAAAA
KHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTA5LTA0VDEyOjI1OjQyKzAwOjAwApRNIAAAAA1JREFU
GNNjYBgFAw8AAYYAASpFXpwAAAAASUVORK5CYII=
B64EOF

  base64 -d > "$TMPPLYMOUTH/progress_box.png" <<'B64EOF'
iVBORw0KGgoAAAANSUhEUgAAASwAAAAKAQMAAAA0MfGpAAAAIGNIUk0AAHomAACAhAAA+gAAAIDo
AAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGUExURSkuQv///8qWyvAAAAABYktHRAH/Ai3eAAAAB3RJ
TUUH6QcEFy0fdJZJQgAAAA1JREFUGNNjYBgFAw8AAYYAASpFXpwAAAAldEVYdGRhdGU6Y3JlYXRl
ADIwMjUtMDctMDRUMjM6NDU6MzErMDA6MDD7tkoMAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI1LTA3
LTA0VDIzOjQ1OjMxKzAwOjAwiuvysAAAACh0RVh0ZGF0ZTp0aW1lc3RhbXAAMjAyNS0wNy0wNFQy
Mzo0NTozMSswMDowMN3+028AAAAASUVORK5CYII=
B64EOF

  if sudo cp -r "$TMPPLYMOUTH" /usr/share/plymouth/themes/catppuccin-mocha \
      && sudo plymouth-set-default-theme -R catppuccin-mocha; then
    log "Plymouth theme set to catppuccin-mocha (reboot to see it on the LUKS decrypt screen)."
  else
    warn "Plymouth theme install/activation failed; boot splash left on its current theme. Revert/retry manually: sudo plymouth-set-default-theme -R bgrt"
  fi
  rm -rf "$TMPPLYMOUTH"
else
  log "Catppuccin Mocha Plymouth theme already installed, skipping."
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
for_window [class="^Cliamp$"] floating enable, resize set 700 500, move position center
for_window [class="^AppMenuTask$"] floating enable, resize set 600 400, move position center
for_window [class="^KeybindingsHelp$"] floating enable, resize set 950 850, move position center
for_window [class="^Evolution-alarm-notify$"] floating enable, resize set 450 350, move position center
for_window [class="^gnome-calendar$"] floating enable, resize set 700 550, move position center
for_window [class="^System-config-printer\.py$"] floating enable, resize set 750 550, move position center
for_window [class="^Screensaver$"] fullscreen enable

# --- launch ---
bindsym $mod+Return exec kitty
bindsym $mod+space exec rofi -show drun -theme ~/.config/rofi/current.rasi
bindsym $mod+shift+space exec rofi -show run -theme ~/.config/rofi/current.rasi
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

# --- music (cliamp, https://www.cliamp.stream/) ---
bindsym $mod+m exec --no-startup-id kitty --class Cliamp -e cliamp

# --- app menu (Omarchy-style: reach this rice's utility scripts in one place) ---
# "Mod1" here, not "alt" - the latter parses without error (i3 -C stays
# silent) but produces a dead grab that never fires on this i3 build,
# confirmed via `i3-msg -t subscribe -m '["binding"]'` showing zero events
# for any alt-based bindsym while Mod1-based ones fire correctly. Every
# other modifier in this file (shift/ctrl/mod4) works fine as a bare word -
# it's specifically "alt" as a modifier name that's the trap.
bindsym $mod+Mod1+space exec --no-startup-id ~/.local/bin/app-menu.sh

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

# --- AI assistant key ---
# This laptop's dedicated assistant key doesn't send a bare XF86Assistant -
# confirmed via `xev`, it fires Super_L+Shift_L+XF86Assistant together as
# one burst every time, so the modifiers here have to match that exactly
# rather than binding XF86Assistant alone (which would require it to be
# pressed with no modifiers held, which this hardware never actually does).
bindsym $mod+shift+XF86Assistant exec --no-startup-id claude-desktop-unofficial

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
bindsym $mod+shift+f floating toggle
bindsym $mod+ctrl+space focus mode_toggle

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
# window_type = 'menu' here fixes a third variant of the same underlying
# problem as rounded-corners-exclude/blur-background-exclude below: picom's
# own synthetic shadow doesn't line up with a Chrome/Edge context menu's
# real shape, leaving a visible gap - not a solid halo, but a shadow
# gradient that fades, jumps back to the page's own plain background for a
# few pixels, then only THEN reaches the menu's actual edge. Confirmed via
# pixel-sampling a straight (non-corner) edge of a live menu screenshot,
# which is what told shadow apart from blur/corner-radius here - all three
# effects produce a visually similar "border" but with different pixel
# signatures, and this rule was the one of the three that had never been
# extended to cover menus at all.
shadow-exclude = [
  "class_g = 'Polybar'",
  "class_g = 'i3-frame'",
  "window_type = 'menu'"
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
# Chrome/Edge/Chromium right-click context menus (override_redirect, no
# WM_CLASS at all - confirmed via a live X11 property query, same shape as
# i3lock's own window) report _NET_WM_WINDOW_TYPE_MENU - picom's own
# corner-radius clipping doesn't correctly account for these menus' own
# native rounded-corner alpha shape (detect-rounded-corners=true isn't
# enough), leaving stray white pixels in the corners where the two
# rounding attempts disagree. window_type = 'menu' targets exactly this
# (confirmed distinct from dunst notifications, which report
# _NET_WM_WINDOW_TYPE_NOTIFICATION/UTILITY - so this doesn't touch those).
# class_g must be 'Polybar' (capital P) to actually match - picom's class_g
# is WM_CLASS's second ("general class") field, which polybar reports as
# "Polybar", not the lowercase "polybar" instance name in the first field
# (confirmed via `xprop WM_CLASS` on a live polybar window). A lowercase
# 'polybar' here silently never matches, so this exclusion (and the
# matching ones in shadow-exclude/blur-background-exclude above/below) did
# nothing - every polybar theme's bar window was getting this 10px corner
# clip regardless of its own configured `radius`, most visibly on
# radius=0 "flat" themes, which should never have shown a rounded corner
# at all. Caught by screenshotting a flat theme's actual bar corner and
# seeing wallpaper peeking through a curve that had no source in the
# theme's own polybar config.
rounded-corners-exclude = [
  "class_g = 'Polybar'",
  "window_type = 'menu'"
];

blur: {
  method = "dual_kawase";
  strength = 6;
}
# window_type = 'menu' here fixes a second, separate artifact from the
# rounded-corner one above: a stray colored strip bleeding along the edge
# of Chrome/Edge right-click menus, most visible at a corner. Confirmed via
# a live screenshot + pixel sampling that the strip's color matched
# whatever was directly behind/beside the menu window (wallpaper, an
# adjacent window) rather than anything in the menu's own theme - i.e. the
# background blur was sampling past the menu's actual rounded-corner clip
# boundary and smearing in nearby pixels. blur, not corner-radius, was the
# actual source this time; excluding the menu from background blur (not
# just from the rounded-corners clip) removes the sampling entirely.
blur-background-exclude = [
  "class_g = 'Polybar'",
  "window_type = 'menu'"
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
; the regular text baseline.
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
; last segment, farthest right.
modules-right = sep-base-mauve-cap tray-cap sep-mauve-cap-surface0 tray sep-surface0-sky backlight sep-sky-mauve pulseaudio sep-mauve-teal media sep-teal-blue network-wired network-wireless sep-blue-teal bluetooth sep-teal-green caffeine sep-green-red dnd sep-red-peach battery sep-peach-yellow memory sep-yellow-green cpu sep-green-lavender date-icon date

[bar/top-secondary]
inherit = bar/base
; same as top-primary minus tray/battery - without this split every extra
; monitor showed a permanently empty tray slot since only one instance can
; ever win the X11 tray selection.
modules-right = sep-base-sky backlight sep-sky-mauve pulseaudio sep-mauve-teal media sep-teal-blue network-wired network-wireless sep-blue-yellow memory sep-yellow-green cpu sep-green-lavender date-icon date

; --- powerline separators ---------------------------------------------------
; Each is a plain glyph rendered in the color of the segment being LEFT
; (content-foreground) over the background of the segment being ENTERED
; (content-background) - that's what makes the rounded cap look like it
; belongs to both neighbours and reads as one continuous capsule chain.
; All of them point the same direction because the whole chain flows left to
; right; only the fg/bg pair changes per transition.
[module/sep-base-mauve-cap]
type = custom/text
format = <label>
label = ""
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
label = ""
label-font = 2
label-foreground = ${colors.mauve}
label-background = ${colors.surface0}
label-underline = ${colors.mauve}
label-overline = ${colors.mauve}

[module/sep-surface0-sky]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.sky}
label-underline = ${colors.mauve}
label-overline = ${colors.mauve}

[module/sep-base-sky]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.sky}

[module/sep-sky-mauve]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.sky}
label-background = ${colors.mauve}

[module/sep-mauve-blue]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.mauve}
label-background = ${colors.blue}

[module/sep-mauve-teal]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.mauve}
label-background = ${colors.teal}

[module/sep-teal-blue]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.teal}
label-background = ${colors.blue}

[module/sep-blue-teal]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.blue}
label-background = ${colors.teal}

[module/sep-teal-green]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.teal}
label-background = ${colors.green}

[module/sep-green-red]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.red}

[module/sep-red-peach]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.red}
label-background = ${colors.peach}

[module/sep-peach-yellow]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.peach}
label-background = ${colors.yellow}

[module/sep-blue-yellow]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.blue}
label-background = ${colors.yellow}

[module/sep-yellow-green]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.yellow}
label-background = ${colors.green}

[module/sep-green-lavender]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.lavender}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
; The real centering culprit: label-focused/unfocused/urgent default to
; "%icon% %name%" - since no ws-icon-N is configured, %icon% renders empty
; but the literal space between it and %name% is still there, permanently
; skewing the visible digit right of center. ws-label pins content to just
; the index, removing that invisible leading space entirely.
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-urgent = ${self.ws-label}
; font-2 (index 3) is the plain, unpatched JetBrains Mono - kept as a minor
; extra safety margin against Nerd Font glyph-metrics quirks (nerd-fonts#991)
; on top of the ws-label fix above. No fill/background here either - polybar
; has no way to draw a rounded rectangle around dynamic per-item text, so a
; filled box always renders as a hard square; underline+overline avoids that
; entirely instead of just trying to soften it.
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

[module/date-icon]
type = custom/text
format = <label>
label = "%{A1:gnome-calendar &:}    %{A}"
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

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = "  󰃟 %percentage%% "
label-foreground = ${colors.base}
format-background = ${colors.sky}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "   %percentage%% "
label-muted = "   muted "
label-volume-foreground = ${colors.base}
label-muted-foreground = ${colors.base}
format-volume-background = ${colors.mauve}
format-muted-background = ${colors.mauve}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label. They
; share one segment color/slot since at most one of them is ever visible.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.base}
format-background = ${colors.teal}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}   %ifname% %{A}"
label-connected-foreground = ${colors.base}
format-connected-background = ${colors.blue}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}   %essid% %{A}%{A}"
label-connected-foreground = ${colors.base}
format-connected-background = ${colors.blue}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.base}
format-background = ${colors.teal}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.base}
format-background = ${colors.green}

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
battery = BAT0
adapter = AC
label-charging = "   %percentage%% "
label-discharging = "   %percentage%% "
label-full = "   Full "
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}
format-charging-background = ${colors.peach}
format-discharging-background = ${colors.peach}
format-full-background = ${colors.peach}

[module/memory]
type = internal/memory
interval = 2
label = "   %percentage_used%% "
label-foreground = ${colors.base}
format-background = ${colors.yellow}

[module/cpu]
type = internal/cpu
interval = 2
label = "   %percentage%% "
label-foreground = ${colors.base}
format-background = ${colors.green}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
; polybar's tray module has no true 4-sided border - format-underline/
; format-overline (top+bottom accent lines) is the closest it can draw to a
; frame. format-background is ALSO needed (not just tray-background, which
; per the docs only colors the individual icons, not the space around them)
; for a solid, cohesive pill instead of a transparent gap with framed icons.
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
# 6a2. Polybar themes - reachable from the app menu (Mod+alt+space)
# ----------------------------------------------------------------------------
# Each theme is a COMPLETE, standalone config.ini, not a [colors]-block
# fragment or a modules-left/-center/-right override - a real theme is more
# than a palette swap (module arrangement, which widgets get a filled
# background vs. plain text, whether powerline arrows connect segments at
# all, are all part of what makes e.g. Dracula's actual i3 setup - flat, no
# boxes - look nothing like Catppuccin's segmented powerline pills, even
# before any color is considered). polybar-theme.sh (11e1 below) applies a
# theme with a plain file copy - no splicing required. catppuccin-mocha.ini
# is just a saved copy of the config.ini just generated above - the
# reference/default theme, byte-identical to what every other config file
# in this script already assumes (rofi, i3lock, GTK, dunst all stay Mocha
# regardless of which polybar theme is active). dracula.ini, nord.ini, and
# archcraft.ini are built from scratch in genuinely different visual
# languages, each modeled directly on a real reference - and deliberately
# different from EACH OTHER structurally too, not just in color. Dracula
# is fully flat (github.com/dracula/i3, i3bar/i3status-based, confirmed by
# reading its actual config): no backgrounds anywhere except the focused
# workspace, widgets separated by a plain "|" divider. Nord uses grouped
# flat "islands" instead - related widgets share one background block
# with no divider between them, separated by a real empty gap from the
# next group - modeled on actual screenshots from github.com/stav121/
# i3wm-themer (themes/screenshots/*.png) and Jfeatherstone/i3-themes'
# Bebop theme (bebop_busy.png), fetched and looked at directly, not
# described secondhand. Archcraft uses rounded-cap "capsule" clusters -
# LD/RD decorator modules (U+E0B6/U+E0B4, the same half-circle pair
# Mocha's separators use, just bracketing a GROUP instead of connecting
# every segment) whose foreground matches the bracketed widgets' own
# format-background so cap and content fuse into one seamless pill,
# standalone items separated by a small dot (U+F444) instead of a divider
# - modeled directly on github.com/archcraft-os/archcraft-i3wm's real
# files/theme/polybar/{decor,modules,colors}.ini, fetched and read
# directly. An earlier version had BOTH Dracula and Nord fully flat with
# only different hex codes - looked like "the same theme, different
# colors" on an actual screenshot, which is what prompted giving Nord its
# own structure; Archcraft's own first pass left its capsule content
# background unset, so the LD/RD caps floated alone with nothing to
# visually connect to until format-background was added to match. All
# ported to polybar syntax since that stays this rice's bar of choice,
# keeping every widget this rice already has - tray, caffeine, DND, etc.
# - restyled rather than removed. A 5th theme (summer-heat, modeled on
# Jfeatherstone/i3-themes) was tried and later removed by request - if
# rebuilding it, its own CJK-numeral workspace icons need
# google-noto-sans-cjk-vf-fonts added back to the package list above.
#
# The remaining 16 themes (aline, brenda, cristina, cynthia, daniela,
# emilia, h4ck3r, isabel, jan, karla, marisol, pamela, silvia, varinka,
# yael, z0mbi3) are rices from github.com/gh0stzk/dotfiles - a real
# 18-theme bspwm/polybar collection, ported after cloning the whole repo
# locally (774 files) rather than fetching pieces through the GitHub API,
# and reading each rice's own real config.ini/modules.ini directly (15 of
# the 16 are genuine polybar configs; z0mbi3 turned out to be EWW-based
# instead - checked per-rice, not assumed from one example after an
# earlier check was wrong - so it translates the source's real
# colors/layout into polybar syntax rather than porting actual config).
# andrea and melissa were built the same way but removed by request after
# live-testing feedback (melissa's bar background was also fully
# transparent, the same class of readability risk fixed for marisol
# below, though no specific reason was given for either removal).
# Several real source palettes turned out to be exact copies of other
# themes already in this set (daniela and emilia's real colors were both
# Tokyo Night, already visually identical to nothing else here but to
# EACH OTHER; marisol's was the official Dracula palette) - reusing them
# as-is would have made those pairs look color-identical, so those three
# palettes instead, kept close to the original's mood (cool vs warm)
# where possible while their real STRUCTURE (workspace icon choices,
# bracket/chip/flat treatment, separator style) is preserved exactly.
# Several rices also ship as 2-6 SEPARATE bars (cynthia: 2, karla: 2,
# pamela: 6) or a true vertical sidebar (z0mbi3) rather than one
# horizontal top bar - every one of those was consolidated into this
# rice's usual single top bar, the same simplification already applied to
# Cynthia's dual-bar layout, rather than changing the launch/gaps setup
# per-theme. A live contrast audit across the whole batch (computing
# actual WCAG contrast ratios between every foreground/background pair
# from each theme's own [colors] block, not eyeballing it) caught several
# real readability bugs before they shipped: aline's yellow/teal icon
# accents were unreadable against its own light cream chip (chosen for a
# DARK theme's contrast profile, ported without adjusting for the switch
# to a light background); brenda's Pac-Man-icon workspace colors had the
# same problem for the same reason; nord's and silvia's muted DND/urgent
# reds were too close in luminance to their own dark backgrounds to read
# as an alert color at all. Fixed by adding separate darker/lighter
# text-safe variants alongside the original (still-correct-elsewhere)
# accent tokens rather than changing shared tokens wholesale, since
# several of those same colors are ALSO used correctly elsewhere as vivid
# chip backgrounds in the same file. Transparency was another real,
# easy-to-miss detail: several sources set their bar's own background
# with a genuine alpha channel, not a flat opaque color - re-checking
# every source's real background line (not just its RGB) found marisol
# and melissa are FULLY transparent (only their own widget chips are ever
# visible, floating directly over the wallpaper), jan/karla/varinka are
# subtly transparent (98%/90%/85% opaque), and pamela's real background
# color comes from a completely different key (bg-alt, not bg) than the
# one this port originally read - all five corrected and live-screenshot-
# verified against this rice's own picom setup (which already excludes
# polybar from shadow/rounded-corners/blur, so its real alpha channel
# renders through cleanly) before being ported here.
#
# A second, hands-on-the-actual-desktop feedback pass (not automated
# contrast math, which had already run and passed) caught what that
# audit couldn't: marisol's literal full transparency read as genuinely
# illegible white text against a real (light) wallpaper - only a live
# screenshot with a specific real desktop behind it catches that, since
# it depends on wallpaper content no theme file can predict. Fixed by
# walking back to ~90% opacity (readability over literal source fidelity
# for this one theme) and adding a rounded-cap bracket around its
# workspace cluster per direct request. The same pass found aline and
# brenda's tray had no dedicated backdrop of its own - most tray icons
# (Discord, 1Password, etc.) are drawn in white/light colors expecting a
# dark bar, and inherited each theme's own light chip color instead,
# effectively disappearing; fixed with an explicit dark, opaque tray
# background independent of the rest of the palette. jan/varinka's
# workspace text was too small and karla's had no padding between
# entries at all - both one-line fixes (a larger label-*-font slot, an
# explicit label-*-padding) easy to miss by omission on any theme with
# plain digit/letter workspace labels. andrea and melissa were dropped by
# request rather than iterated on further. hidrot (below, from
# github.com/Murzchnvok/polybar-collection - its sibling theme "murz" was
# built, tested, and also dropped by request) applies every one of these
# lessons from the start instead of needing them fixed in after the fact:
# ~90% opacity (not full), an explicit dark tray-bg token, and real
# padding/font sizing on its workspace glyphs from the first version.
#
# IMPORTANT for editing any theme file below: never hand-type a Nerd Font
# glyph directly into a heredoc/file, and never hand-type one into an
# Edit() old_string/new_string either - a real mistake in an earlier
# version silently dropped EVERY separator glyph in catppuccin-mocha.ini
# (empty label = "" instead of the U+E0B4 powerline cap - rendered as flat
# squares instead of pills, no error anywhere), most widget icons across
# the first 3 themes, and later caused an Edit() call on archcraft.ini to
# fail to match at all (polybar treats a missing glyph exactly like an
# intentionally empty label, and a Read()/Edit() round-trip of a
# hand-typed glyph doesn't reliably preserve the exact bytes either).
# Verify with python - `ord(c) for c in label` - not by eye; a Write() or
# Edit() tool call visually LOOKS like it included the glyph even when the
# actual bytes silently didn't make it in or didn't match. Prefer doing
# any edit that touches a glyph line via a Python string-replace script
# matched on surrounding ASCII text instead.
log "Writing polybar themes..."
mkdir -p "$CONF/polybar/themes"
cp "$CONF/polybar/config.ini" "$CONF/polybar/themes/catppuccin-mocha.ini"

cat > "$CONF/polybar/themes/dracula.ini" <<'EOF'
; Dracula - flat, minimal, no powerline pills anywhere. Modeled directly on
; the ACTUAL github.com/dracula/i3 port (confirmed by reading its real
; config, not assumed): that setup is i3bar/i3status-based, not polybar,
; and renders almost everything as plain statusline text - the workspace
; switcher is the only element that ever gets a filled background, and
; only for the FOCUSED state; every other widget is just colored text
; separated by a plain "|" divider in the muted "Current Line" tone
; (#44475a), which is also i3status's own real separator color in that
; config. Ported to polybar (this rice's bar of choice throughout) rather
; than switching to i3bar/i3status, keeping every widget this rice already
; has (tray, caffeine, DND, etc. - none of which exist in the plain
; i3status world) but restyled to match that flat philosophy instead of
; Catppuccin Mocha's segmented powerline-pill one.
[colors]
base     = #282a36
mantle   = #282a36
surface0 = #44475a
surface1 = #44475a
text     = #f8f8f2
subtext  = #6272a4
mauve    = #bd93f9
lavender = #ff79c6
blue     = #6272a4
sky      = #8be9fd
green    = #50fa7b
teal     = #8be9fd
yellow   = #f1fa8c
peach    = #ffb86c
red      = #ff5555

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
; The tray needs SOME background to give its icons a defined, clickable
; area - everything else here is flat text, so a small muted box (Current
; Line, not an accent) reads as "a container", not "another pill in a
; powerline chain" the way Mocha's mauve tray-cap did.
modules-right = tray sep-plain backlight sep-plain pulseaudio sep-plain media sep-plain network-wired network-wireless sep-plain bluetooth sep-plain caffeine sep-plain dnd sep-plain battery sep-plain memory sep-plain cpu sep-plain date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep-plain pulseaudio sep-plain media sep-plain network-wired network-wireless sep-plain memory sep-plain cpu sep-plain date-icon date

[module/sep-plain]
type = custom/text
format = <label>
label = "|"
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-urgent = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.text}
label-focused-background = ${colors.surface0}
label-focused-padding = 3
; Unfocused workspaces get NO background at all (not even the bar's own
; color explicitly set) - just muted text directly on the bar, matching
; the real dracula/i3 config's own inactive-workspace treatment exactly
; (its bg is literally the bar's own background - the box is invisible
; until focused).
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
label = "%{A1:gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.mauve}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = " 󰃟 %percentage%%"
label-foreground = ${colors.yellow}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "  %percentage%%"
label-muted = "  muted"
label-volume-foreground = ${colors.green}
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.green}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}  %essid%%{A}%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.sky}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "  %percentage%%"
label-discharging = "  %percentage%%"
label-full = " Full"
label-charging-foreground = ${colors.peach}
label-discharging-foreground = ${colors.peach}
label-full-foreground = ${colors.peach}

[module/memory]
type = internal/memory
interval = 2
label = "  %percentage_used%%"
label-foreground = ${colors.yellow}

[module/cpu]
type = internal/cpu
interval = 2
label = "  %percentage%%"
label-foreground = ${colors.green}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/nord.ini" <<'EOF'
; Nord - grouped flat "islands" with real gaps between groups, no dividers
; within a group. Modeled on the actual layout style seen in stav121/
; i3wm-themer's own theme screenshots (github.com/stav121/i3wm-themer,
; themes/screenshots/*.png - fetched and looked at directly, not just
; described) and Jfeatherstone/i3-themes' Bebop theme (same - the real
; bebop_busy.png screenshot, not a text summary of it): related stats
; (volume/network/bluetooth, battery/memory/cpu) sit together in one
; shared-background block with no separator between them, icons alone
; carrying the color, then a real empty gap - not a divider glyph, not
; another color transition - before the next block starts. Genuinely
; different from this rice's other 2 themes: Mocha's segments are all
; physically CONNECTED by powerline arrows into one continuous ribbon,
; Dracula has NO backgrounds anywhere except the focused workspace: Nord
; sits in between - grouped flat blocks, gaps, no arrows. Colors are the
; official Nord palette (nordtheme.com).
[colors]
base     = #2e3440
mantle   = #2e3440
surface0 = #3b4252
surface1 = #434c5e
text     = #eceff4
subtext  = #d8dee9
mauve    = #b48ead
lavender = #81a1c1
blue     = #5e81ac
sky      = #88c0d0
green    = #a3be8c
teal     = #8fbcbb
yellow   = #ebcb8b
peach    = #d08770
red      = #bf616a
; lighter text-safe variant of red for the DND label - the plain red
; above is used as a chip background (fine as-is), but its own hex is
; too close in luminance to the dark surface0 chip when used as text.
red-light = #E098A0

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 4
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
; 4 grouped blocks (system stats / power-adjacent / tray / clock), each a
; single shared-background island with its own widgets packed tight inside
; (no divider between them - only the icon color tells them apart), a real
; empty gap-nord module between islands instead of a colored separator.
modules-right = backlight pulseaudio media network-wired network-wireless bluetooth gap-nord caffeine dnd battery gap-nord memory cpu gap-nord tray gap-nord date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media network-wired network-wireless gap-nord memory cpu gap-nord date-icon date

[module/gap-nord]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-urgent = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.text}
label-focused-background = ${colors.surface0}
label-focused-padding = 3
; Unfocused workspaces get NO background at all - just muted text directly
; on the bar, same restrained treatment the i3wm-themer/Bebop screenshots
; use for inactive workspace numbers (a flat number, not a colored pill).
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
label = "%{A1:gnome-calendar &:} 󰃰 %{A}"
label-font = 1
label-foreground = ${colors.lavender}
format-background = ${colors.surface0}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}
format-background = ${colors.surface0}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = " 󰃟 %percentage%% "
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "  %percentage%% "
label-muted = " muted "
label-volume-foreground = ${colors.green}
label-muted-foreground = ${colors.subtext}
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.green}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.sky}
format-connected-background = ${colors.surface0}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}  %essid% %{A}%{A}"
label-connected-foreground = ${colors.sky}
format-connected-background = ${colors.surface0}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.sky}
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}
format-background = ${colors.surface0}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red-light}
format-background = ${colors.surface0}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "  %percentage%% "
label-discharging = "  %percentage%% "
label-full = " Full "
label-charging-foreground = ${colors.peach}
label-discharging-foreground = ${colors.peach}
label-full-foreground = ${colors.peach}
format-charging-background = ${colors.surface0}
format-discharging-background = ${colors.surface0}
format-full-background = ${colors.surface0}

[module/memory]
type = internal/memory
interval = 2
label = "  %percentage_used%% "
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}

[module/cpu]
type = internal/cpu
interval = 2
label = "  %percentage%% "
label-foreground = ${colors.green}
format-background = ${colors.surface0}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/archcraft.ini" <<'EOF'
; Archcraft - grouped clusters bracketed by rounded-cap decorators, where
; the group's own widgets share the SAME background as the caps so the
; whole thing reads as one seamless rounded capsule (not the cap floating
; alone with unfilled content, which was wrong on the first pass here -
; confirmed by reading the real decor.ini + modules.ini together: LD/RD
; content-foreground = ALTBACKGROUND on content-background = BACKGROUND,
; and every module they bracket (i3, tray, date) sets its own
; format-background = ALTBACKGROUND to match). Standalone items outside
; any bracket are separated by a small dot glyph instead of a divider
; line. Modeled directly on the REAL Archcraft i3wm polybar config
; (github.com/archcraft-os/archcraft-i3wm, files/theme/polybar/
; {decor,modules,colors}.ini - fetched and read directly, not guessed):
; its own LD/RD "decor" modules use exactly these two glyphs (U+E0B6/
; U+E0B4, the same half-circle pair Mocha's separators use, just
; bracketing a GROUP instead of connecting every segment) and its own
; "dot" module uses U+F444. This is the 4th genuinely distinct structure
; in this rice's theme set: Mocha connects every segment with an arrow,
; Dracula has no backgrounds anywhere, Nord groups widgets under one
; shared fill block with a real gap between groups, Archcraft groups them
; under a rounded-cap capsule shape - closest in spirit to Archcraft's
; real workspace/tray cluster on the left and clock cluster on the right
; in its own config's modules-left/modules-right, while non-bracketed
; widgets (backlight/volume/network/battery/memory/cpu) stay completely
; flat with only a colored icon prefix, matching modules.ini's own
; [module/cpu] etc exactly (format = <label>, no format-background at
; all). Colors are Archcraft's own real palette (colors.ini) - a
; One-Dark-adjacent scheme, not Catppuccin, Dracula, or Nord - mapped
; onto this rice's 15 tokens: BACKGROUND/ALTBACKGROUND -> base/mantle/
; surface0/surface1, FOREGROUND/ALTFOREGROUND -> text/subtext, MAGENTA ->
; mauve/lavender (only one purple in the source), BLUE -> blue, CYAN ->
; sky/teal, GREEN -> green, YELLOW -> yellow, ACCENT (its own highlight
; rose/pink, not a generic peach) -> peach, RED -> red.
[colors]
base     = #1e222a
mantle   = #1e222a
surface0 = #292e39
surface1 = #292e39
text     = #c8ccd4
subtext  = #727c91
mauve    = #c678dd
lavender = #c678dd
blue     = #61afef
sky      = #56b6c2
green    = #98c379
teal     = #56b6c2
yellow   = #e5c07b
peach    = #da6e89
red      = #e06c75

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = LD i3 RD
modules-center =

[bar/top-primary]
inherit = bar/base
; The left cluster is the workspace switcher alone (already bracketed by
; LD/RD in bar/base); the tray gets its own small bracketed group here
; since it's primary-only. Every widget on the right is plain/unfilled,
; dot-separated, with one final LD/RD-bracketed group for the clock.
modules-left = LD i3 RD dot LD tray RD
modules-right = backlight dot pulseaudio dot media dot network-wired network-wireless dot bluetooth dot caffeine dot dnd dot battery dot memory dot cpu dot LD date-icon date RD

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dot pulseaudio dot media dot network-wired network-wireless dot memory dot cpu dot LD date-icon date RD

[module/LD]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}

[module/RD]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}

[module/dot]
type = custom/text
format = <label>
label = "  "
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
; format-background here matches LD/RD's own foreground so the caps and
; the workspace squares fuse into one seamless capsule (the fix - without
; it the caps float alone with nothing to visually connect to).
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-visible = ${self.ws-label}
label-urgent = ${self.ws-label}
; Each workspace state pops its own accent color against the shared
; surface0 capsule background - matching the real archcraft-i3wm config's
; label-focused/-unfocused/-visible/-urgent split exactly (blue/
; unchanged/green/red there too, just using this rice's own token names).
label-focused-font = 3
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.blue}
label-focused-padding = 3
label-unfocused-font = 3
label-unfocused-foreground = ${colors.text}
label-unfocused-background = ${colors.surface0}
label-unfocused-padding = 2
label-visible-font = 3
label-visible-foreground = ${colors.base}
label-visible-background = ${colors.green}
label-visible-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.peach}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = " 󰃟 %percentage%% "
label-foreground = ${colors.yellow}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "  %percentage%% "
label-muted = " muted "
label-volume-foreground = ${colors.green}
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.green}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}  %essid% %{A}%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.sky}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "  %percentage%% "
label-discharging = "  %percentage%% "
label-full = " Full "
label-charging-foreground = ${colors.peach}
label-discharging-foreground = ${colors.peach}
label-full-foreground = ${colors.peach}

[module/memory]
type = internal/memory
interval = 2
label = "  %percentage_used%% "
label-foreground = ${colors.yellow}

[module/cpu]
type = internal/cpu
interval = 2
label = "  %percentage%% "
label-foreground = ${colors.green}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
format-background = ${colors.surface0}
tray-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/aline.ini" <<'EOF'
; Aline - a light/pastel theme, the only non-dark theme in this rice's
; set. Rounded-cap bracket groups (bi/bd = U+E0B6/U+E0B4, the same
; half-circle pair Mocha's own separators and Archcraft's LD/RD use) wrap
; clusters of related widgets in one shared cream ("mc") capsule, plain
; icon-prefix-colored widgets inside - structurally close to this rice's
; own Archcraft theme (same glyph family, same "shared group background"
; idea), but never dark: bar/text/group colors are all warm cream/plum,
; not a single dark canvas anywhere. Modeled directly on github.com/
; gh0stzk/dotfiles' real "aline" rice (config/bspwm/rices/aline/
; {config,modules}.ini, read from a full local clone of the repo, not
; fetched piecemeal) - a genuine polybar config, unlike this same repo's
; "andrea"/"z0mbi3" rices which turned out to be EWW-based instead
; (checked per-rice this time, not assumed from one example). Workspaces
; get a real per-number identity here: each UNFOCUSED workspace shows its
; own uniquely-colored circled-number icon (ws-icon-N, a genuine Material
; Design "circled digit" codepoint per number) rather than a shared style,
; collapsing to a plain digit only once focused or urgent - matching the
; source's own "unique icon when empty, shared style when active" split.
; The source's own usercard/mplayer/power/colorpicker/weather modules are
; static buttons or external scripts specific to that rice's own toolkit
; (Weather/Colorpicker/OpenApps helper commands) not present in this rig,
; so they're left out rather than faked - same call this rice's other
; themes made for widgets they couldn't actually port (Summer-heat's
; Spotify/Google-Calendar, Archcraft's tray-adjacent extras). Two of the
; source's own icon codepoints (a workspace "active" check-glyph, U+F09DE,
; and a mute icon, U+F6A9) turned out to be MISSING from this rice's
; actual installed Nerd Font build when render-tested before use (one
; came back as a generic bullet placeholder, the other fully blank) -
; caught by rendering every new codepoint before writing it into a real
; file, not after; replaced with a plain digit and plain "muted" text,
; both already proven safe by every other theme in this set.
[colors]
base = #FAF4ED
mantle = #FAF4ED
surface0 = #F2E9E1
surface1 = #F2E9E1
text = #575279
subtext = #9893A5
teal = #2E7480
; Dedicated dark, fully-opaque backdrop for the system tray specifically -
; most tray icons (Discord, 1Password, etc.) are drawn in white/light
; colors expecting a dark bar and become invisible against this theme's
; own light cream chips (caught via direct feedback, not assumed).
tray-bg = #3D3757
green = #286983
yellow = #A15E15
red = #B4637A
blue = #2E5D66

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius-top = 0
radius-bottom = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = bi i3 bd
modules-center = bi date bd

[bar/top-primary]
inherit = bar/base
modules-right = bi backlight pulseaudio media bd sep bi network-wired network-wireless bd sep bi bluetooth caffeine dnd bd sep bi battery memory cpu bd sep bi-tray tray bd-tray

[bar/top-secondary]
inherit = bar/base
modules-right = bi backlight pulseaudio media bd sep bi network-wired network-wireless bd sep bi memory cpu bd

[module/bi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/bd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

; Tray-specific cap pair - same shape as bi/bd above, but colored for the
; tray's own dark backdrop instead of the light cream chip everything
; else uses, so the caps blend into tray-bg instead of clashing with it.
[module/bi-tray]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.tray-bg}
label-background = ${colors.base}

[module/bd-tray]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.tray-bg}
label-background = ${colors.base}

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰬺
ws-icon-1 = 2;󰬻
ws-icon-2 = 3;󰬼
ws-icon-3 = 4;󰬽
ws-icon-4 = 5;󰬾
ws-icon-5 = 6;󰬿
ws-icon-6 = 7;󰭀
ws-icon-7 = 8;󰭁
ws-icon-8 = 9;󰭂
ws-icon-default = "♟"
label-focused = ${self.ws-label}
ws-label = %index%
label-unfocused = %icon%
label-urgent = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.blue}
label-focused-padding = 3
label-unfocused-font = 3
label-unfocused-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.red}
label-urgent-padding = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.text}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"
label-font = 3

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %percentage%% "

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.teal}
format-muted-background = ${colors.surface0}
label-volume = " %percentage%% "
label-muted = " muted "
label-muted-foreground = ${colors.red}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.teal}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:} %ifname% %{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-background = ${colors.surface0}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.text}
label = " %percentage_used%% "

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.text}
label = " %percentage%% "

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.tray-bg}
format-background = ${colors.tray-bg}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/brenda.ini" <<'EOF'
; Brenda - flat, individually-colored two-part widgets: every widget is a
; vivid-colored icon chip immediately followed by its own cream ("mbg")
; value chip, separated from the NEXT widget by a real gap - each widget
; gets its own distinct hue (yellow/green/orange/blue/lime/red) rather
; than one accent reused everywhere. Workspaces get a genuine Pac-Man
; theme: focused = Pac-Man glyph (orange), occupied/urgent = ghost glyph
; (purple), empty = a plain moon/dot (blue-gray) - all sharing one light
; cream chip background. Modeled directly on github.com/gh0stzk/dotfiles'
; real "brenda" rice (config/bspwm/rices/brenda/{config,modules}.ini,
; read from a full local clone). An Everforest-adjacent dark-olive palette
; (bg=#2d353b, fg warm cream) - distinct from every other palette in this
; rice's theme set. One of the source's own icon choices (a battery-
; charging "plug" glyph, U+E0B7) rendered as an unrelated crescent shape
; when render-tested in this rice's actual Nerd Font build, so charging
; reuses this rice's own already-verified battery icon instead of a new,
; unverified one.
[colors]
base   = #2D353B
mantle = #2D353B
surface0 = #F8F5E4
surface1 = #F8F5E4
text   = #D3C6AA
subtext = #859289
red    = #E67E80
green  = #A7C080
yellow = #DBBC7F
blue   = #7FBBB3
purple = #D699B6
orange = #E69875
lime   = #B9C244
; darker text-safe variants for use on the light cream ("surface0") chip -
; the plain orange/purple/red above stay vivid for use as CHIP
; BACKGROUNDS (with dark text on top), where the lighter tone is correct;
; these are for text/icons drawn directly on that same light chip, which
; the vivid tones don't have enough contrast for.
orange-dark = #A8501F
purple-dark = #96406B
red-dark    = #B33440
green-dark  = #3E6E2E

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep network-icon network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery-icon battery sep memory-icon memory sep cpu-icon cpu sep tray sep date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep network-icon network-wired network-wireless sep memory-icon memory sep cpu-icon cpu sep date-icon date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = " 󰮯 "
label-focused-foreground = ${colors.orange-dark}
label-focused-padding = 1
label-unfocused = " 󰊠 "
label-unfocused-foreground = ${colors.purple-dark}
label-unfocused-padding = 1
label-urgent = " 󰊠 "
label-urgent-foreground = ${colors.red-dark}
label-urgent-padding = 1

[module/date-icon]
type = custom/text
format = <label>
format-background = ${colors.blue}
label = "  "
label-foreground = ${colors.base}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:} %date%  %time% %{A}"
label-foreground = ${colors.base}

[module/backlight-icon]
type = custom/text
format = <label>
format-background = ${colors.yellow}
label = " 󰃟 "
label-foreground = ${colors.base}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
label = " %percentage%% "
label-foreground = ${colors.base}

[module/pulseaudio-icon]
type = internal/pulseaudio
format-volume = <label-volume>
format-muted = <label-muted>
format-volume-background = ${colors.orange}
format-muted-background = ${colors.orange}
label-volume = "  "
label-volume-foreground = ${colors.base}
label-muted = "  "
label-muted-foreground = ${colors.base}

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}
label-volume = " %percentage%% "
label-muted = " muted "
label-volume-foreground = ${colors.base}
label-muted-foreground = ${colors.base}

[module/network-icon]
type = custom/text
format = <label>
format-background = ${colors.green}
label = "  "
label-foreground = ${colors.base}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.base}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green-dark}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red-dark}

[module/battery-icon]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.yellow}
format-discharging-background = ${colors.yellow}
format-full-background = ${colors.yellow}
label-charging = "  "
label-discharging = "  "
label-full = "  "
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-discharging-background = ${colors.surface0}
format-full-background = ${colors.surface0}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}

[module/memory-icon]
type = custom/text
format = <label>
format-background = ${colors.blue}
label = "  "
label-foreground = ${colors.base}

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
label = " %percentage_used%% "
label-foreground = ${colors.base}

[module/cpu-icon]
type = custom/text
format = <label>
format-background = ${colors.red}
label = "  "
label-foreground = ${colors.base}

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
label = " %percentage%% "
label-foreground = ${colors.base}

; Tray specifically uses the theme's own dark base, not the light cream
; surface0 every other widget's value-chip uses - most tray icons
; (Discord, 1Password, etc.) are drawn in white/light colors expecting a
; dark bar and become invisible against a light chip (caught via direct
; feedback, not assumed).
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.base}
format-background = ${colors.base}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/cristina.ini" <<'EOF'
; Cristina - individually-colored pill capsules: each quantifiable widget
; gets its OWN rounded-cap bracket pair (U+E0B6/U+E0B4, same glyph family
; as Mocha/Archcraft/Aline) in its own distinct hue, with a real gap
; between each pill instead of a shared group background or a continuous
; connected chain - a genuine third variation on the same bracket-glyph
; idea already used elsewhere in this rice's set. Non-quantifiable
; widgets (battery, bluetooth, caffeine, dnd) stay fully plain/unbracketed
; with just a colored icon prefix, matching the source's own real mixed
; treatment exactly (its battery module has no background at all, while
; its filesystem/cpu/memory/pulseaudio/network/date modules each get
; their own individual bracket pair colored to match that widget's icon).
; Modeled directly on github.com/gh0stzk/dotfiles' real "cristina" rice
; (config/bspwm/rices/cristina/{config,modules}.ini, read from a full
; local clone). A Rosé-Pine-Moon-adjacent dark purple-navy palette
; (bg=#232136, fg pale lavender). Workspaces stay plain digits directly
; on the bar's own background (no chip at all) - matching the source's
; own unbracketed workspace treatment - rather than porting its literal
; per-number app-category icon set (folder/code/gamepad/etc, ending in a
; literal toilet emoji for workspace 9), which is too specific to the
; original author's own workflow to carry meaning here.
[colors]
base   = #232136
mantle = #232136
surface0 = #39374A
text   = #E0DEF4
subtext = #908CAA
red    = #EA6F91
green  = #9BCED7
yellow = #F1CA93
blue   = #34738E
purple = #C3A5E6
orange = #F08641
indigo = #6C77BB
lime   = #8EC07C

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = bli backlight bld sep voli pulseaudio vold sep media sep neti network-wired network-wireless netd sep bluetooth sep caffeine sep dnd sep battery sep memi memory memd sep cpi cpu cpd sep tray sep dti date dtd

[bar/top-secondary]
inherit = bar/base
modules-right = bli backlight bld sep voli pulseaudio vold sep media sep neti network-wired network-wireless netd sep memi memory memd sep cpi cpu cpd sep dti date dtd

; --- bracket pairs -------------------------------------------------------
[module/sep]
type = custom/text
format = <label>
label = "  "

[module/bli]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.base}

[module/bld]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.green}

[module/neti]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.orange}
label-background = ${colors.base}

[module/netd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.orange}

[module/memi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.purple}
label-background = ${colors.base}

[module/memd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.purple}

[module/cpi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.yellow}
label-background = ${colors.base}

[module/cpd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.yellow}

[module/voli]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.blue}
label-background = ${colors.base}

[module/vold]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.blue}

[module/dti]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.indigo}
label-background = ${colors.base}

[module/dtd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.indigo}


; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-foreground = ${colors.lime}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-foreground = ${colors.purple}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.indigo}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.green}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.blue}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.blue}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.orange}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.orange}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/cynthia.ini" <<'EOF'
; Cynthia - deliberately monochrome and minimal: a near-black bar where
; only the workspace state colors (blue/green/red) carry any real hue at
; all - every other widget is plain icon+text directly on the bar's own
; background, with only a FEW widgets (workspace, cpu+memory together,
; network) wrapped in a single dark-gray bracket capsule (bi/bd =
; U+E0B6/U+E0B4) rather than a rainbow of individually-colored ones like
; this rice's own Cristina theme, or a shared accent like Archcraft.
; Modeled directly on github.com/gh0stzk/dotfiles' real "cynthia" rice
; (config/bspwm/rices/cynthia/{config,modules}.ini, read from a full
; local clone) - workspace numbers reuse the same circled-digit icon
; style as this rice's own Aline theme (ws-icon-N, verified render-tested
; there already), but here EVERY state (focused/occupied/urgent) keeps
; the same per-number icon and only changes color, rather than Aline's
; "unique icon only when empty" split. The source actually ships this
; rice as TWO separate bars (a top bar for workspaces/system stats, a
; bottom bar for media/weather/date) - consolidated into this rice's
; usual single top bar instead, since a real second bar is a structural
; change to the launch/gaps setup affecting every theme, not something
; to introduce for just one of them.
[colors]
base   = #181616
mantle = #181616
surface0 = #242121
surface1 = #242121
text   = #C5C9C5
subtext = #708491
red    = #E46876
green  = #87A987
blue   = #7FB4CA
purple = #938AA9
yellow = #E6C384
orange = #E57C46

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = bi i3 bd
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = bi memory cpu bd sep bi network-wired network-wireless bd sep bluetooth sep caffeine sep dnd sep battery sep backlight sep pulseaudio sep media sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = bi memory cpu bd sep bi network-wired network-wireless bd sep backlight sep pulseaudio sep media sep date

[module/bi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/bd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰬺
ws-icon-1 = 2;󰬻
ws-icon-2 = 3;󰬼
ws-icon-3 = 4;󰬽
ws-icon-4 = 5;󰬾
ws-icon-5 = 6;󰬿
ws-icon-6 = 7;󰭀
ws-icon-7 = 8;󰭁
ws-icon-8 = 9;󰭂
ws-icon-default = "♟"
label-focused = %icon%
label-focused-foreground = ${colors.blue}
label-focused-font = 2
label-focused-padding = 1
label-unfocused = %icon%
label-unfocused-foreground = ${colors.green}
label-unfocused-font = 2
label-unfocused-padding = 1
label-urgent = %icon%
label-urgent-foreground = ${colors.red}
label-urgent-font = 2
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/daniela.ini" <<'EOF'
; Daniela - flat text-label widgets: instead of an icon glyph, each
; widget's own prefix is a literal colored WORD ("CPU", "RAM", "NET",
; "VOL", "BAT") with a plain, unstyled value next to it - no background
; anywhere, no divider between widgets, each label just its own color
; directly on the bar. Genuinely different from every icon-based theme in
; this rice's set. Modeled directly on github.com/gh0stzk/dotfiles' real
; "daniela" rice (config/bspwm/rices/daniela/{config,modules}.ini, read
; from a full local clone): its own cpu_bar/memory_bar/etc modules
; literally set format-prefix to the word "CPU"/"RAM" (font-1, colored),
; confirmed by reading the actual module bodies rather than guessing from
; the screenshot alone. The source's own color palette turned out to be
; Catppuccin Mocha's exact hex values reused wholesale (bg=#181825,
; fg=#cdd6f4, same red/blue/green/yellow/purple as this rice's own
; catppuccin-mocha.ini) - porting it as-is would make two themes in this
; set look color-identical, so this port keeps daniela's real STRUCTURE
; (word-prefix, fully flat, no backgrounds) but uses a fresh Tokyo-Night-
; adjacent palette instead, distinct from every other theme here.
[colors]
base   = #1A1B26
mantle = #1A1B26
surface0 = #31323C
text   = #C0CAF5
subtext = #565F89
red    = #F7768E
green  = #9ECE6A
yellow = #E0AF68
blue   = #7AA2F7
purple = #BB9AF7
cyan   = #7DCFFF
orange = #FF9E64

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight pulseaudio media network-wired network-wireless bluetooth caffeine dnd battery memory cpu tray date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media network-wired network-wireless memory cpu date

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-foreground = ${colors.blue}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.orange}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "BRT "
format-prefix-font = 1
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = "VOL "
format-volume-prefix-font = 1
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.red}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = "NET "
format-connected-prefix-font = 1
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = "NET "
format-connected-prefix-font = 1
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = "BAT "
format-charging-prefix-font = 1
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = "BAT "
format-discharging-prefix-font = 1
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = "BAT "
format-full-prefix-font = 1
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = "RAM "
format-prefix-font = 1
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-font = 1
format-prefix-foreground = ${colors.blue}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/emilia.ini" <<'EOF'
; Emilia - individually-bracketed capsules again (like this rice's own
; Cristina theme), but every bracket shares the SAME muted color instead
; of a rainbow of per-widget hues - a sea of small uniform dark-gray
; pills, each holding just one (or occasionally two related) widgets,
; real gaps between them. Workspaces reuse the same Pac-Man/ghost/moon
; icon set as this rice's own Brenda theme (label-focused/-occupied/
; -urgent/-empty = U+F0BAF/U+F02A0/U+F02A0/U+F044A, confirmed identical
; codepoints by reading both sources directly) but structured completely
; differently: Brenda pairs a vivid icon-chip with a separate value-chip
; for every widget, Emilia wraps each whole widget in one plain muted
; bracket instead. Modeled directly on github.com/gh0stzk/dotfiles' real
; "emilia" rice (config/bspwm/rices/emilia/{config,modules}.ini, read
; from a full local clone). The source's own real palette turned out to
; be Tokyo Night again (same exact hex values already used for this
; rice's own Daniela theme, built earlier in this same batch) - reusing
; it here too would make two themes look color-identical, so this port
; uses a fresh warm copper/amber palette instead, distinct from every
; other theme built so far.
[colors]
base   = #1E1A17
mantle = #1E1A17
surface0 = #2B241F
surface1 = #2B241F
text   = #E8DCC8
subtext = #9C8F7D
red    = #D9736A
green  = #A8B562
yellow = #E0A458
blue   = #7FA5B5
purple = #B08BBB
orange = #D98E4A

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = bli backlight bld sep voli pulseaudio vold sep media
modules-center = bi i3 bd

[bar/top-primary]
inherit = bar/base
modules-right = neti network-wired network-wireless netd sep bti bluetooth btd sep cafi caffeine cafd sep dndi dnd dndd sep bati battery batd sep memi memory memd sep cpi cpu cpd sep tray sep dti date dtd

[bar/top-secondary]
inherit = bar/base
modules-right = neti network-wired network-wireless netd sep memi memory memd sep cpi cpu cpd sep dti date dtd

[module/bi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/bd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- bracket pairs -------------------------------------------------------
[module/bli]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/bld]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/voli]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/vold]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/neti]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/netd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/bti]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/btd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/cafi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/cafd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/dndi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/dndd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/bati]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/batd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/memi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/memd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/cpi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/cpd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/dti]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/dtd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}


; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-foreground = ${colors.blue}
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-background = ${colors.surface0}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/h4ck3r.ini" <<'EOF'
; H4ck3r - a deliberately monochrome green-on-black "matrix terminal"
; palette: the source's own colors.ini names keys "red"/"purple"/"blue"/
; "yellow" but EVERY one of them is actually some shade of green in hex
; (confirmed by reading the real hex values, not the key names - e.g.
; its own "red" is #6DDE00) - a hacker-aesthetic monochrome scheme
; disguised as a normal multi-hue palette. This port keeps that same
; "everything is a shade of green" idea honestly (no literal reds/blues
; anywhere) rather than reading the key names at face value. Workspace
; icons are a genuine reticle/skull/dot set (focused = targeting
; reticle, occupied/urgent = skull, empty = plain dot), all sharing one
; dark chip background. Modeled directly on github.com/gh0stzk/dotfiles'
; real "h4ck3r" rice (config/bspwm/rices/h4ck3r/{config,modules}.ini,
; read from a full local clone) - its own left-side network-info/VPN-
; status/target-lock modules are custom scripts specific to that rice's
; own security-tool workflow, not part of this rig, so left out rather
; than faked, same call made for other themes' unportable widgets.
[colors]
base   = #0C1018
mantle = #0C1018
surface0 = #1B2333
surface1 = #1B2333
text   = #00FA5C
subtext = #578A29
green  = #00FA5C
yellow = #76EA00
lime   = #9CF542
red    = #6DDE00

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󱓇"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 2
label-unfocused = "󰚌"
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent = "󰚌"
label-urgent-foreground = ${colors.lime}
label-urgent-padding = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.subtext}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-discharging-prefix = " "
format-full-prefix = " "
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/isabel.ini" <<'EOF'
; Isabel - deliberately understated: no chip backgrounds anywhere, no
; per-state color coding at all (focused/occupied/urgent workspaces all
; share the SAME plain foreground color - only the icon SHAPE tells them
; apart, confirmed by reading the source's own [module/bspwm] block,
; which sets every state's label-*-foreground to the same ${color.fg}).
; Standalone items are separated by a real visible vertical 3-dot bullet
; glyph (U+F01D9, colored) instead of a plain gap or a divider line -
; distinct from every other separator style in this rice's set. Reuses
; the same Pac-Man/ghost/moon workspace icon family as this rice's own
; Brenda and Emilia themes (confirmed identical codepoints, U+F0BAF/
; U+F02A0/U+F044A, by reading isabel's own real config) - the third of
; this batch to use it, since that really is what the source itself
; ships - but structured completely differently again: no chip, no
; bracket, no state color, just the bare icon on the bar. Modeled
; directly on github.com/gh0stzk/dotfiles' real "isabel" rice (config/
; bspwm/rices/isabel/{config,modules}.ini, read from a full local
; clone). The source's own palette turned out to be an Atom-One-Dark-
; adjacent scheme, already close to this rice's own Archcraft theme, so
; this port uses a fresh teal/mint dark palette instead to stay visually
; distinct.
[colors]
base   = #10181A
mantle = #10181A
surface0 = #282F31
text   = #A8C5C0
subtext = #5C7B76
teal   = #4FD6BE
green  = #7FBF8F
yellow = #D6B35C
red    = #D67F7F
blue   = #5FA8C7

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots tray dots date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots memory dots cpu dots date

[module/dots]
type = custom/text
format = <label>
label = " 󰇙 "
label-foreground = ${colors.teal}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-discharging-prefix = " "
format-full-prefix = " "
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/jan.ini" <<'EOF'
; Jan - a genuine Synthwave '84-adjacent neon palette: deep navy-purple
; background, hot-pink/electric-blue/neon-green/neon-yellow accents, no
; muted tones anywhere. The vivid high-contrast direction this rice
; considered early on (before settling on Archcraft/Nord/Dracula) shows
; up for real here, sourced rather than invented. Reuses the same
; circled-digit workspace icon family as this rice's own Aline/Cynthia
; themes (ws-icon-N, already verified rendering), but the focused state
; wraps its icon in literal square brackets ("[icon]", confirmed by
; reading the source's own label-focused = "[%icon%]") - a small but
; genuine detail distinct from either of those. Modeled directly on
; github.com/gh0stzk/dotfiles' real "jan" rice (config/bspwm/rices/jan/
; {config,modules}.ini, read from a full local clone). One of the
; source's own separator glyphs (U+F7C6) rendered fully blank when
; render-tested in this rice's actual Nerd Font build, so a plain gap is
; used instead, matching the same fix applied for other themes' missing
; glyphs in this batch.
; The source's own bg carries an alpha channel too (E6, ~90% opaque) -
; a subtle transparency this port matches rather than a flat opaque fill.
[colors]
base   = #E6212A4C
mantle = #E6212A4C
surface0 = #14192E
text   = #27FBFE
subtext = #6B7BB0
pink   = #FB007A
magenta = #F200F4
blue   = #19BFFE
green  = #00FF00
lime   = #8DF202
yellow = #F2ED00
orange = #DB330A
purple = #6800D2

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰬺
ws-icon-1 = 2;󰬻
ws-icon-2 = 3;󰬼
ws-icon-3 = 4;󰬽
ws-icon-4 = 5;󰬾
ws-icon-5 = 6;󰬿
ws-icon-6 = 7;󰭀
ws-icon-7 = 8;󰭁
ws-icon-8 = 9;󰭂
ws-icon-default = "♟"
label-focused = "[%icon%]"
label-focused-foreground = ${colors.pink}
label-focused-font = 2
label-unfocused = %icon%
label-unfocused-foreground = ${colors.lime}
label-unfocused-font = 2
label-urgent = %icon%
label-urgent-foreground = ${colors.orange}
label-urgent-font = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.blue}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.blue}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.pink}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.blue}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.pink}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.pink}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.pink}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.yellow}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.pink}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/karla.ini" <<'EOF'
; Karla - vivid magenta/purple/electric-blue palette, widgets separated
; by a plain "|" pipe divider (an actual ASCII pipe, not a Nerd Font
; glyph - confirmed from the source's own [module/sep], `label = "|"`)
; rather than any powerline shape - the simplest divider style in this
; rice's whole theme set. Reuses the same targeting-reticle focused-
; workspace icon as this rice's own H4ck3r theme (U+F14C7, already
; verified rendering there), but on a vivid rather than monochrome
; palette, and with no color distinction between focused/unfocused
; (matching the source's own [module/bspwm], which sets both to the same
; plain foreground). Modeled directly on github.com/gh0stzk/dotfiles'
; real "karla" rice (config/bspwm/rices/karla/{config,modules}.ini, read
; from a full local clone) - the source actually ships this rice as
; THREE separate bars (system stats, media/battery/network, and a
; third bar just for centered workspaces), consolidated here into this
; rice's usual single top bar for the same reason Cynthia's two bars
; were: a real second or third bar is a structural change to the launch
; setup affecting every theme, not a per-theme decision.
; The source's own bg carries an alpha channel too (D9, ~85% opaque) -
; a subtle transparency this port matches rather than a flat opaque fill.
[colors]
base   = #D90E1113
mantle = #D90E1113
surface0 = #26292B
text   = #AFB1DB
subtext = #6272A4
red    = #E7034A
pink   = #F05393
purple = #7A44E3
blue   = #4856D4
cyan   = #7DF0F0
green  = #0FD94F
yellow = #F7F23F
orange = #F98860

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = " | "
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = "󱓇"
label-focused-foreground = ${colors.pink}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-foreground = ${colors.text}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.blue}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.red}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.blue}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.pink}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/marisol.ini" <<'EOF'
; Marisol - one shared dark-gray chip wraps the whole workspace cluster
; (format-level background, no bracket caps at all) - a 4th distinct
; structural treatment of the same Pac-Man/ghost workspace icon family
; already used by this rice's own Brenda (2-part icon+value chips),
; Emilia (individual mb-brackets per widget) and reused again here
; (confirmed identical codepoints, U+F0BAF/U+F02A0, by reading marisol's
; own real config) - genuinely the source's own shared default icon set
; across many of its rices, not a coincidence on this port's part.
; Modeled directly on github.com/gh0stzk/dotfiles' real "marisol" rice
; (config/bspwm/rices/marisol/{config,modules}.ini, read from a full
; local clone). The source's own palette turned out to be the official
; Dracula theme's exact hex values (bg=#282a36, fg=#f8f8f2, same reds/
; purples/greens as this rice's own catppuccin-adjacent Dracula theme) -
; reusing it here would make two themes look color-identical, so this
; port uses a fresh warm coral/salmon palette instead. The source's own
; bar background is ${color.trans} - fully transparent (alpha 00), not
; its opaque "bg" - only the workspace's own grey chip and individual
; widget colors are ever visible, floating directly over the wallpaper.
; A first pass ported that literally (alpha 00) - but real-world feedback
; against an actual (light) wallpaper found the theme's own light text
; unreadable with nothing behind it at all, since a fully transparent bar
; inherits whatever's on the desktop rather than anything this theme
; controls. Kept mostly-transparent (still see-through, still distinct
; from every fully-opaque theme in this set) but backed by enough of its
; own dark fill (alpha E6, ~90% opaque) that text and icons stay legible
; regardless of wallpaper - readability over literal source fidelity.
[colors]
base   = #E6241C1C
mantle = #E6241C1C
surface0 = #332727
surface1 = #332727
text   = #F5E6E0
subtext = #A8827C
red    = #E8604C
pink   = #E68A9E
yellow = #E8B84C
blue   = #6FA8C7
green  = #7FBF8F
purple = #B98FC7

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = bi i3 bd
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; Rounded-cap brackets around the workspace cluster (requested directly:
; "would be nice if the brown background around virtual desktop indicator
; had rounded corners") - the same U+E0B6/U+E0B4 half-circle pair Mocha's
; own separators and this rice's Archcraft/Aline/Cynthia use, foreground
; matching the workspace chip's own background so the caps and the
; content between them fuse into one seamless rounded pill instead of a
; flat-edged rectangle.
[module/bi]
type = custom/text
format = <label>
label = "%{T2}%{T-}"
label-font = 2
label-foreground = ${colors.surface0}

[module/bd]
type = custom/text
format = <label>
label = "%{T2}%{T-}"
label-font = 2
label-foreground = ${colors.surface0}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-foreground = ${colors.blue}
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

; Explicit dark, opaque tray backdrop - most tray icons (Discord,
; 1Password, etc.) are drawn in white/light colors expecting a dark bar,
; and this theme's own bar background is only ~90% opaque, not a fully
; reliable backdrop by itself.
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/pamela.ini" <<'EOF'
; Pamela - a 5th distinct treatment of the same Pac-Man/ghost workspace
; icon family this rice's own Brenda/Emilia/Isabel/Marisol themes already
; use (confirmed identical codepoints again by reading pamela's own real
; config) - here with NO chip background at all, but WITH per-state color
; (yellow focused, blue occupied/urgent), splitting the difference
; between Isabel's fully-plain no-color treatment and the others' boxed
; ones. Modeled directly on github.com/gh0stzk/dotfiles' real "pamela"
; rice (config/bspwm/rices/pamela/{config,modules}.ini, read from a full
; local clone) - the source actually ships this rice as SIX separate
; bars (launcher, workspaces, media, system stats, date, and a sixth for
; tray/weather/updates), by far the most bar-split rice in the whole
; collection, consolidated here into this rice's usual single bar for
; the same structural reason as every other multi-bar rice in this batch.
; A vivid indigo-navy/periwinkle/coral palette, genuinely its own. The
; source's own bar actually gets its background from a SEPARATE color key
; (bg-alt = #BF1D1F28, ~75% opaque) rather than the plain "bg" key this
; port originally used - a distinct, slightly darker navy, semi-
; transparent rather than solid. Corrected to match after re-checking the
; source directly.
[colors]
base   = #BF1D1F28
mantle = #BF1D1F28
surface0 = #3D435C
surface1 = #3D435C
text   = #FDFDFD
subtext = #8C8C8C
red    = #F37F97
purple = #C574DD
blue   = #8897F4
cyan   = #79E6F3
green  = #5ADECD
yellow = #F2A272

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-foreground = ${colors.blue}
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-foreground = ${colors.blue}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/silvia.ini" <<'EOF'
; Silvia - the official Gruvbox Dark palette, used as-is (unlike several
; other themes in this batch, this rice's real colors don't clash with
; anything already in this set - confirmed by checking the live themes
; directory before building). Workspace icons are a concentric-rings/dot
; pair (focused = target rings, occupied/urgent = plain ring, empty = a
; smaller dot), separated from other standalone items by the same
; vertical 3-dot bullet glyph this rice's own Isabel theme already uses
; (U+F01D9, confirmed identical by reading silvia's own real config).
; Modeled directly on github.com/gh0stzk/dotfiles' real "silvia" rice
; (config/bspwm/rices/silvia/{config,modules}.ini, read from a full
; local clone).
[colors]
base   = #3C3836
mantle = #3C3836
surface0 = #504945
surface1 = #504945
text   = #EBDBB2
subtext = #928374
red    = #CC241D
; official Gruvbox "bright" variants of red/blue - the muted/dark base
; tones above didn't have enough contrast against this theme's own dark
; background when used as text (only fine as chip backgrounds, which
; nothing here does with them).
red-light = #FB4934
pink   = #D3869B
purple = #B16286
blue   = #458588
blue-light = #83A598
cyan   = #689D6A
green  = #98971A
lime   = #8EC07C
yellow = #D79921
orange = #D65D0E

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots tray dots date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots memory dots cpu dots date

[module/dots]
type = custom/text
format = <label>
label = " 󰇙 "
label-foreground = ${colors.orange}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
label-focused = "󰺕"
label-focused-foreground = ${colors.lime}
label-focused-padding = 1
label-unfocused = "󰀚"
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = "󰀚"
label-urgent-foreground = ${colors.red-light}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.blue-light}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.pink}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.pink}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red-light}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/varinka.ini" <<'EOF'
; Varinka - a genuine near-monochrome grayscale palette: reading the
; source's own colors.ini, keys named "red"/"purple"/"blue"/"cyan"/
; "green"/"yellow" are ALL just different shades of gray in hex (e.g. its
; own "red" is #dee2e6, a light gray) - only pink and orange are real
; colors. Workspaces use literal LETTER glyphs (A, B, C, D, E, F) instead
; of numbers - confirmed by reading and render-testing the source's own
; ws-icon-N codepoints (U+F0AEE..U+F0AF3), a genuinely distinctive detail
; among every other workspace treatment in this rice's set. Modeled
; directly on github.com/gh0stzk/dotfiles' real "varinka" rice (config/
; bspwm/rices/varinka/{config,modules}.ini, read from a full local
; clone).
; The source's own bg carries an alpha channel too (FA, ~98% opaque) -
; barely transparent, but matched for fidelity rather than flattened.
[colors]
base   = #FA212529
mantle = #FA212529
surface0 = #343A40
surface1 = #343A40
text   = #F8F9FA
subtext = #6C757D
grey   = #ADB5BD
pink   = #DC5BBC
orange = #DE8658
green  = #ADB5BD
blue   = #495057

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=16;5"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰫮
ws-icon-1 = 2;󰫯
ws-icon-2 = 3;󰫰
ws-icon-3 = 4;󰫱
ws-icon-4 = 5;󰫲
ws-icon-5 = 6;󰫳
ws-icon-default = "♟"
label-focused = %icon%
label-focused-foreground = ${colors.text}
label-focused-font = 2
label-unfocused = %icon%
label-unfocused-foreground = ${colors.subtext}
label-unfocused-font = 2
label-urgent = %icon%
label-urgent-foreground = ${colors.pink}
label-urgent-font = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.pink}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-discharging-prefix = " "
format-full-prefix = " "
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/yael.ini" <<'EOF'
; Yael - a vivid IBM-Carbon-adjacent dark palette (near-black background,
; hot-pink/electric-blue/turquoise/mint accents, confirmed by reading the
; source's real colors.ini rather than the earlier thumbnail alone).
; Focused workspace gets a solid blue chip with inverted (background-
; colored) text - the source's own real label-focused-background/
; -foreground pair - while unfocused stays plain indigo text with no
; chip. Modeled directly on github.com/gh0stzk/dotfiles' real "yael"
; rice (config/bspwm/rices/yael/{config,modules}.ini, read from a full
; local clone). The source's own per-workspace icons are app-category
; glyphs (code/folder/browser/controller/heart/terminal/etc, one per
; number) too specific to the original author's own workflow to carry
; real meaning here, so plain digits are used instead - the same call
; made for this rice's own Cristina theme, which had the identical
; app-icon pattern.
[colors]
base   = #161616
mantle = #161616
surface0 = #262626
surface1 = #262626
text   = #FFFFFF
subtext = #8C8C8C
red    = #EE5396
purple = #FF7EB6
blue   = #33B1FF
cyan   = #3DDBD9
green  = #42BE65
yellow = #FFE97B
indigo = #82CFFF

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-padding = 2
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.blue}
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-padding = 2
label-unfocused-foreground = ${colors.indigo}
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-padding = 2
label-urgent-foreground = ${colors.red}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.cyan}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.red}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/z0mbi3.ini" <<'EOF'
; Z0mbi3 - a Nord-adjacent but genuinely distinct dark navy palette
; (background #0d0f18, periwinkle foreground #a5b6cf - different hex from
; the official Nord values this rice's own Nord theme already uses),
; workspace states as subtle blue-gray shade steps rather than a bright
; accent (focused #8ea6c4, occupied #6e8db4, empty #434c5e - read
; directly from the source's own real eww.scss). Modeled on github.com/
; gh0stzk/dotfiles' real "z0mbi3" rice - the repo maintainer's own
; namesake rice - but like Andrea, this one is EWW-based (bar/eww.yuck +
; bar/eww.scss), not polybar, and its real layout is a VERTICAL sidebar
; (`:orientation "v"` on its own launcher/workspace widgets, confirmed by
; reading the source directly) rather than a horizontal top bar at all -
; architecturally different from every other theme in this rice, which
; is built around a single horizontal top bar. This port keeps the
; source's real colors and workspace-state treatment but lays them out
; horizontally, the same simplification applied to every other multi-bar
; or off-position rice in this batch.
[colors]
base   = #0D0F18
mantle = #0D0F18
surface0 = #1C1E27
surface1 = #1C1E27
text   = #A5B6CF
subtext = #6E8DB4
red    = #DD6777
green  = #90CEAA
yellow = #ECD3A0
blue   = #86AAEC
magenta = #C296EB
cyan   = #93CEE9

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-foreground = ${colors.text}
label-focused-padding = 2
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-foreground = ${colors.red}
label-urgent-padding = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.blue}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %percentage%% "

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.magenta}
label-volume = " %percentage%% "
label-muted = " muted "

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.magenta}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:} %ifname% %{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-background = ${colors.surface0}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = " %percentage_used%% "

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = " %percentage%% "

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/aline-square.ini" <<'EOF'
; Aline - a light/pastel theme, the only non-dark theme in this rice's
; set. Rounded-cap bracket groups (bi/bd = U+E0B6/U+E0B4, the same
; half-circle pair Mocha's own separators and Archcraft's LD/RD use) wrap
; clusters of related widgets in one shared cream ("mc") capsule, plain
; icon-prefix-colored widgets inside - structurally close to this rice's
; own Archcraft theme (same glyph family, same "shared group background"
; idea), but never dark: bar/text/group colors are all warm cream/plum,
; not a single dark canvas anywhere. Modeled directly on github.com/
; gh0stzk/dotfiles' real "aline" rice (config/bspwm/rices/aline/
; {config,modules}.ini, read from a full local clone of the repo, not
; fetched piecemeal) - a genuine polybar config, unlike this same repo's
; "andrea"/"z0mbi3" rices which turned out to be EWW-based instead
; (checked per-rice this time, not assumed from one example). Workspaces
; get a real per-number identity here: each UNFOCUSED workspace shows its
; own uniquely-colored circled-number icon (ws-icon-N, a genuine Material
; Design "circled digit" codepoint per number) rather than a shared style,
; collapsing to a plain digit only once focused or urgent - matching the
; source's own "unique icon when empty, shared style when active" split.
; The source's own usercard/mplayer/power/colorpicker/weather modules are
; static buttons or external scripts specific to that rice's own toolkit
; (Weather/Colorpicker/OpenApps helper commands) not present in this rig,
; so they're left out rather than faked - same call this rice's other
; themes made for widgets they couldn't actually port (Summer-heat's
; Spotify/Google-Calendar, Archcraft's tray-adjacent extras). Two of the
; source's own icon codepoints (a workspace "active" check-glyph, U+F09DE,
; and a mute icon, U+F6A9) turned out to be MISSING from this rice's
; actual installed Nerd Font build when render-tested before use (one
; came back as a generic bullet placeholder, the other fully blank) -
; caught by rendering every new codepoint before writing it into a real
; file, not after; replaced with a plain digit and plain "muted" text,
; both already proven safe by every other theme in this set.
[colors]
base = #FAF4ED
mantle = #FAF4ED
surface0 = #F2E9E1
surface1 = #F2E9E1
text = #575279
subtext = #9893A5
teal = #2E7480
; Dedicated dark, fully-opaque backdrop for the system tray specifically -
; most tray icons (Discord, 1Password, etc.) are drawn in white/light
; colors expecting a dark bar and become invisible against this theme's
; own light cream chips (caught via direct feedback, not assumed).
tray-bg = #3D3757
green = #286983
yellow = #A15E15
red = #B4637A
blue = #2E5D66

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius-top = 0
radius-bottom = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center = date

[bar/top-primary]
inherit = bar/base
modules-right = backlight pulseaudio media sep network-wired network-wireless sep bluetooth caffeine dnd sep battery memory cpu sep tray

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media sep network-wired network-wireless sep memory cpu

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰬺
ws-icon-1 = 2;󰬻
ws-icon-2 = 3;󰬼
ws-icon-3 = 4;󰬽
ws-icon-4 = 5;󰬾
ws-icon-5 = 6;󰬿
ws-icon-6 = 7;󰭀
ws-icon-7 = 8;󰭁
ws-icon-8 = 9;󰭂
ws-icon-default = "♟"
label-focused = ${self.ws-label}
ws-label = %index%
label-unfocused = %icon%
label-urgent = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.blue}
label-focused-padding = 3
label-unfocused-font = 3
label-unfocused-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.red}
label-urgent-padding = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.text}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"
label-font = 3

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %percentage%% "

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.teal}
format-muted-background = ${colors.surface0}
label-volume = " %percentage%% "
label-muted = " muted "
label-muted-foreground = ${colors.red}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.teal}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:} %ifname% %{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-background = ${colors.surface0}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.text}
label = " %percentage_used%% "

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.text}
label = " %percentage%% "

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.tray-bg}
format-background = ${colors.tray-bg}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/archcraft-square.ini" <<'EOF'
; Archcraft - grouped clusters bracketed by rounded-cap decorators, where
; the group's own widgets share the SAME background as the caps so the
; whole thing reads as one seamless rounded capsule (not the cap floating
; alone with unfilled content, which was wrong on the first pass here -
; confirmed by reading the real decor.ini + modules.ini together: LD/RD
; content-foreground = ALTBACKGROUND on content-background = BACKGROUND,
; and every module they bracket (i3, tray, date) sets its own
; format-background = ALTBACKGROUND to match). Standalone items outside
; any bracket are separated by a small dot glyph instead of a divider
; line. Modeled directly on the REAL Archcraft i3wm polybar config
; (github.com/archcraft-os/archcraft-i3wm, files/theme/polybar/
; {decor,modules,colors}.ini - fetched and read directly, not guessed):
; its own LD/RD "decor" modules use exactly these two glyphs (U+E0B6/
; U+E0B4, the same half-circle pair Mocha's separators use, just
; bracketing a GROUP instead of connecting every segment) and its own
; "dot" module uses U+F444. This is the 4th genuinely distinct structure
; in this rice's theme set: Mocha connects every segment with an arrow,
; Dracula has no backgrounds anywhere, Nord groups widgets under one
; shared fill block with a real gap between groups, Archcraft groups them
; under a rounded-cap capsule shape - closest in spirit to Archcraft's
; real workspace/tray cluster on the left and clock cluster on the right
; in its own config's modules-left/modules-right, while non-bracketed
; widgets (backlight/volume/network/battery/memory/cpu) stay completely
; flat with only a colored icon prefix, matching modules.ini's own
; [module/cpu] etc exactly (format = <label>, no format-background at
; all). Colors are Archcraft's own real palette (colors.ini) - a
; One-Dark-adjacent scheme, not Catppuccin, Dracula, or Nord - mapped
; onto this rice's 15 tokens: BACKGROUND/ALTBACKGROUND -> base/mantle/
; surface0/surface1, FOREGROUND/ALTFOREGROUND -> text/subtext, MAGENTA ->
; mauve/lavender (only one purple in the source), BLUE -> blue, CYAN ->
; sky/teal, GREEN -> green, YELLOW -> yellow, ACCENT (its own highlight
; rose/pink, not a generic peach) -> peach, RED -> red.
[colors]
base     = #1e222a
mantle   = #1e222a
surface0 = #292e39
surface1 = #292e39
text     = #c8ccd4
subtext  = #727c91
mauve    = #c678dd
lavender = #c678dd
blue     = #61afef
sky      = #56b6c2
green    = #98c379
teal     = #56b6c2
yellow   = #e5c07b
peach    = #da6e89
red      = #e06c75

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
; The left cluster is the workspace switcher alone (already bracketed by
; LD/RD in bar/base); the tray gets its own small bracketed group here
; since it's primary-only. Every widget on the right is plain/unfilled,
; dot-separated, with one final LD/RD-bracketed group for the clock.
modules-left = i3 dot tray
modules-right = backlight dot pulseaudio dot media dot network-wired network-wireless dot bluetooth dot caffeine dot dnd dot battery dot memory dot cpu dot date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dot pulseaudio dot media dot network-wired network-wireless dot memory dot cpu dot date-icon date

[module/dot]
type = custom/text
format = <label>
label = "  "
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
; format-background here matches LD/RD's own foreground so the caps and
; the workspace squares fuse into one seamless capsule (the fix - without
; it the caps float alone with nothing to visually connect to).
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-visible = ${self.ws-label}
label-urgent = ${self.ws-label}
; Each workspace state pops its own accent color against the shared
; surface0 capsule background - matching the real archcraft-i3wm config's
; label-focused/-unfocused/-visible/-urgent split exactly (blue/
; unchanged/green/red there too, just using this rice's own token names).
label-focused-font = 3
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.blue}
label-focused-padding = 3
label-unfocused-font = 3
label-unfocused-foreground = ${colors.text}
label-unfocused-background = ${colors.surface0}
label-unfocused-padding = 2
label-visible-font = 3
label-visible-foreground = ${colors.base}
label-visible-background = ${colors.green}
label-visible-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.peach}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = " 󰃟 %percentage%% "
label-foreground = ${colors.yellow}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "  %percentage%% "
label-muted = " muted "
label-volume-foreground = ${colors.green}
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.green}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}  %essid% %{A}%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.sky}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "  %percentage%% "
label-discharging = "  %percentage%% "
label-full = " Full "
label-charging-foreground = ${colors.peach}
label-discharging-foreground = ${colors.peach}
label-full-foreground = ${colors.peach}

[module/memory]
type = internal/memory
interval = 2
label = "  %percentage_used%% "
label-foreground = ${colors.yellow}

[module/cpu]
type = internal/cpu
interval = 2
label = "  %percentage%% "
label-foreground = ${colors.green}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
format-background = ${colors.surface0}
tray-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/brenda-square.ini" <<'EOF'
; Brenda - flat, individually-colored two-part widgets: every widget is a
; vivid-colored icon chip immediately followed by its own cream ("mbg")
; value chip, separated from the NEXT widget by a real gap - each widget
; gets its own distinct hue (yellow/green/orange/blue/lime/red) rather
; than one accent reused everywhere. Workspaces get a genuine Pac-Man
; theme: focused = Pac-Man glyph (orange), occupied/urgent = ghost glyph
; (purple), empty = a plain moon/dot (blue-gray) - all sharing one light
; cream chip background. Modeled directly on github.com/gh0stzk/dotfiles'
; real "brenda" rice (config/bspwm/rices/brenda/{config,modules}.ini,
; read from a full local clone). An Everforest-adjacent dark-olive palette
; (bg=#2d353b, fg warm cream) - distinct from every other palette in this
; rice's theme set. One of the source's own icon choices (a battery-
; charging "plug" glyph, U+E0B7) rendered as an unrelated crescent shape
; when render-tested in this rice's actual Nerd Font build, so charging
; reuses this rice's own already-verified battery icon instead of a new,
; unverified one.
[colors]
base   = #2D353B
mantle = #2D353B
surface0 = #F8F5E4
surface1 = #F8F5E4
text   = #D3C6AA
subtext = #859289
red    = #E67E80
green  = #A7C080
yellow = #DBBC7F
blue   = #7FBBB3
purple = #D699B6
orange = #E69875
lime   = #B9C244
; darker text-safe variants for use on the light cream ("surface0") chip -
; the plain orange/purple/red above stay vivid for use as CHIP
; BACKGROUNDS (with dark text on top), where the lighter tone is correct;
; these are for text/icons drawn directly on that same light chip, which
; the vivid tones don't have enough contrast for.
orange-dark = #A8501F
purple-dark = #96406B
red-dark    = #B33440
green-dark  = #3E6E2E

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep network-icon network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery-icon battery sep memory-icon memory sep cpu-icon cpu sep tray sep date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep network-icon network-wired network-wireless sep memory-icon memory sep cpu-icon cpu sep date-icon date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = " 󰮯 "
label-focused-foreground = ${colors.orange-dark}
label-focused-padding = 1
label-unfocused = " 󰊠 "
label-unfocused-foreground = ${colors.purple-dark}
label-unfocused-padding = 1
label-urgent = " 󰊠 "
label-urgent-foreground = ${colors.red-dark}
label-urgent-padding = 1

[module/date-icon]
type = custom/text
format = <label>
format-background = ${colors.blue}
label = "  "
label-foreground = ${colors.base}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:} %date%  %time% %{A}"
label-foreground = ${colors.base}

[module/backlight-icon]
type = custom/text
format = <label>
format-background = ${colors.yellow}
label = " 󰃟 "
label-foreground = ${colors.base}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
label = " %percentage%% "
label-foreground = ${colors.base}

[module/pulseaudio-icon]
type = internal/pulseaudio
format-volume = <label-volume>
format-muted = <label-muted>
format-volume-background = ${colors.orange}
format-muted-background = ${colors.orange}
label-volume = "  "
label-volume-foreground = ${colors.base}
label-muted = "  "
label-muted-foreground = ${colors.base}

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}
label-volume = " %percentage%% "
label-muted = " muted "
label-volume-foreground = ${colors.base}
label-muted-foreground = ${colors.base}

[module/network-icon]
type = custom/text
format = <label>
format-background = ${colors.green}
label = "  "
label-foreground = ${colors.base}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.base}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green-dark}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red-dark}

[module/battery-icon]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.yellow}
format-discharging-background = ${colors.yellow}
format-full-background = ${colors.yellow}
label-charging = "  "
label-discharging = "  "
label-full = "  "
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-discharging-background = ${colors.surface0}
format-full-background = ${colors.surface0}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}

[module/memory-icon]
type = custom/text
format = <label>
format-background = ${colors.blue}
label = "  "
label-foreground = ${colors.base}

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
label = " %percentage_used%% "
label-foreground = ${colors.base}

[module/cpu-icon]
type = custom/text
format = <label>
format-background = ${colors.red}
label = "  "
label-foreground = ${colors.base}

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
label = " %percentage%% "
label-foreground = ${colors.base}

; Tray specifically uses the theme's own dark base, not the light cream
; surface0 every other widget's value-chip uses - most tray icons
; (Discord, 1Password, etc.) are drawn in white/light colors expecting a
; dark bar and become invisible against a light chip (caught via direct
; feedback, not assumed).
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.base}
format-background = ${colors.base}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/catppuccin-mocha-square.ini" <<'EOF'
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
radius = 0
padding-left = 1
padding-right = 0
module-margin = 0
; font-1 is a slightly larger slot for the powerline separator glyphs so the
; rounded caps render full-height instead of looking clipped/short next to
; the regular text baseline.
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
; last segment, farthest right.
modules-right = tray-cap tray backlight pulseaudio media network-wired network-wireless bluetooth caffeine dnd battery memory cpu date-icon date

[bar/top-secondary]
inherit = bar/base
; same as top-primary minus tray/battery - without this split every extra
; monitor showed a permanently empty tray slot since only one instance can
; ever win the X11 tray selection.
modules-right = backlight pulseaudio media network-wired network-wireless memory cpu date-icon date

; --- powerline separators ---------------------------------------------------
; Each is a plain glyph rendered in the color of the segment being LEFT
; (content-foreground) over the background of the segment being ENTERED
; (content-background) - that's what makes the rounded cap look like it
; belongs to both neighbours and reads as one continuous capsule chain.
; All of them point the same direction because the whole chain flows left to
; right; only the fg/bg pair changes per transition.
[module/tray-cap]
type = custom/text
format = <label>
label = "  "
label-background = ${colors.mauve}
label-underline = ${colors.mauve}
label-overline = ${colors.mauve}

[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
; The real centering culprit: label-focused/unfocused/urgent default to
; "%icon% %name%" - since no ws-icon-N is configured, %icon% renders empty
; but the literal space between it and %name% is still there, permanently
; skewing the visible digit right of center. ws-label pins content to just
; the index, removing that invisible leading space entirely.
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-urgent = ${self.ws-label}
; font-2 (index 3) is the plain, unpatched JetBrains Mono - kept as a minor
; extra safety margin against Nerd Font glyph-metrics quirks (nerd-fonts#991)
; on top of the ws-label fix above. No fill/background here either - polybar
; has no way to draw a rounded rectangle around dynamic per-item text, so a
; filled box always renders as a hard square; underline+overline avoids that
; entirely instead of just trying to soften it.
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

[module/date-icon]
type = custom/text
format = <label>
label = "%{A1:gnome-calendar &:}    %{A}"
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

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = "  󰃟 %percentage%% "
label-foreground = ${colors.base}
format-background = ${colors.sky}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "   %percentage%% "
label-muted = "   muted "
label-volume-foreground = ${colors.base}
label-muted-foreground = ${colors.base}
format-volume-background = ${colors.mauve}
format-muted-background = ${colors.mauve}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label. They
; share one segment color/slot since at most one of them is ever visible.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.base}
format-background = ${colors.teal}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}   %ifname% %{A}"
label-connected-foreground = ${colors.base}
format-connected-background = ${colors.blue}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}   %essid% %{A}%{A}"
label-connected-foreground = ${colors.base}
format-connected-background = ${colors.blue}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.base}
format-background = ${colors.teal}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.base}
format-background = ${colors.green}

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
battery = BAT0
adapter = AC
label-charging = "   %percentage%% "
label-discharging = "   %percentage%% "
label-full = "   Full "
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}
format-charging-background = ${colors.peach}
format-discharging-background = ${colors.peach}
format-full-background = ${colors.peach}

[module/memory]
type = internal/memory
interval = 2
label = "   %percentage_used%% "
label-foreground = ${colors.base}
format-background = ${colors.yellow}

[module/cpu]
type = internal/cpu
interval = 2
label = "   %percentage%% "
label-foreground = ${colors.base}
format-background = ${colors.green}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
; polybar's tray module has no true 4-sided border - format-underline/
; format-overline (top+bottom accent lines) is the closest it can draw to a
; frame. format-background is ALSO needed (not just tray-background, which
; per the docs only colors the individual icons, not the space around them)
; for a solid, cohesive pill instead of a transparent gap with framed icons.
format-background = ${colors.surface0}
format-underline = ${colors.mauve}
format-overline = ${colors.mauve}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/cristina-square.ini" <<'EOF'
; Cristina - individually-colored pill capsules: each quantifiable widget
; gets its OWN rounded-cap bracket pair (U+E0B6/U+E0B4, same glyph family
; as Mocha/Archcraft/Aline) in its own distinct hue, with a real gap
; between each pill instead of a shared group background or a continuous
; connected chain - a genuine third variation on the same bracket-glyph
; idea already used elsewhere in this rice's set. Non-quantifiable
; widgets (battery, bluetooth, caffeine, dnd) stay fully plain/unbracketed
; with just a colored icon prefix, matching the source's own real mixed
; treatment exactly (its battery module has no background at all, while
; its filesystem/cpu/memory/pulseaudio/network/date modules each get
; their own individual bracket pair colored to match that widget's icon).
; Modeled directly on github.com/gh0stzk/dotfiles' real "cristina" rice
; (config/bspwm/rices/cristina/{config,modules}.ini, read from a full
; local clone). A Rosé-Pine-Moon-adjacent dark purple-navy palette
; (bg=#232136, fg pale lavender). Workspaces stay plain digits directly
; on the bar's own background (no chip at all) - matching the source's
; own unbracketed workspace treatment - rather than porting its literal
; per-number app-category icon set (folder/code/gamepad/etc, ending in a
; literal toilet emoji for workspace 9), which is too specific to the
; original author's own workflow to carry meaning here.
[colors]
base   = #232136
mantle = #232136
surface0 = #39374A
text   = #E0DEF4
subtext = #908CAA
red    = #EA6F91
green  = #9BCED7
yellow = #F1CA93
blue   = #34738E
purple = #C3A5E6
orange = #F08641
indigo = #6C77BB
lime   = #8EC07C

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

; --- bracket pairs -------------------------------------------------------
[module/sep]
type = custom/text
format = <label>
label = "  "

[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-foreground = ${colors.lime}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-foreground = ${colors.purple}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.indigo}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.green}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.blue}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.blue}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.orange}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.orange}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/cynthia-square.ini" <<'EOF'
; Cynthia - deliberately monochrome and minimal: a near-black bar where
; only the workspace state colors (blue/green/red) carry any real hue at
; all - every other widget is plain icon+text directly on the bar's own
; background, with only a FEW widgets (workspace, cpu+memory together,
; network) wrapped in a single dark-gray bracket capsule (bi/bd =
; U+E0B6/U+E0B4) rather than a rainbow of individually-colored ones like
; this rice's own Cristina theme, or a shared accent like Archcraft.
; Modeled directly on github.com/gh0stzk/dotfiles' real "cynthia" rice
; (config/bspwm/rices/cynthia/{config,modules}.ini, read from a full
; local clone) - workspace numbers reuse the same circled-digit icon
; style as this rice's own Aline theme (ws-icon-N, verified render-tested
; there already), but here EVERY state (focused/occupied/urgent) keeps
; the same per-number icon and only changes color, rather than Aline's
; "unique icon only when empty" split. The source actually ships this
; rice as TWO separate bars (a top bar for workspaces/system stats, a
; bottom bar for media/weather/date) - consolidated into this rice's
; usual single top bar instead, since a real second bar is a structural
; change to the launch/gaps setup affecting every theme, not something
; to introduce for just one of them.
[colors]
base   = #181616
mantle = #181616
surface0 = #242121
surface1 = #242121
text   = #C5C9C5
subtext = #708491
red    = #E46876
green  = #87A987
blue   = #7FB4CA
purple = #938AA9
yellow = #E6C384
orange = #E57C46

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = memory cpu sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep backlight sep pulseaudio sep media sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = memory cpu sep network-wired network-wireless sep backlight sep pulseaudio sep media sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰬺
ws-icon-1 = 2;󰬻
ws-icon-2 = 3;󰬼
ws-icon-3 = 4;󰬽
ws-icon-4 = 5;󰬾
ws-icon-5 = 6;󰬿
ws-icon-6 = 7;󰭀
ws-icon-7 = 8;󰭁
ws-icon-8 = 9;󰭂
ws-icon-default = "♟"
label-focused = %icon%
label-focused-foreground = ${colors.blue}
label-focused-font = 2
label-focused-padding = 1
label-unfocused = %icon%
label-unfocused-foreground = ${colors.green}
label-unfocused-font = 2
label-unfocused-padding = 1
label-urgent = %icon%
label-urgent-foreground = ${colors.red}
label-urgent-font = 2
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/daniela-square.ini" <<'EOF'
; Daniela - flat text-label widgets: instead of an icon glyph, each
; widget's own prefix is a literal colored WORD ("CPU", "RAM", "NET",
; "VOL", "BAT") with a plain, unstyled value next to it - no background
; anywhere, no divider between widgets, each label just its own color
; directly on the bar. Genuinely different from every icon-based theme in
; this rice's set. Modeled directly on github.com/gh0stzk/dotfiles' real
; "daniela" rice (config/bspwm/rices/daniela/{config,modules}.ini, read
; from a full local clone): its own cpu_bar/memory_bar/etc modules
; literally set format-prefix to the word "CPU"/"RAM" (font-1, colored),
; confirmed by reading the actual module bodies rather than guessing from
; the screenshot alone. The source's own color palette turned out to be
; Catppuccin Mocha's exact hex values reused wholesale (bg=#181825,
; fg=#cdd6f4, same red/blue/green/yellow/purple as this rice's own
; catppuccin-mocha.ini) - porting it as-is would make two themes in this
; set look color-identical, so this port keeps daniela's real STRUCTURE
; (word-prefix, fully flat, no backgrounds) but uses a fresh Tokyo-Night-
; adjacent palette instead, distinct from every other theme here.
[colors]
base   = #1A1B26
mantle = #1A1B26
surface0 = #31323C
text   = #C0CAF5
subtext = #565F89
red    = #F7768E
green  = #9ECE6A
yellow = #E0AF68
blue   = #7AA2F7
purple = #BB9AF7
cyan   = #7DCFFF
orange = #FF9E64

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight pulseaudio media network-wired network-wireless bluetooth caffeine dnd battery memory cpu tray date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media network-wired network-wireless memory cpu date

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-foreground = ${colors.blue}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.orange}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "BRT "
format-prefix-font = 1
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = "VOL "
format-volume-prefix-font = 1
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.red}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = "NET "
format-connected-prefix-font = 1
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = "NET "
format-connected-prefix-font = 1
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = "BAT "
format-charging-prefix-font = 1
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = "BAT "
format-discharging-prefix-font = 1
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = "BAT "
format-full-prefix-font = 1
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = "RAM "
format-prefix-font = 1
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-font = 1
format-prefix-foreground = ${colors.blue}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/dracula-square.ini" <<'EOF'
; Dracula - flat, minimal, no powerline pills anywhere. Modeled directly on
; the ACTUAL github.com/dracula/i3 port (confirmed by reading its real
; config, not assumed): that setup is i3bar/i3status-based, not polybar,
; and renders almost everything as plain statusline text - the workspace
; switcher is the only element that ever gets a filled background, and
; only for the FOCUSED state; every other widget is just colored text
; separated by a plain "|" divider in the muted "Current Line" tone
; (#44475a), which is also i3status's own real separator color in that
; config. Ported to polybar (this rice's bar of choice throughout) rather
; than switching to i3bar/i3status, keeping every widget this rice already
; has (tray, caffeine, DND, etc. - none of which exist in the plain
; i3status world) but restyled to match that flat philosophy instead of
; Catppuccin Mocha's segmented powerline-pill one.
[colors]
base     = #282a36
mantle   = #282a36
surface0 = #44475a
surface1 = #44475a
text     = #f8f8f2
subtext  = #6272a4
mauve    = #bd93f9
lavender = #ff79c6
blue     = #6272a4
sky      = #8be9fd
green    = #50fa7b
teal     = #8be9fd
yellow   = #f1fa8c
peach    = #ffb86c
red      = #ff5555

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
; The tray needs SOME background to give its icons a defined, clickable
; area - everything else here is flat text, so a small muted box (Current
; Line, not an accent) reads as "a container", not "another pill in a
; powerline chain" the way Mocha's mauve tray-cap did.
modules-right = tray sep-plain backlight sep-plain pulseaudio sep-plain media sep-plain network-wired network-wireless sep-plain bluetooth sep-plain caffeine sep-plain dnd sep-plain battery sep-plain memory sep-plain cpu sep-plain date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep-plain pulseaudio sep-plain media sep-plain network-wired network-wireless sep-plain memory sep-plain cpu sep-plain date-icon date

[module/sep-plain]
type = custom/text
format = <label>
label = "|"
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-urgent = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.text}
label-focused-background = ${colors.surface0}
label-focused-padding = 3
; Unfocused workspaces get NO background at all (not even the bar's own
; color explicitly set) - just muted text directly on the bar, matching
; the real dracula/i3 config's own inactive-workspace treatment exactly
; (its bg is literally the bar's own background - the box is invisible
; until focused).
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
label = "%{A1:gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.mauve}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = " 󰃟 %percentage%%"
label-foreground = ${colors.yellow}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "  %percentage%%"
label-muted = "  muted"
label-volume-foreground = ${colors.green}
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.green}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}  %essid%%{A}%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.sky}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "  %percentage%%"
label-discharging = "  %percentage%%"
label-full = " Full"
label-charging-foreground = ${colors.peach}
label-discharging-foreground = ${colors.peach}
label-full-foreground = ${colors.peach}

[module/memory]
type = internal/memory
interval = 2
label = "  %percentage_used%%"
label-foreground = ${colors.yellow}

[module/cpu]
type = internal/cpu
interval = 2
label = "  %percentage%%"
label-foreground = ${colors.green}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/emilia-square.ini" <<'EOF'
; Emilia - individually-bracketed capsules again (like this rice's own
; Cristina theme), but every bracket shares the SAME muted color instead
; of a rainbow of per-widget hues - a sea of small uniform dark-gray
; pills, each holding just one (or occasionally two related) widgets,
; real gaps between them. Workspaces reuse the same Pac-Man/ghost/moon
; icon set as this rice's own Brenda theme (label-focused/-occupied/
; -urgent/-empty = U+F0BAF/U+F02A0/U+F02A0/U+F044A, confirmed identical
; codepoints by reading both sources directly) but structured completely
; differently: Brenda pairs a vivid icon-chip with a separate value-chip
; for every widget, Emilia wraps each whole widget in one plain muted
; bracket instead. Modeled directly on github.com/gh0stzk/dotfiles' real
; "emilia" rice (config/bspwm/rices/emilia/{config,modules}.ini, read
; from a full local clone). The source's own real palette turned out to
; be Tokyo Night again (same exact hex values already used for this
; rice's own Daniela theme, built earlier in this same batch) - reusing
; it here too would make two themes look color-identical, so this port
; uses a fresh warm copper/amber palette instead, distinct from every
; other theme built so far.
[colors]
base   = #1E1A17
mantle = #1E1A17
surface0 = #2B241F
surface1 = #2B241F
text   = #E8DCC8
subtext = #9C8F7D
red    = #D9736A
green  = #A8B562
yellow = #E0A458
blue   = #7FA5B5
purple = #B08BBB
orange = #D98E4A

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = backlight sep pulseaudio sep media
modules-center = i3

[bar/top-primary]
inherit = bar/base
modules-right = network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- bracket pairs -------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-foreground = ${colors.blue}
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-background = ${colors.surface0}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/h4ck3r-square.ini" <<'EOF'
; H4ck3r - a deliberately monochrome green-on-black "matrix terminal"
; palette: the source's own colors.ini names keys "red"/"purple"/"blue"/
; "yellow" but EVERY one of them is actually some shade of green in hex
; (confirmed by reading the real hex values, not the key names - e.g.
; its own "red" is #6DDE00) - a hacker-aesthetic monochrome scheme
; disguised as a normal multi-hue palette. This port keeps that same
; "everything is a shade of green" idea honestly (no literal reds/blues
; anywhere) rather than reading the key names at face value. Workspace
; icons are a genuine reticle/skull/dot set (focused = targeting
; reticle, occupied/urgent = skull, empty = plain dot), all sharing one
; dark chip background. Modeled directly on github.com/gh0stzk/dotfiles'
; real "h4ck3r" rice (config/bspwm/rices/h4ck3r/{config,modules}.ini,
; read from a full local clone) - its own left-side network-info/VPN-
; status/target-lock modules are custom scripts specific to that rice's
; own security-tool workflow, not part of this rig, so left out rather
; than faked, same call made for other themes' unportable widgets.
[colors]
base   = #0C1018
mantle = #0C1018
surface0 = #1B2333
surface1 = #1B2333
text   = #00FA5C
subtext = #578A29
green  = #00FA5C
yellow = #76EA00
lime   = #9CF542
red    = #6DDE00

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󱓇"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 2
label-unfocused = "󰚌"
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent = "󰚌"
label-urgent-foreground = ${colors.lime}
label-urgent-padding = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.subtext}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-discharging-prefix = " "
format-full-prefix = " "
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/hidrot-square.ini" <<'EOF'
; Hidrot - three separate floating clusters bracketed by NEUTRAL rounded
; caps (U+E0B6/U+E0B4, same glyph family as Mocha/Archcraft/Aline/Marisol)
; that match each cluster's own content background rather than a vivid
; accent - the workspace cluster, and a rainbow-icon cluster where every
; widget gets its OWN distinct vivid icon-chip color (blue/aqua/green/
; purple/yellow/red) against one shared neutral value-chip background,
; confirmed by reading the source's own real per-widget files directly
; (each sets format-prefix-background to a different accent, format-
; background to the same neutral bg1 throughout). Modeled directly on
; github.com/Murzchnvok/polybar-collection's real "hidrot" theme (themes/
; hidrot/*.ini, read from a full local clone) - like its sibling "murz"
; (this rice's own theme by the same name, later removed by request),
; colors come from a separate, swappable colorscheme file; its three
; bundled colorschemes (gruvbox/nord/onedark) are all already used
; elsewhere in this rice's set, so this port uses a fresh graphite-blue
; palette instead. The source's own background is semi-transparent - but
; this rice's own Marisol theme already went fully transparent once and
; had to be walked back after real feedback found it illegible against
; an actual wallpaper, so hidrot ships at a safer ~90% opacity from the
; start instead of repeating that mistake. Workspace state icons and the
; system tray both get real attention up front for the same reason:
; explicit padding and a comfortably large font on the workspace glyphs
; (this rice's own Jan/Karla/Varinka all needed that fixed in after the
; fact), and a dedicated dark, opaque tray backdrop independent of the
; rest of the palette (Aline/Brenda both needed that fixed in after the
; fact too, since most tray icons are drawn expecting a dark bar).
[colors]
base   = #E61B1E24
mantle = #E61B1E24
surface0 = #262B33
surface1 = #262B33
text   = #D6DCE5
subtext = #6E7684
green0 = #7CB88F
purple0 = #B08FD1
blue0  = #6E93C7
red0   = #D9707A
blue1  = #5E8FCC
aqua1  = #4FB0A6
green1 = #7BBF7E
purple1 = #B08FD1
yellow1 = #D9B25C
red1   = #D9707A
tray-bg = #14161A

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3

[bar/top-primary]
inherit = bar/base
modules-center = date-icon date
modules-right = backlight pulseaudio media sep network-wired network-wireless bluetooth caffeine dnd battery memory cpu sep tray

[bar/top-secondary]
inherit = bar/base
modules-center = date-icon date
modules-right = backlight pulseaudio media sep network-wired network-wireless memory cpu

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󰄰"
label-focused-foreground = ${colors.green0}
label-focused-font = 2
label-focused-padding = 2
label-unfocused = "󰄰"
label-unfocused-foreground = ${colors.blue0}
label-unfocused-font = 2
label-unfocused-padding = 2
label-urgent = "󰄰"
label-urgent-foreground = ${colors.red0}
label-urgent-font = 2
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
format-background = ${colors.surface0}
label = "󱑎"
label-foreground = ${colors.green1}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:} %date%  %time% %{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰖨 "
format-prefix-background = ${colors.blue1}
format-prefix-foreground = ${colors.base}
label = " %percentage%% "

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-volume-prefix = "󰕾 "
format-volume-prefix-background = ${colors.yellow1}
format-volume-prefix-foreground = ${colors.base}
format-muted-background = ${colors.surface0}
format-muted-prefix = "󰖁 "
format-muted-prefix-background = ${colors.red1}
format-muted-prefix-foreground = ${colors.base}
label-volume = " %percentage%% "
label-muted = " muted "

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.yellow1}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = "󰒍 "
format-connected-prefix-background = ${colors.green1}
format-connected-prefix-foreground = ${colors.base}
label-connected = "%{A1:nm-connection-editor &:} %ifname% %{A}"
format-disconnected-background = ${colors.surface0}
format-disconnected-prefix = "󰒎 "
format-disconnected-prefix-background = ${colors.red1}
format-disconnected-prefix-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = "󰖩 "
format-connected-prefix-background = ${colors.green1}
format-connected-prefix-foreground = ${colors.base}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green0}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red0}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = "󰠠 "
format-charging-prefix-background = ${colors.aqua1}
format-charging-prefix-foreground = ${colors.base}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = "󰠠 "
format-discharging-prefix-background = ${colors.blue1}
format-discharging-prefix-foreground = ${colors.base}
format-full-background = ${colors.surface0}
format-full-prefix = "󰠠 "
format-full-prefix-background = ${colors.green1}
format-full-prefix-foreground = ${colors.base}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = "󰘚 "
format-prefix-background = ${colors.green1}
format-prefix-foreground = ${colors.base}
label = " %percentage_used%% "

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = "󰍛 "
format-prefix-background = ${colors.purple1}
format-prefix-foreground = ${colors.base}
label = " %percentage%% "

; Explicit dark, opaque tray backdrop - most tray icons (Discord,
; 1Password, etc.) are drawn in white/light colors expecting a dark bar,
; and this theme's own bar background is only ~90% opaque, not a fully
; reliable backdrop by itself.
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.tray-bg}
format-background = ${colors.tray-bg}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/isabel-square.ini" <<'EOF'
; Isabel - deliberately understated: no chip backgrounds anywhere, no
; per-state color coding at all (focused/occupied/urgent workspaces all
; share the SAME plain foreground color - only the icon SHAPE tells them
; apart, confirmed by reading the source's own [module/bspwm] block,
; which sets every state's label-*-foreground to the same ${color.fg}).
; Standalone items are separated by a real visible vertical 3-dot bullet
; glyph (U+F01D9, colored) instead of a plain gap or a divider line -
; distinct from every other separator style in this rice's set. Reuses
; the same Pac-Man/ghost/moon workspace icon family as this rice's own
; Brenda and Emilia themes (confirmed identical codepoints, U+F0BAF/
; U+F02A0/U+F044A, by reading isabel's own real config) - the third of
; this batch to use it, since that really is what the source itself
; ships - but structured completely differently again: no chip, no
; bracket, no state color, just the bare icon on the bar. Modeled
; directly on github.com/gh0stzk/dotfiles' real "isabel" rice (config/
; bspwm/rices/isabel/{config,modules}.ini, read from a full local
; clone). The source's own palette turned out to be an Atom-One-Dark-
; adjacent scheme, already close to this rice's own Archcraft theme, so
; this port uses a fresh teal/mint dark palette instead to stay visually
; distinct.
[colors]
base   = #10181A
mantle = #10181A
surface0 = #282F31
text   = #A8C5C0
subtext = #5C7B76
teal   = #4FD6BE
green  = #7FBF8F
yellow = #D6B35C
red    = #D67F7F
blue   = #5FA8C7

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots tray dots date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots memory dots cpu dots date

[module/dots]
type = custom/text
format = <label>
label = " 󰇙 "
label-foreground = ${colors.teal}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-discharging-prefix = " "
format-full-prefix = " "
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/jan-square.ini" <<'EOF'
; Jan - a genuine Synthwave '84-adjacent neon palette: deep navy-purple
; background, hot-pink/electric-blue/neon-green/neon-yellow accents, no
; muted tones anywhere. The vivid high-contrast direction this rice
; considered early on (before settling on Archcraft/Nord/Dracula) shows
; up for real here, sourced rather than invented. Reuses the same
; circled-digit workspace icon family as this rice's own Aline/Cynthia
; themes (ws-icon-N, already verified rendering), but the focused state
; wraps its icon in literal square brackets ("[icon]", confirmed by
; reading the source's own label-focused = "[%icon%]") - a small but
; genuine detail distinct from either of those. Modeled directly on
; github.com/gh0stzk/dotfiles' real "jan" rice (config/bspwm/rices/jan/
; {config,modules}.ini, read from a full local clone). One of the
; source's own separator glyphs (U+F7C6) rendered fully blank when
; render-tested in this rice's actual Nerd Font build, so a plain gap is
; used instead, matching the same fix applied for other themes' missing
; glyphs in this batch.
; The source's own bg carries an alpha channel too (E6, ~90% opaque) -
; a subtle transparency this port matches rather than a flat opaque fill.
[colors]
base   = #E6212A4C
mantle = #E6212A4C
surface0 = #14192E
text   = #27FBFE
subtext = #6B7BB0
pink   = #FB007A
magenta = #F200F4
blue   = #19BFFE
green  = #00FF00
lime   = #8DF202
yellow = #F2ED00
orange = #DB330A
purple = #6800D2

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰬺
ws-icon-1 = 2;󰬻
ws-icon-2 = 3;󰬼
ws-icon-3 = 4;󰬽
ws-icon-4 = 5;󰬾
ws-icon-5 = 6;󰬿
ws-icon-6 = 7;󰭀
ws-icon-7 = 8;󰭁
ws-icon-8 = 9;󰭂
ws-icon-default = "♟"
label-focused = "[%icon%]"
label-focused-foreground = ${colors.pink}
label-focused-font = 2
label-unfocused = %icon%
label-unfocused-foreground = ${colors.lime}
label-unfocused-font = 2
label-urgent = %icon%
label-urgent-foreground = ${colors.orange}
label-urgent-font = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.blue}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.blue}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.pink}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.blue}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.pink}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.pink}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.pink}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.yellow}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.pink}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/karla-square.ini" <<'EOF'
; Karla - vivid magenta/purple/electric-blue palette, widgets separated
; by a plain "|" pipe divider (an actual ASCII pipe, not a Nerd Font
; glyph - confirmed from the source's own [module/sep], `label = "|"`)
; rather than any powerline shape - the simplest divider style in this
; rice's whole theme set. Reuses the same targeting-reticle focused-
; workspace icon as this rice's own H4ck3r theme (U+F14C7, already
; verified rendering there), but on a vivid rather than monochrome
; palette, and with no color distinction between focused/unfocused
; (matching the source's own [module/bspwm], which sets both to the same
; plain foreground). Modeled directly on github.com/gh0stzk/dotfiles'
; real "karla" rice (config/bspwm/rices/karla/{config,modules}.ini, read
; from a full local clone) - the source actually ships this rice as
; THREE separate bars (system stats, media/battery/network, and a
; third bar just for centered workspaces), consolidated here into this
; rice's usual single top bar for the same reason Cynthia's two bars
; were: a real second or third bar is a structural change to the launch
; setup affecting every theme, not a per-theme decision.
; The source's own bg carries an alpha channel too (D9, ~85% opaque) -
; a subtle transparency this port matches rather than a flat opaque fill.
[colors]
base   = #D90E1113
mantle = #D90E1113
surface0 = #26292B
text   = #AFB1DB
subtext = #6272A4
red    = #E7034A
pink   = #F05393
purple = #7A44E3
blue   = #4856D4
cyan   = #7DF0F0
green  = #0FD94F
yellow = #F7F23F
orange = #F98860

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = " | "
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = "󱓇"
label-focused-foreground = ${colors.pink}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-foreground = ${colors.text}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.blue}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.red}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.blue}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.pink}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/marisol-square.ini" <<'EOF'
; Marisol - one shared dark-gray chip wraps the whole workspace cluster
; (format-level background, no bracket caps at all) - a 4th distinct
; structural treatment of the same Pac-Man/ghost workspace icon family
; already used by this rice's own Brenda (2-part icon+value chips),
; Emilia (individual mb-brackets per widget) and reused again here
; (confirmed identical codepoints, U+F0BAF/U+F02A0, by reading marisol's
; own real config) - genuinely the source's own shared default icon set
; across many of its rices, not a coincidence on this port's part.
; Modeled directly on github.com/gh0stzk/dotfiles' real "marisol" rice
; (config/bspwm/rices/marisol/{config,modules}.ini, read from a full
; local clone). The source's own palette turned out to be the official
; Dracula theme's exact hex values (bg=#282a36, fg=#f8f8f2, same reds/
; purples/greens as this rice's own catppuccin-adjacent Dracula theme) -
; reusing it here would make two themes look color-identical, so this
; port uses a fresh warm coral/salmon palette instead. The source's own
; bar background is ${color.trans} - fully transparent (alpha 00), not
; its opaque "bg" - only the workspace's own grey chip and individual
; widget colors are ever visible, floating directly over the wallpaper.
; A first pass ported that literally (alpha 00) - but real-world feedback
; against an actual (light) wallpaper found the theme's own light text
; unreadable with nothing behind it at all, since a fully transparent bar
; inherits whatever's on the desktop rather than anything this theme
; controls. Kept mostly-transparent (still see-through, still distinct
; from every fully-opaque theme in this set) but backed by enough of its
; own dark fill (alpha E6, ~90% opaque) that text and icons stay legible
; regardless of wallpaper - readability over literal source fidelity.
[colors]
base   = #E6241C1C
mantle = #E6241C1C
surface0 = #332727
surface1 = #332727
text   = #F5E6E0
subtext = #A8827C
red    = #E8604C
pink   = #E68A9E
yellow = #E8B84C
blue   = #6FA8C7
green  = #7FBF8F
purple = #B98FC7

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; Rounded-cap brackets around the workspace cluster (requested directly:
; "would be nice if the brown background around virtual desktop indicator
; had rounded corners") - the same U+E0B6/U+E0B4 half-circle pair Mocha's
; own separators and this rice's Archcraft/Aline/Cynthia use, foreground
; matching the workspace chip's own background so the caps and the
; content between them fuse into one seamless rounded pill instead of a
; flat-edged rectangle.
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-foreground = ${colors.blue}
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

; Explicit dark, opaque tray backdrop - most tray icons (Discord,
; 1Password, etc.) are drawn in white/light colors expecting a dark bar,
; and this theme's own bar background is only ~90% opaque, not a fully
; reliable backdrop by itself.
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/nord-square.ini" <<'EOF'
; Nord - grouped flat "islands" with real gaps between groups, no dividers
; within a group. Modeled on the actual layout style seen in stav121/
; i3wm-themer's own theme screenshots (github.com/stav121/i3wm-themer,
; themes/screenshots/*.png - fetched and looked at directly, not just
; described) and Jfeatherstone/i3-themes' Bebop theme (same - the real
; bebop_busy.png screenshot, not a text summary of it): related stats
; (volume/network/bluetooth, battery/memory/cpu) sit together in one
; shared-background block with no separator between them, icons alone
; carrying the color, then a real empty gap - not a divider glyph, not
; another color transition - before the next block starts. Genuinely
; different from this rice's other 2 themes: Mocha's segments are all
; physically CONNECTED by powerline arrows into one continuous ribbon,
; Dracula has NO backgrounds anywhere except the focused workspace: Nord
; sits in between - grouped flat blocks, gaps, no arrows. Colors are the
; official Nord palette (nordtheme.com).
[colors]
base     = #2e3440
mantle   = #2e3440
surface0 = #3b4252
surface1 = #434c5e
text     = #eceff4
subtext  = #d8dee9
mauve    = #b48ead
lavender = #81a1c1
blue     = #5e81ac
sky      = #88c0d0
green    = #a3be8c
teal     = #8fbcbb
yellow   = #ebcb8b
peach    = #d08770
red      = #bf616a
; lighter text-safe variant of red for the DND label - the plain red
; above is used as a chip background (fine as-is), but its own hex is
; too close in luminance to the dark surface0 chip when used as text.
red-light = #E098A0

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
; 4 grouped blocks (system stats / power-adjacent / tray / clock), each a
; single shared-background island with its own widgets packed tight inside
; (no divider between them - only the icon color tells them apart), a real
; empty gap-nord module between islands instead of a colored separator.
modules-right = backlight pulseaudio media network-wired network-wireless bluetooth gap-nord caffeine dnd battery gap-nord memory cpu gap-nord tray gap-nord date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media network-wired network-wireless gap-nord memory cpu gap-nord date-icon date

[module/gap-nord]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-unfocused = ${self.ws-label}
label-urgent = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.text}
label-focused-background = ${colors.surface0}
label-focused-padding = 3
; Unfocused workspaces get NO background at all - just muted text directly
; on the bar, same restrained treatment the i3wm-themer/Bebop screenshots
; use for inactive workspace numbers (a flat number, not a colored pill).
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
label = "%{A1:gnome-calendar &:} 󰃰 %{A}"
label-font = 1
label-foreground = ${colors.lavender}
format-background = ${colors.surface0}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}
format-background = ${colors.surface0}

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
label = " 󰃟 %percentage%% "
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "  %percentage%% "
label-muted = " muted "
label-volume-foreground = ${colors.green}
label-muted-foreground = ${colors.subtext}
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.green}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.sky}
format-connected-background = ${colors.surface0}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}  %essid% %{A}%{A}"
label-connected-foreground = ${colors.sky}
format-connected-background = ${colors.surface0}
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.sky}
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}
format-background = ${colors.surface0}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red-light}
format-background = ${colors.surface0}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "  %percentage%% "
label-discharging = "  %percentage%% "
label-full = " Full "
label-charging-foreground = ${colors.peach}
label-discharging-foreground = ${colors.peach}
label-full-foreground = ${colors.peach}
format-charging-background = ${colors.surface0}
format-discharging-background = ${colors.surface0}
format-full-background = ${colors.surface0}

[module/memory]
type = internal/memory
interval = 2
label = "  %percentage_used%% "
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}

[module/cpu]
type = internal/cpu
interval = 2
label = "  %percentage%% "
label-foreground = ${colors.green}
format-background = ${colors.surface0}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/pamela-square.ini" <<'EOF'
; Pamela - a 5th distinct treatment of the same Pac-Man/ghost workspace
; icon family this rice's own Brenda/Emilia/Isabel/Marisol themes already
; use (confirmed identical codepoints again by reading pamela's own real
; config) - here with NO chip background at all, but WITH per-state color
; (yellow focused, blue occupied/urgent), splitting the difference
; between Isabel's fully-plain no-color treatment and the others' boxed
; ones. Modeled directly on github.com/gh0stzk/dotfiles' real "pamela"
; rice (config/bspwm/rices/pamela/{config,modules}.ini, read from a full
; local clone) - the source actually ships this rice as SIX separate
; bars (launcher, workspaces, media, system stats, date, and a sixth for
; tray/weather/updates), by far the most bar-split rice in the whole
; collection, consolidated here into this rice's usual single bar for
; the same structural reason as every other multi-bar rice in this batch.
; A vivid indigo-navy/periwinkle/coral palette, genuinely its own. The
; source's own bar actually gets its background from a SEPARATE color key
; (bg-alt = #BF1D1F28, ~75% opaque) rather than the plain "bg" key this
; port originally used - a distinct, slightly darker navy, semi-
; transparent rather than solid. Corrected to match after re-checking the
; source directly.
[colors]
base   = #BF1D1F28
mantle = #BF1D1F28
surface0 = #3D435C
surface1 = #3D435C
text   = #FDFDFD
subtext = #8C8C8C
red    = #F37F97
purple = #C574DD
blue   = #8897F4
cyan   = #79E6F3
green  = #5ADECD
yellow = #F2A272

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
label-focused = "󰮯"
label-focused-foreground = ${colors.yellow}
label-focused-padding = 1
label-unfocused = "󰊠"
label-unfocused-foreground = ${colors.blue}
label-unfocused-padding = 1
label-urgent = "󰊠"
label-urgent-foreground = ${colors.blue}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/silvia-square.ini" <<'EOF'
; Silvia - the official Gruvbox Dark palette, used as-is (unlike several
; other themes in this batch, this rice's real colors don't clash with
; anything already in this set - confirmed by checking the live themes
; directory before building). Workspace icons are a concentric-rings/dot
; pair (focused = target rings, occupied/urgent = plain ring, empty = a
; smaller dot), separated from other standalone items by the same
; vertical 3-dot bullet glyph this rice's own Isabel theme already uses
; (U+F01D9, confirmed identical by reading silvia's own real config).
; Modeled directly on github.com/gh0stzk/dotfiles' real "silvia" rice
; (config/bspwm/rices/silvia/{config,modules}.ini, read from a full
; local clone).
[colors]
base   = #3C3836
mantle = #3C3836
surface0 = #504945
surface1 = #504945
text   = #EBDBB2
subtext = #928374
red    = #CC241D
; official Gruvbox "bright" variants of red/blue - the muted/dark base
; tones above didn't have enough contrast against this theme's own dark
; background when used as text (only fine as chip backgrounds, which
; nothing here does with them).
red-light = #FB4934
pink   = #D3869B
purple = #B16286
blue   = #458588
blue-light = #83A598
cyan   = #689D6A
green  = #98971A
lime   = #8EC07C
yellow = #D79921
orange = #D65D0E

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots tray dots date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots network-wired network-wireless dots memory dots cpu dots date

[module/dots]
type = custom/text
format = <label>
label = " 󰇙 "
label-foreground = ${colors.orange}

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
label-focused = "󰺕"
label-focused-foreground = ${colors.lime}
label-focused-padding = 1
label-unfocused = "󰀚"
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = "󰀚"
label-urgent-foreground = ${colors.red-light}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.blue-light}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.pink}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.pink}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red-light}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/varinka-square.ini" <<'EOF'
; Varinka - a genuine near-monochrome grayscale palette: reading the
; source's own colors.ini, keys named "red"/"purple"/"blue"/"cyan"/
; "green"/"yellow" are ALL just different shades of gray in hex (e.g. its
; own "red" is #dee2e6, a light gray) - only pink and orange are real
; colors. Workspaces use literal LETTER glyphs (A, B, C, D, E, F) instead
; of numbers - confirmed by reading and render-testing the source's own
; ws-icon-N codepoints (U+F0AEE..U+F0AF3), a genuinely distinctive detail
; among every other workspace treatment in this rice's set. Modeled
; directly on github.com/gh0stzk/dotfiles' real "varinka" rice (config/
; bspwm/rices/varinka/{config,modules}.ini, read from a full local
; clone).
; The source's own bg carries an alpha channel too (FA, ~98% opaque) -
; barely transparent, but matched for fidelity rather than flattened.
[colors]
base   = #FA212529
mantle = #FA212529
surface0 = #343A40
surface1 = #343A40
text   = #F8F9FA
subtext = #6C757D
grey   = #ADB5BD
pink   = #DC5BBC
orange = #DE8658
green  = #ADB5BD
blue   = #495057

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=16;5"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-icon-0 = 1;󰫮
ws-icon-1 = 2;󰫯
ws-icon-2 = 3;󰫰
ws-icon-3 = 4;󰫱
ws-icon-4 = 5;󰫲
ws-icon-5 = 6;󰫳
ws-icon-default = "♟"
label-focused = %icon%
label-focused-foreground = ${colors.text}
label-focused-font = 2
label-unfocused = %icon%
label-unfocused-foreground = ${colors.subtext}
label-unfocused-font = 2
label-urgent = %icon%
label-urgent-foreground = ${colors.pink}
label-urgent-font = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.pink}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-discharging-prefix = " "
format-full-prefix = " "
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/yael-square.ini" <<'EOF'
; Yael - a vivid IBM-Carbon-adjacent dark palette (near-black background,
; hot-pink/electric-blue/turquoise/mint accents, confirmed by reading the
; source's real colors.ini rather than the earlier thumbnail alone).
; Focused workspace gets a solid blue chip with inverted (background-
; colored) text - the source's own real label-focused-background/
; -foreground pair - while unfocused stays plain indigo text with no
; chip. Modeled directly on github.com/gh0stzk/dotfiles' real "yael"
; rice (config/bspwm/rices/yael/{config,modules}.ini, read from a full
; local clone). The source's own per-workspace icons are app-category
; glyphs (code/folder/browser/controller/heart/terminal/etc, one per
; number) too specific to the original author's own workflow to carry
; real meaning here, so plain digits are used instead - the same call
; made for this rice's own Cristina theme, which had the identical
; app-icon pattern.
[colors]
base   = #161616
mantle = #161616
surface0 = #262626
surface1 = #262626
text   = #FFFFFF
subtext = #8C8C8C
red    = #EE5396
purple = #FF7EB6
blue   = #33B1FF
cyan   = #3DDBD9
green  = #42BE65
yellow = #FFE97B
indigo = #82CFFF

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-padding = 2
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.blue}
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-padding = 2
label-unfocused-foreground = ${colors.indigo}
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-padding = 2
label-urgent-foreground = ${colors.red}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.cyan}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%percentage%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.purple}
label-volume = "%percentage%%"
label-muted = "muted"

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:}%essid%%{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"

[module/memory]
type = internal/memory
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.purple}
label = "%percentage_used%%"

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.red}
label = "%percentage%%"

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/z0mbi3-square.ini" <<'EOF'
; Z0mbi3 - a Nord-adjacent but genuinely distinct dark navy palette
; (background #0d0f18, periwinkle foreground #a5b6cf - different hex from
; the official Nord values this rice's own Nord theme already uses),
; workspace states as subtle blue-gray shade steps rather than a bright
; accent (focused #8ea6c4, occupied #6e8db4, empty #434c5e - read
; directly from the source's own real eww.scss). Modeled on github.com/
; gh0stzk/dotfiles' real "z0mbi3" rice - the repo maintainer's own
; namesake rice - but like Andrea, this one is EWW-based (bar/eww.yuck +
; bar/eww.scss), not polybar, and its real layout is a VERTICAL sidebar
; (`:orientation "v"` on its own launcher/workspace widgets, confirmed by
; reading the source directly) rather than a horizontal top bar at all -
; architecturally different from every other theme in this rice, which
; is built around a single horizontal top bar. This port keeps the
; source's real colors and workspace-state treatment but lays them out
; horizontally, the same simplification applied to every other multi-bar
; or off-position rice in this batch.
[colors]
base   = #0D0F18
mantle = #0D0F18
surface0 = #1C1E27
surface1 = #1C1E27
text   = #A5B6CF
subtext = #6E8DB4
red    = #DD6777
green  = #90CEAA
yellow = #ECD3A0
blue   = #86AAEC
magenta = #C296EB
cyan   = #93CEE9

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep network-wired network-wireless sep memory sep cpu sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 2
label-focused-foreground = ${colors.text}
label-focused-padding = 2
label-unfocused = ${self.ws-label}
label-unfocused-font = 2
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent = ${self.ws-label}
label-urgent-font = 2
label-urgent-foreground = ${colors.red}
label-urgent-padding = 2

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
format-prefix = " "
format-prefix-foreground = ${colors.blue}
label = "%{A1:gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %percentage%% "

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-muted-background = ${colors.surface0}
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.magenta}
label-volume = " %percentage%% "
label-muted = " muted "

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.magenta}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:} %ifname% %{A}"
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = " "
format-connected-prefix-foreground = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.cyan}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.yellow}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.yellow}
format-full-background = ${colors.surface0}
format-full-prefix = " "
format-full-prefix-foreground = ${colors.green}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = " %percentage_used%% "

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = " "
label = " %percentage%% "

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF


cat > "$CONF/polybar/themes/hidrot.ini" <<'EOF'
; Hidrot - three separate floating clusters bracketed by NEUTRAL rounded
; caps (U+E0B6/U+E0B4, same glyph family as Mocha/Archcraft/Aline/Marisol)
; that match each cluster's own content background rather than a vivid
; accent - the workspace cluster, and a rainbow-icon cluster where every
; widget gets its OWN distinct vivid icon-chip color (blue/aqua/green/
; purple/yellow/red) against one shared neutral value-chip background,
; confirmed by reading the source's own real per-widget files directly
; (each sets format-prefix-background to a different accent, format-
; background to the same neutral bg1 throughout). Modeled directly on
; github.com/Murzchnvok/polybar-collection's real "hidrot" theme (themes/
; hidrot/*.ini, read from a full local clone) - like its sibling "murz"
; (this rice's own theme by the same name, later removed by request),
; colors come from a separate, swappable colorscheme file; its three
; bundled colorschemes (gruvbox/nord/onedark) are all already used
; elsewhere in this rice's set, so this port uses a fresh graphite-blue
; palette instead. The source's own background is semi-transparent - but
; this rice's own Marisol theme already went fully transparent once and
; had to be walked back after real feedback found it illegible against
; an actual wallpaper, so hidrot ships at a safer ~90% opacity from the
; start instead of repeating that mistake. Workspace state icons and the
; system tray both get real attention up front for the same reason:
; explicit padding and a comfortably large font on the workspace glyphs
; (this rice's own Jan/Karla/Varinka all needed that fixed in after the
; fact), and a dedicated dark, opaque tray backdrop independent of the
; rest of the palette (Aline/Brenda both needed that fixed in after the
; fact too, since most tray icons are drawn expecting a dark bar).
[colors]
base   = #E61B1E24
mantle = #E61B1E24
surface0 = #262B33
surface1 = #262B33
text   = #D6DCE5
subtext = #6E7684
green0 = #7CB88F
purple0 = #B08FD1
blue0  = #6E93C7
red0   = #D9707A
blue1  = #5E8FCC
aqua1  = #4FB0A6
green1 = #7BBF7E
purple1 = #B08FD1
yellow1 = #D9B25C
red1   = #D9707A
tray-bg = #14161A

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = bi i3 bd

[bar/top-primary]
inherit = bar/base
modules-center = bi date-icon date bd
modules-right = bi backlight pulseaudio media bd sep bi network-wired network-wireless bluetooth caffeine dnd battery memory cpu bd sep tray

[bar/top-secondary]
inherit = bar/base
modules-center = bi date-icon date bd
modules-right = bi backlight pulseaudio media bd sep bi network-wired network-wireless memory cpu bd

[module/bi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}

[module/bd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
format-background = ${colors.surface0}
index-sort = true
wrapping-scroll = false
label-focused = "󰄰"
label-focused-foreground = ${colors.green0}
label-focused-font = 2
label-focused-padding = 2
label-unfocused = "󰄰"
label-unfocused-foreground = ${colors.blue0}
label-unfocused-font = 2
label-unfocused-padding = 2
label-urgent = "󰄰"
label-urgent-foreground = ${colors.red0}
label-urgent-font = 2
label-urgent-padding = 2

[module/date-icon]
type = custom/text
format = <label>
format-background = ${colors.surface0}
label = "󱑎"
label-foreground = ${colors.green1}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:gnome-calendar &:} %date%  %time% %{A}"

[module/backlight]
type = internal/backlight
card = intel_backlight
enable-scroll = true
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰖨 "
format-prefix-background = ${colors.blue1}
format-prefix-foreground = ${colors.base}
label = " %percentage%% "

[module/pulseaudio]
type = internal/pulseaudio
format-volume-background = ${colors.surface0}
format-volume-prefix = "󰕾 "
format-volume-prefix-background = ${colors.yellow1}
format-volume-prefix-foreground = ${colors.base}
format-muted-background = ${colors.surface0}
format-muted-prefix = "󰖁 "
format-muted-prefix-background = ${colors.red1}
format-muted-prefix-foreground = ${colors.base}
label-volume = " %percentage%% "
label-muted = " muted "

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.yellow1}
format-background = ${colors.surface0}
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = "󰒍 "
format-connected-prefix-background = ${colors.green1}
format-connected-prefix-foreground = ${colors.base}
label-connected = "%{A1:nm-connection-editor &:} %ifname% %{A}"
format-disconnected-background = ${colors.surface0}
format-disconnected-prefix = "󰒎 "
format-disconnected-prefix-background = ${colors.red1}
format-disconnected-prefix-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3
format-connected-background = ${colors.surface0}
format-connected-prefix = "󰖩 "
format-connected-prefix-background = ${colors.green1}
format-connected-prefix-foreground = ${colors.base}
label-connected = "%{A1:nm-connection-editor &:}%{A3:nmcli radio wifi toggle &:} %essid% %{A}%{A}"
format-disconnected =

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
format-background = ${colors.surface0}

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.green0}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.red0}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-background = ${colors.surface0}
format-charging-prefix = "󰠠 "
format-charging-prefix-background = ${colors.aqua1}
format-charging-prefix-foreground = ${colors.base}
format-discharging-background = ${colors.surface0}
format-discharging-prefix = "󰠠 "
format-discharging-prefix-background = ${colors.blue1}
format-discharging-prefix-foreground = ${colors.base}
format-full-background = ${colors.surface0}
format-full-prefix = "󰠠 "
format-full-prefix-background = ${colors.green1}
format-full-prefix-foreground = ${colors.base}
label-charging = " %percentage%% "
label-discharging = " %percentage%% "
label-full = " Full "

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.surface0}
format-prefix = "󰘚 "
format-prefix-background = ${colors.green1}
format-prefix-foreground = ${colors.base}
label = " %percentage_used%% "

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.surface0}
format-prefix = "󰍛 "
format-prefix-background = ${colors.purple1}
format-prefix-foreground = ${colors.base}
label = " %percentage%% "

; Explicit dark, opaque tray backdrop - most tray icons (Discord,
; 1Password, etc.) are drawn in white/light colors expecting a dark bar,
; and this theme's own bar background is only ~90% opaque, not a fully
; reliable backdrop by itself.
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.tray-bg}
format-background = ${colors.tray-bg}

[settings]
screenchange-reload = true
EOF

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

printf '%%{A1:playerctl previous:}%%{A}  %%{A1:playerctl play-pause:}%s%%{A}  %%{A1:playerctl next:}%%{A}' "$icon"
EOF
chmod +x "$BIN/polybar-media.sh"

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
@theme "current"
EOF

mkdir -p "$CONF/rofi/themes"

cat > "$CONF/rofi/themes/aline-powermenu.rasi" <<'EOF'
* {
    base:     #FAF4EDff;
    mantle:   #FAF4EDff;
    text:     #575279ff;
    subtext:  #9893A5ff;
    mauve:    #2E5D66ff;
    surface0: #F2E9E1ff;

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

cat > "$CONF/rofi/themes/aline.rasi" <<'EOF'
* {
    base:     #FAF4EDff;
    mantle:   #FAF4EDff;
    text:     #575279ff;
    subtext:  #9893A5ff;
    mauve:    #2E5D66ff;
    surface0: #F2E9E1ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/archcraft-powermenu.rasi" <<'EOF'
* {
    base:     #1E222Aff;
    mantle:   #1E222Aff;
    text:     #C8CCD4ff;
    subtext:  #727C91ff;
    mauve:    #C678DDff;
    surface0: #292E39ff;

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

cat > "$CONF/rofi/themes/archcraft.rasi" <<'EOF'
* {
    base:     #1E222Aff;
    mantle:   #1E222Aff;
    text:     #C8CCD4ff;
    subtext:  #727C91ff;
    mauve:    #C678DDff;
    surface0: #292E39ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/brenda-powermenu.rasi" <<'EOF'
* {
    base:     #2D353Bff;
    mantle:   #2D353Bff;
    text:     #D3C6AAff;
    subtext:  #859289ff;
    mauve:    #E69875ff;
    surface0: #3D454Bff;

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

cat > "$CONF/rofi/themes/brenda.rasi" <<'EOF'
* {
    base:     #2D353Bff;
    mantle:   #2D353Bff;
    text:     #D3C6AAff;
    subtext:  #859289ff;
    mauve:    #E69875ff;
    surface0: #3D454Bff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/catppuccin-mocha-powermenu.rasi" <<'EOF'
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

cat > "$CONF/rofi/themes/catppuccin-mocha.rasi" <<'EOF'
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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/cristina-powermenu.rasi" <<'EOF'
* {
    base:     #232136ff;
    mantle:   #232136ff;
    text:     #E0DEF4ff;
    subtext:  #908CAAff;
    mauve:    #8EC07Cff;
    surface0: #39374Aff;

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

cat > "$CONF/rofi/themes/cristina.rasi" <<'EOF'
* {
    base:     #232136ff;
    mantle:   #232136ff;
    text:     #E0DEF4ff;
    subtext:  #908CAAff;
    mauve:    #8EC07Cff;
    surface0: #39374Aff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/cynthia-powermenu.rasi" <<'EOF'
* {
    base:     #181616ff;
    mantle:   #181616ff;
    text:     #C5C9C5ff;
    subtext:  #708491ff;
    mauve:    #7FB4CAff;
    surface0: #242121ff;

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

cat > "$CONF/rofi/themes/cynthia.rasi" <<'EOF'
* {
    base:     #181616ff;
    mantle:   #181616ff;
    text:     #C5C9C5ff;
    subtext:  #708491ff;
    mauve:    #7FB4CAff;
    surface0: #242121ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/daniela-powermenu.rasi" <<'EOF'
* {
    base:     #1A1B26ff;
    mantle:   #1A1B26ff;
    text:     #C0CAF5ff;
    subtext:  #565F89ff;
    mauve:    #7AA2F7ff;
    surface0: #31323Cff;

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

cat > "$CONF/rofi/themes/daniela.rasi" <<'EOF'
* {
    base:     #1A1B26ff;
    mantle:   #1A1B26ff;
    text:     #C0CAF5ff;
    subtext:  #565F89ff;
    mauve:    #7AA2F7ff;
    surface0: #31323Cff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/dracula-powermenu.rasi" <<'EOF'
* {
    base:     #282A36ff;
    mantle:   #282A36ff;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    mauve:    #BD93F9ff;
    surface0: #44475Aff;

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

cat > "$CONF/rofi/themes/dracula.rasi" <<'EOF'
* {
    base:     #282A36ff;
    mantle:   #282A36ff;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    mauve:    #BD93F9ff;
    surface0: #44475Aff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/emilia-powermenu.rasi" <<'EOF'
* {
    base:     #1E1A17ff;
    mantle:   #1E1A17ff;
    text:     #E8DCC8ff;
    subtext:  #9C8F7Dff;
    mauve:    #E0A458ff;
    surface0: #2B241Fff;

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

cat > "$CONF/rofi/themes/emilia.rasi" <<'EOF'
* {
    base:     #1E1A17ff;
    mantle:   #1E1A17ff;
    text:     #E8DCC8ff;
    subtext:  #9C8F7Dff;
    mauve:    #E0A458ff;
    surface0: #2B241Fff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/h4ck3r-powermenu.rasi" <<'EOF'
* {
    base:     #0C1018ff;
    mantle:   #0C1018ff;
    text:     #00FA5Cff;
    subtext:  #578A29ff;
    mauve:    #76EA00ff;
    surface0: #1B2333ff;

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

cat > "$CONF/rofi/themes/h4ck3r.rasi" <<'EOF'
* {
    base:     #0C1018ff;
    mantle:   #0C1018ff;
    text:     #00FA5Cff;
    subtext:  #578A29ff;
    mauve:    #76EA00ff;
    surface0: #1B2333ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/hidrot-powermenu.rasi" <<'EOF'
* {
    base:     #1B1E24ff;
    mantle:   #1B1E24ff;
    text:     #D6DCE5ff;
    subtext:  #6E7684ff;
    mauve:    #7CB88Fff;
    surface0: #262B33ff;

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

cat > "$CONF/rofi/themes/hidrot.rasi" <<'EOF'
* {
    base:     #1B1E24ff;
    mantle:   #1B1E24ff;
    text:     #D6DCE5ff;
    subtext:  #6E7684ff;
    mauve:    #7CB88Fff;
    surface0: #262B33ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/isabel-powermenu.rasi" <<'EOF'
* {
    base:     #10181Aff;
    mantle:   #10181Aff;
    text:     #A8C5C0ff;
    subtext:  #5C7B76ff;
    mauve:    #4FD6BEff;
    surface0: #282F31ff;

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

cat > "$CONF/rofi/themes/isabel.rasi" <<'EOF'
* {
    base:     #10181Aff;
    mantle:   #10181Aff;
    text:     #A8C5C0ff;
    subtext:  #5C7B76ff;
    mauve:    #4FD6BEff;
    surface0: #282F31ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/jan-powermenu.rasi" <<'EOF'
* {
    base:     #212A4Cff;
    mantle:   #212A4Cff;
    text:     #27FBFEff;
    subtext:  #6B7BB0ff;
    mauve:    #FB007Aff;
    surface0: #14192Eff;

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

cat > "$CONF/rofi/themes/jan.rasi" <<'EOF'
* {
    base:     #212A4Cff;
    mantle:   #212A4Cff;
    text:     #27FBFEff;
    subtext:  #6B7BB0ff;
    mauve:    #FB007Aff;
    surface0: #14192Eff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/karla-powermenu.rasi" <<'EOF'
* {
    base:     #0E1113ff;
    mantle:   #0E1113ff;
    text:     #AFB1DBff;
    subtext:  #6272A4ff;
    mauve:    #F05393ff;
    surface0: #26292Bff;

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

cat > "$CONF/rofi/themes/karla.rasi" <<'EOF'
* {
    base:     #0E1113ff;
    mantle:   #0E1113ff;
    text:     #AFB1DBff;
    subtext:  #6272A4ff;
    mauve:    #F05393ff;
    surface0: #26292Bff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/marisol-powermenu.rasi" <<'EOF'
* {
    base:     #241C1Cff;
    mantle:   #241C1Cff;
    text:     #F5E6E0ff;
    subtext:  #A8827Cff;
    mauve:    #E8B84Cff;
    surface0: #332727ff;

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

cat > "$CONF/rofi/themes/marisol.rasi" <<'EOF'
* {
    base:     #241C1Cff;
    mantle:   #241C1Cff;
    text:     #F5E6E0ff;
    subtext:  #A8827Cff;
    mauve:    #E8B84Cff;
    surface0: #332727ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/nord-powermenu.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #ECEFF4ff;
    subtext:  #D8DEE9ff;
    mauve:    #B48EADff;
    surface0: #3B4252ff;

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

cat > "$CONF/rofi/themes/nord.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #ECEFF4ff;
    subtext:  #D8DEE9ff;
    mauve:    #B48EADff;
    surface0: #3B4252ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/pamela-powermenu.rasi" <<'EOF'
* {
    base:     #1D1F28ff;
    mantle:   #1D1F28ff;
    text:     #FDFDFDff;
    subtext:  #8C8C8Cff;
    mauve:    #F2A272ff;
    surface0: #3D435Cff;

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

cat > "$CONF/rofi/themes/pamela.rasi" <<'EOF'
* {
    base:     #1D1F28ff;
    mantle:   #1D1F28ff;
    text:     #FDFDFDff;
    subtext:  #8C8C8Cff;
    mauve:    #F2A272ff;
    surface0: #3D435Cff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/silvia-powermenu.rasi" <<'EOF'
* {
    base:     #3C3836ff;
    mantle:   #3C3836ff;
    text:     #EBDBB2ff;
    subtext:  #928374ff;
    mauve:    #8EC07Cff;
    surface0: #504945ff;

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

cat > "$CONF/rofi/themes/silvia.rasi" <<'EOF'
* {
    base:     #3C3836ff;
    mantle:   #3C3836ff;
    text:     #EBDBB2ff;
    subtext:  #928374ff;
    mauve:    #8EC07Cff;
    surface0: #504945ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/varinka-powermenu.rasi" <<'EOF'
* {
    base:     #212529ff;
    mantle:   #212529ff;
    text:     #F8F9FAff;
    subtext:  #6C757Dff;
    mauve:    #DC5BBCff;
    surface0: #343A40ff;

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

cat > "$CONF/rofi/themes/varinka.rasi" <<'EOF'
* {
    base:     #212529ff;
    mantle:   #212529ff;
    text:     #F8F9FAff;
    subtext:  #6C757Dff;
    mauve:    #DC5BBCff;
    surface0: #343A40ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/yael-powermenu.rasi" <<'EOF'
* {
    base:     #161616ff;
    mantle:   #161616ff;
    text:     #FFFFFFff;
    subtext:  #8C8C8Cff;
    mauve:    #33B1FFff;
    surface0: #262626ff;

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

cat > "$CONF/rofi/themes/yael.rasi" <<'EOF'
* {
    base:     #161616ff;
    mantle:   #161616ff;
    text:     #FFFFFFff;
    subtext:  #8C8C8Cff;
    mauve:    #33B1FFff;
    surface0: #262626ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/z0mbi3-powermenu.rasi" <<'EOF'
* {
    base:     #0D0F18ff;
    mantle:   #0D0F18ff;
    text:     #A5B6CFff;
    subtext:  #6E8DB4ff;
    mauve:    #86AAECff;
    surface0: #1C1E27ff;

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

cat > "$CONF/rofi/themes/z0mbi3.rasi" <<'EOF'
* {
    base:     #0D0F18ff;
    mantle:   #0D0F18ff;
    text:     #A5B6CFff;
    subtext:  #6E8DB4ff;
    mauve:    #86AAECff;
    surface0: #1C1E27ff;

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
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 6px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/aline-square.rasi" <<'EOF'
* {
    base:     #FAF4EDff;
    mantle:   #FAF4EDff;
    text:     #575279ff;
    subtext:  #9893A5ff;
    mauve:    #2E5D66ff;
    surface0: #F2E9E1ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/aline-square-powermenu.rasi" <<'EOF'
* {
    base:     #FAF4EDff;
    mantle:   #FAF4EDff;
    text:     #575279ff;
    subtext:  #9893A5ff;
    mauve:    #2E5D66ff;
    surface0: #F2E9E1ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/archcraft-square.rasi" <<'EOF'
* {
    base:     #1E222Aff;
    mantle:   #1E222Aff;
    text:     #C8CCD4ff;
    subtext:  #727C91ff;
    mauve:    #C678DDff;
    surface0: #292E39ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/archcraft-square-powermenu.rasi" <<'EOF'
* {
    base:     #1E222Aff;
    mantle:   #1E222Aff;
    text:     #C8CCD4ff;
    subtext:  #727C91ff;
    mauve:    #C678DDff;
    surface0: #292E39ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/brenda-square.rasi" <<'EOF'
* {
    base:     #2D353Bff;
    mantle:   #2D353Bff;
    text:     #D3C6AAff;
    subtext:  #859289ff;
    mauve:    #E69875ff;
    surface0: #3D454Bff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/brenda-square-powermenu.rasi" <<'EOF'
* {
    base:     #2D353Bff;
    mantle:   #2D353Bff;
    text:     #D3C6AAff;
    subtext:  #859289ff;
    mauve:    #E69875ff;
    surface0: #3D454Bff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/catppuccin-mocha-square.rasi" <<'EOF'
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
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/catppuccin-mocha-square-powermenu.rasi" <<'EOF'
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
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/cristina-square.rasi" <<'EOF'
* {
    base:     #232136ff;
    mantle:   #232136ff;
    text:     #E0DEF4ff;
    subtext:  #908CAAff;
    mauve:    #8EC07Cff;
    surface0: #39374Aff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/cristina-square-powermenu.rasi" <<'EOF'
* {
    base:     #232136ff;
    mantle:   #232136ff;
    text:     #E0DEF4ff;
    subtext:  #908CAAff;
    mauve:    #8EC07Cff;
    surface0: #39374Aff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/cynthia-square.rasi" <<'EOF'
* {
    base:     #181616ff;
    mantle:   #181616ff;
    text:     #C5C9C5ff;
    subtext:  #708491ff;
    mauve:    #7FB4CAff;
    surface0: #242121ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/cynthia-square-powermenu.rasi" <<'EOF'
* {
    base:     #181616ff;
    mantle:   #181616ff;
    text:     #C5C9C5ff;
    subtext:  #708491ff;
    mauve:    #7FB4CAff;
    surface0: #242121ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/daniela-square.rasi" <<'EOF'
* {
    base:     #1A1B26ff;
    mantle:   #1A1B26ff;
    text:     #C0CAF5ff;
    subtext:  #565F89ff;
    mauve:    #7AA2F7ff;
    surface0: #31323Cff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/daniela-square-powermenu.rasi" <<'EOF'
* {
    base:     #1A1B26ff;
    mantle:   #1A1B26ff;
    text:     #C0CAF5ff;
    subtext:  #565F89ff;
    mauve:    #7AA2F7ff;
    surface0: #31323Cff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/dracula-square.rasi" <<'EOF'
* {
    base:     #282A36ff;
    mantle:   #282A36ff;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    mauve:    #BD93F9ff;
    surface0: #44475Aff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/dracula-square-powermenu.rasi" <<'EOF'
* {
    base:     #282A36ff;
    mantle:   #282A36ff;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    mauve:    #BD93F9ff;
    surface0: #44475Aff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/emilia-square.rasi" <<'EOF'
* {
    base:     #1E1A17ff;
    mantle:   #1E1A17ff;
    text:     #E8DCC8ff;
    subtext:  #9C8F7Dff;
    mauve:    #E0A458ff;
    surface0: #2B241Fff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/emilia-square-powermenu.rasi" <<'EOF'
* {
    base:     #1E1A17ff;
    mantle:   #1E1A17ff;
    text:     #E8DCC8ff;
    subtext:  #9C8F7Dff;
    mauve:    #E0A458ff;
    surface0: #2B241Fff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/h4ck3r-square.rasi" <<'EOF'
* {
    base:     #0C1018ff;
    mantle:   #0C1018ff;
    text:     #00FA5Cff;
    subtext:  #578A29ff;
    mauve:    #76EA00ff;
    surface0: #1B2333ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/h4ck3r-square-powermenu.rasi" <<'EOF'
* {
    base:     #0C1018ff;
    mantle:   #0C1018ff;
    text:     #00FA5Cff;
    subtext:  #578A29ff;
    mauve:    #76EA00ff;
    surface0: #1B2333ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/hidrot-square.rasi" <<'EOF'
* {
    base:     #1B1E24ff;
    mantle:   #1B1E24ff;
    text:     #D6DCE5ff;
    subtext:  #6E7684ff;
    mauve:    #7CB88Fff;
    surface0: #262B33ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/hidrot-square-powermenu.rasi" <<'EOF'
* {
    base:     #1B1E24ff;
    mantle:   #1B1E24ff;
    text:     #D6DCE5ff;
    subtext:  #6E7684ff;
    mauve:    #7CB88Fff;
    surface0: #262B33ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/isabel-square.rasi" <<'EOF'
* {
    base:     #10181Aff;
    mantle:   #10181Aff;
    text:     #A8C5C0ff;
    subtext:  #5C7B76ff;
    mauve:    #4FD6BEff;
    surface0: #282F31ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/isabel-square-powermenu.rasi" <<'EOF'
* {
    base:     #10181Aff;
    mantle:   #10181Aff;
    text:     #A8C5C0ff;
    subtext:  #5C7B76ff;
    mauve:    #4FD6BEff;
    surface0: #282F31ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/jan-square.rasi" <<'EOF'
* {
    base:     #212A4Cff;
    mantle:   #212A4Cff;
    text:     #27FBFEff;
    subtext:  #6B7BB0ff;
    mauve:    #FB007Aff;
    surface0: #14192Eff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/jan-square-powermenu.rasi" <<'EOF'
* {
    base:     #212A4Cff;
    mantle:   #212A4Cff;
    text:     #27FBFEff;
    subtext:  #6B7BB0ff;
    mauve:    #FB007Aff;
    surface0: #14192Eff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/karla-square.rasi" <<'EOF'
* {
    base:     #0E1113ff;
    mantle:   #0E1113ff;
    text:     #AFB1DBff;
    subtext:  #6272A4ff;
    mauve:    #F05393ff;
    surface0: #26292Bff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/karla-square-powermenu.rasi" <<'EOF'
* {
    base:     #0E1113ff;
    mantle:   #0E1113ff;
    text:     #AFB1DBff;
    subtext:  #6272A4ff;
    mauve:    #F05393ff;
    surface0: #26292Bff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/marisol-square.rasi" <<'EOF'
* {
    base:     #241C1Cff;
    mantle:   #241C1Cff;
    text:     #F5E6E0ff;
    subtext:  #A8827Cff;
    mauve:    #E8B84Cff;
    surface0: #332727ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/marisol-square-powermenu.rasi" <<'EOF'
* {
    base:     #241C1Cff;
    mantle:   #241C1Cff;
    text:     #F5E6E0ff;
    subtext:  #A8827Cff;
    mauve:    #E8B84Cff;
    surface0: #332727ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/nord-square.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #ECEFF4ff;
    subtext:  #D8DEE9ff;
    mauve:    #B48EADff;
    surface0: #3B4252ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/nord-square-powermenu.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #ECEFF4ff;
    subtext:  #D8DEE9ff;
    mauve:    #B48EADff;
    surface0: #3B4252ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/pamela-square.rasi" <<'EOF'
* {
    base:     #1D1F28ff;
    mantle:   #1D1F28ff;
    text:     #FDFDFDff;
    subtext:  #8C8C8Cff;
    mauve:    #F2A272ff;
    surface0: #3D435Cff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/pamela-square-powermenu.rasi" <<'EOF'
* {
    base:     #1D1F28ff;
    mantle:   #1D1F28ff;
    text:     #FDFDFDff;
    subtext:  #8C8C8Cff;
    mauve:    #F2A272ff;
    surface0: #3D435Cff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/silvia-square.rasi" <<'EOF'
* {
    base:     #3C3836ff;
    mantle:   #3C3836ff;
    text:     #EBDBB2ff;
    subtext:  #928374ff;
    mauve:    #8EC07Cff;
    surface0: #504945ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/silvia-square-powermenu.rasi" <<'EOF'
* {
    base:     #3C3836ff;
    mantle:   #3C3836ff;
    text:     #EBDBB2ff;
    subtext:  #928374ff;
    mauve:    #8EC07Cff;
    surface0: #504945ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/varinka-square.rasi" <<'EOF'
* {
    base:     #212529ff;
    mantle:   #212529ff;
    text:     #F8F9FAff;
    subtext:  #6C757Dff;
    mauve:    #DC5BBCff;
    surface0: #343A40ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/varinka-square-powermenu.rasi" <<'EOF'
* {
    base:     #212529ff;
    mantle:   #212529ff;
    text:     #F8F9FAff;
    subtext:  #6C757Dff;
    mauve:    #DC5BBCff;
    surface0: #343A40ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/yael-square.rasi" <<'EOF'
* {
    base:     #161616ff;
    mantle:   #161616ff;
    text:     #FFFFFFff;
    subtext:  #8C8C8Cff;
    mauve:    #33B1FFff;
    surface0: #262626ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/yael-square-powermenu.rasi" <<'EOF'
* {
    base:     #161616ff;
    mantle:   #161616ff;
    text:     #FFFFFFff;
    subtext:  #8C8C8Cff;
    mauve:    #33B1FFff;
    surface0: #262626ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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

cat > "$CONF/rofi/themes/z0mbi3-square.rasi" <<'EOF'
* {
    base:     #0D0F18ff;
    mantle:   #0D0F18ff;
    text:     #A5B6CFff;
    subtext:  #6E8DB4ff;
    mauve:    #86AAECff;
    surface0: #1C1E27ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 30%;
    border-radius: 0px;
    background-color: @base;
}

inputbar {
    padding: 10px;
    background-color: @mantle;
    border-radius: 0px;
    children: [prompt, entry];
}

prompt { text-color: @mauve; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 12;
    padding: 8px 0;
}

element {
    padding: 6px 10px;
    border-radius: 0px;
}
element-text, element-icon {
    background-color: inherit;
    text-color: inherit;
}

element selected {
    background-color: @surface0;
    text-color: @mauve;
}
EOF

cat > "$CONF/rofi/themes/z0mbi3-square-powermenu.rasi" <<'EOF'
* {
    base:     #0D0F18ff;
    mantle:   #0D0F18ff;
    text:     #A5B6CFff;
    subtext:  #6E8DB4ff;
    mauve:    #86AAECff;
    surface0: #1C1E27ff;

    background-color: @base;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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
    border-radius: 0px;
    background-color: @mantle;
}
element normal.normal {
    text-color: @text;
}
element selected {
    background-color: @surface0;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
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


cp "$CONF/rofi/themes/catppuccin-mocha.rasi" "$CONF/rofi/current.rasi"
cp "$CONF/rofi/themes/catppuccin-mocha-powermenu.rasi" "$CONF/rofi/current-powermenu.rasi"


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

# Colors come from current.conf (a copy of one of themes/*.conf, chosen via
# ~/.local/bin/polybar-theme.sh) rather than being set directly here, so a
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

mkdir -p "$CONF/kitty/themes"

cat > "$CONF/kitty/themes/aline.conf" <<'EOF'
foreground              #575279
background              #FAF4ED
selection_foreground    #FAF4ED
selection_background    #575279
cursor                  #2E5D66
cursor_text_color       #FAF4ED

color0  #F2E9E1
color8  #9893A5
color1  #B4637A
color9  #B4637A
color2  #286983
color10 #286983
color3  #A15E15
color11 #A15E15
color4  #2E5D66
color12 #2E5D66
color5  #2E5D66
color13 #2E5D66
color6  #2E7480
color14 #2E7480
color7  #9893A5
color15 #575279
EOF

cat > "$CONF/kitty/themes/archcraft.conf" <<'EOF'
foreground              #C8CCD4
background              #1E222A
selection_foreground    #1E222A
selection_background    #C8CCD4
cursor                  #C678DD
cursor_text_color       #1E222A

color0  #292E39
color8  #727C91
color1  #E06C75
color9  #E06C75
color2  #98C379
color10 #98C379
color3  #E5C07B
color11 #E5C07B
color4  #61AFEF
color12 #61AFEF
color5  #C678DD
color13 #C678DD
color6  #56B6C2
color14 #56B6C2
color7  #727C91
color15 #C8CCD4
EOF

cat > "$CONF/kitty/themes/brenda.conf" <<'EOF'
foreground              #D3C6AA
background              #2D353B
selection_foreground    #2D353B
selection_background    #D3C6AA
cursor                  #E69875
cursor_text_color       #2D353B

color0  #3D454B
color8  #859289
color1  #E67E80
color9  #E67E80
color2  #A7C080
color10 #A7C080
color3  #DBBC7F
color11 #DBBC7F
color4  #7FBBB3
color12 #7FBBB3
color5  #D699B6
color13 #D699B6
color6  #B9C244
color14 #B9C244
color7  #859289
color15 #D3C6AA
EOF

cat > "$CONF/kitty/themes/catppuccin-mocha.conf" <<'EOF'
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

cat > "$CONF/kitty/themes/cristina.conf" <<'EOF'
foreground              #E0DEF4
background              #232136
selection_foreground    #232136
selection_background    #E0DEF4
cursor                  #8EC07C
cursor_text_color       #232136

color0  #232136
color8  #908CAA
color1  #EA6F91
color9  #EA6F91
color2  #9BCED7
color10 #9BCED7
color3  #F1CA93
color11 #F1CA93
color4  #34738E
color12 #34738E
color5  #C3A5E6
color13 #C3A5E6
color6  #8EC07C
color14 #8EC07C
color7  #908CAA
color15 #E0DEF4
EOF

cat > "$CONF/kitty/themes/cynthia.conf" <<'EOF'
foreground              #C5C9C5
background              #181616
selection_foreground    #181616
selection_background    #C5C9C5
cursor                  #7FB4CA
cursor_text_color       #181616

color0  #242121
color8  #708491
color1  #E46876
color9  #E46876
color2  #87A987
color10 #87A987
color3  #E6C384
color11 #E6C384
color4  #7FB4CA
color12 #7FB4CA
color5  #938AA9
color13 #938AA9
color6  #7FB4CA
color14 #7FB4CA
color7  #708491
color15 #C5C9C5
EOF

cat > "$CONF/kitty/themes/daniela.conf" <<'EOF'
foreground              #C0CAF5
background              #1A1B26
selection_foreground    #1A1B26
selection_background    #C0CAF5
cursor                  #7AA2F7
cursor_text_color       #1A1B26

color0  #1A1B26
color8  #565F89
color1  #F7768E
color9  #F7768E
color2  #9ECE6A
color10 #9ECE6A
color3  #E0AF68
color11 #E0AF68
color4  #7AA2F7
color12 #7AA2F7
color5  #BB9AF7
color13 #BB9AF7
color6  #7DCFFF
color14 #7DCFFF
color7  #565F89
color15 #C0CAF5
EOF

cat > "$CONF/kitty/themes/dracula.conf" <<'EOF'
foreground              #F8F8F2
background              #282A36
selection_foreground    #282A36
selection_background    #F8F8F2
cursor                  #BD93F9
cursor_text_color       #282A36

color0  #44475A
color8  #6272A4
color1  #FF5555
color9  #FF5555
color2  #50FA7B
color10 #50FA7B
color3  #F1FA8C
color11 #F1FA8C
color4  #6272A4
color12 #6272A4
color5  #BD93F9
color13 #BD93F9
color6  #8BE9FD
color14 #8BE9FD
color7  #6272A4
color15 #F8F8F2
EOF

cat > "$CONF/kitty/themes/emilia.conf" <<'EOF'
foreground              #E8DCC8
background              #1E1A17
selection_foreground    #1E1A17
selection_background    #E8DCC8
cursor                  #E0A458
cursor_text_color       #1E1A17

color0  #2B241F
color8  #9C8F7D
color1  #D9736A
color9  #D9736A
color2  #A8B562
color10 #A8B562
color3  #E0A458
color11 #E0A458
color4  #7FA5B5
color12 #7FA5B5
color5  #B08BBB
color13 #B08BBB
color6  #7FA5B5
color14 #7FA5B5
color7  #9C8F7D
color15 #E8DCC8
EOF

cat > "$CONF/kitty/themes/h4ck3r.conf" <<'EOF'
foreground              #00FA5C
background              #0C1018
selection_foreground    #0C1018
selection_background    #00FA5C
cursor                  #76EA00
cursor_text_color       #0C1018

color0  #1B2333
color8  #578A29
color1  #6DDE00
color9  #6DDE00
color2  #00FA5C
color10 #00FA5C
color3  #76EA00
color11 #76EA00
color4  #9CF542
color12 #9CF542
color5  #00FA5C
color13 #00FA5C
color6  #9CF542
color14 #9CF542
color7  #578A29
color15 #00FA5C
EOF

cat > "$CONF/kitty/themes/hidrot.conf" <<'EOF'
foreground              #D6DCE5
background              #1B1E24
selection_foreground    #1B1E24
selection_background    #D6DCE5
cursor                  #7CB88F
cursor_text_color       #1B1E24

color0  #262B33
color8  #6E7684
color1  #D9707A
color9  #D9707A
color2  #7BBF7E
color10 #7BBF7E
color3  #D9B25C
color11 #D9B25C
color4  #5E8FCC
color12 #5E8FCC
color5  #B08FD1
color13 #B08FD1
color6  #4FB0A6
color14 #4FB0A6
color7  #6E7684
color15 #D6DCE5
EOF

cat > "$CONF/kitty/themes/isabel.conf" <<'EOF'
foreground              #A8C5C0
background              #10181A
selection_foreground    #10181A
selection_background    #A8C5C0
cursor                  #4FD6BE
cursor_text_color       #10181A

color0  #10181A
color8  #5C7B76
color1  #D67F7F
color9  #D67F7F
color2  #7FBF8F
color10 #7FBF8F
color3  #D6B35C
color11 #D6B35C
color4  #5FA8C7
color12 #5FA8C7
color5  #5FA8C7
color13 #5FA8C7
color6  #4FD6BE
color14 #4FD6BE
color7  #5C7B76
color15 #A8C5C0
EOF

cat > "$CONF/kitty/themes/jan.conf" <<'EOF'
foreground              #27FBFE
background              #212A4C
selection_foreground    #212A4C
selection_background    #27FBFE
cursor                  #FB007A
cursor_text_color       #212A4C

color0  #212A4C
color8  #6B7BB0
color1  #FB007A
color9  #FB007A
color2  #00FF00
color10 #00FF00
color3  #F2ED00
color11 #F2ED00
color4  #19BFFE
color12 #19BFFE
color5  #6800D2
color13 #6800D2
color6  #8DF202
color14 #8DF202
color7  #6B7BB0
color15 #27FBFE
EOF

cat > "$CONF/kitty/themes/karla.conf" <<'EOF'
foreground              #AFB1DB
background              #0E1113
selection_foreground    #0E1113
selection_background    #AFB1DB
cursor                  #F05393
cursor_text_color       #0E1113

color0  #0E1113
color8  #6272A4
color1  #E7034A
color9  #E7034A
color2  #0FD94F
color10 #0FD94F
color3  #F7F23F
color11 #F7F23F
color4  #4856D4
color12 #4856D4
color5  #7A44E3
color13 #7A44E3
color6  #7DF0F0
color14 #7DF0F0
color7  #6272A4
color15 #AFB1DB
EOF

cat > "$CONF/kitty/themes/marisol.conf" <<'EOF'
foreground              #F5E6E0
background              #241C1C
selection_foreground    #241C1C
selection_background    #F5E6E0
cursor                  #E8B84C
cursor_text_color       #241C1C

color0  #332727
color8  #A8827C
color1  #E8604C
color9  #E8604C
color2  #7FBF8F
color10 #7FBF8F
color3  #E8B84C
color11 #E8B84C
color4  #6FA8C7
color12 #6FA8C7
color5  #B98FC7
color13 #B98FC7
color6  #6FA8C7
color14 #6FA8C7
color7  #A8827C
color15 #F5E6E0
EOF

cat > "$CONF/kitty/themes/nord.conf" <<'EOF'
foreground              #ECEFF4
background              #2E3440
selection_foreground    #2E3440
selection_background    #ECEFF4
cursor                  #B48EAD
cursor_text_color       #2E3440

color0  #3B4252
color8  #D8DEE9
color1  #BF616A
color9  #E098A0
color2  #A3BE8C
color10 #A3BE8C
color3  #EBCB8B
color11 #EBCB8B
color4  #5E81AC
color12 #5E81AC
color5  #B48EAD
color13 #B48EAD
color6  #8FBCBB
color14 #8FBCBB
color7  #D8DEE9
color15 #ECEFF4
EOF

cat > "$CONF/kitty/themes/pamela.conf" <<'EOF'
foreground              #FDFDFD
background              #1D1F28
selection_foreground    #1D1F28
selection_background    #FDFDFD
cursor                  #F2A272
cursor_text_color       #1D1F28

color0  #3D435C
color8  #8C8C8C
color1  #F37F97
color9  #F37F97
color2  #5ADECD
color10 #5ADECD
color3  #F2A272
color11 #F2A272
color4  #8897F4
color12 #8897F4
color5  #C574DD
color13 #C574DD
color6  #79E6F3
color14 #79E6F3
color7  #8C8C8C
color15 #FDFDFD
EOF

cat > "$CONF/kitty/themes/silvia.conf" <<'EOF'
foreground              #EBDBB2
background              #3C3836
selection_foreground    #3C3836
selection_background    #EBDBB2
cursor                  #8EC07C
cursor_text_color       #3C3836

color0  #504945
color8  #928374
color1  #CC241D
color9  #FB4934
color2  #98971A
color10 #98971A
color3  #D79921
color11 #D79921
color4  #458588
color12 #83A598
color5  #B16286
color13 #B16286
color6  #689D6A
color14 #689D6A
color7  #928374
color15 #EBDBB2
EOF

cat > "$CONF/kitty/themes/varinka.conf" <<'EOF'
foreground              #F8F9FA
background              #212529
selection_foreground    #212529
selection_background    #F8F9FA
cursor                  #DC5BBC
cursor_text_color       #212529

color0  #343A40
color8  #6C757D
color1  #DC5BBC
color9  #DC5BBC
color2  #ADB5BD
color10 #ADB5BD
color3  #DE8658
color11 #DE8658
color4  #495057
color12 #495057
color5  #DC5BBC
color13 #DC5BBC
color6  #495057
color14 #495057
color7  #6C757D
color15 #F8F9FA
EOF

cat > "$CONF/kitty/themes/yael.conf" <<'EOF'
foreground              #FFFFFF
background              #161616
selection_foreground    #161616
selection_background    #FFFFFF
cursor                  #33B1FF
cursor_text_color       #161616

color0  #262626
color8  #8C8C8C
color1  #EE5396
color9  #EE5396
color2  #42BE65
color10 #42BE65
color3  #FFE97B
color11 #FFE97B
color4  #33B1FF
color12 #33B1FF
color5  #FF7EB6
color13 #FF7EB6
color6  #3DDBD9
color14 #3DDBD9
color7  #8C8C8C
color15 #FFFFFF
EOF

cat > "$CONF/kitty/themes/z0mbi3.conf" <<'EOF'
foreground              #A5B6CF
background              #0D0F18
selection_foreground    #0D0F18
selection_background    #A5B6CF
cursor                  #86AAEC
cursor_text_color       #0D0F18

color0  #1C1E27
color8  #6E8DB4
color1  #DD6777
color9  #DD6777
color2  #90CEAA
color10 #90CEAA
color3  #ECD3A0
color11 #ECD3A0
color4  #86AAEC
color12 #86AAEC
color5  #C296EB
color13 #C296EB
color6  #93CEE9
color14 #93CEE9
color7  #6E8DB4
color15 #A5B6CF
EOF

cat > "$CONF/kitty/themes/aline-square.conf" <<'EOF'
foreground              #575279
background              #FAF4ED
selection_foreground    #FAF4ED
selection_background    #575279
cursor                  #2E5D66
cursor_text_color       #FAF4ED

color0  #F2E9E1
color8  #9893A5
color1  #B4637A
color9  #B4637A
color2  #286983
color10 #286983
color3  #A15E15
color11 #A15E15
color4  #2E5D66
color12 #2E5D66
color5  #2E5D66
color13 #2E5D66
color6  #2E7480
color14 #2E7480
color7  #9893A5
color15 #575279
EOF

cat > "$CONF/kitty/themes/archcraft-square.conf" <<'EOF'
foreground              #C8CCD4
background              #1E222A
selection_foreground    #1E222A
selection_background    #C8CCD4
cursor                  #C678DD
cursor_text_color       #1E222A

color0  #292E39
color8  #727C91
color1  #E06C75
color9  #E06C75
color2  #98C379
color10 #98C379
color3  #E5C07B
color11 #E5C07B
color4  #61AFEF
color12 #61AFEF
color5  #C678DD
color13 #C678DD
color6  #56B6C2
color14 #56B6C2
color7  #727C91
color15 #C8CCD4
EOF

cat > "$CONF/kitty/themes/brenda-square.conf" <<'EOF'
foreground              #D3C6AA
background              #2D353B
selection_foreground    #2D353B
selection_background    #D3C6AA
cursor                  #E69875
cursor_text_color       #2D353B

color0  #3D454B
color8  #859289
color1  #E67E80
color9  #E67E80
color2  #A7C080
color10 #A7C080
color3  #DBBC7F
color11 #DBBC7F
color4  #7FBBB3
color12 #7FBBB3
color5  #D699B6
color13 #D699B6
color6  #B9C244
color14 #B9C244
color7  #859289
color15 #D3C6AA
EOF

cat > "$CONF/kitty/themes/catppuccin-mocha-square.conf" <<'EOF'
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

cat > "$CONF/kitty/themes/cristina-square.conf" <<'EOF'
foreground              #E0DEF4
background              #232136
selection_foreground    #232136
selection_background    #E0DEF4
cursor                  #8EC07C
cursor_text_color       #232136

color0  #232136
color8  #908CAA
color1  #EA6F91
color9  #EA6F91
color2  #9BCED7
color10 #9BCED7
color3  #F1CA93
color11 #F1CA93
color4  #34738E
color12 #34738E
color5  #C3A5E6
color13 #C3A5E6
color6  #8EC07C
color14 #8EC07C
color7  #908CAA
color15 #E0DEF4
EOF

cat > "$CONF/kitty/themes/cynthia-square.conf" <<'EOF'
foreground              #C5C9C5
background              #181616
selection_foreground    #181616
selection_background    #C5C9C5
cursor                  #7FB4CA
cursor_text_color       #181616

color0  #242121
color8  #708491
color1  #E46876
color9  #E46876
color2  #87A987
color10 #87A987
color3  #E6C384
color11 #E6C384
color4  #7FB4CA
color12 #7FB4CA
color5  #938AA9
color13 #938AA9
color6  #7FB4CA
color14 #7FB4CA
color7  #708491
color15 #C5C9C5
EOF

cat > "$CONF/kitty/themes/daniela-square.conf" <<'EOF'
foreground              #C0CAF5
background              #1A1B26
selection_foreground    #1A1B26
selection_background    #C0CAF5
cursor                  #7AA2F7
cursor_text_color       #1A1B26

color0  #1A1B26
color8  #565F89
color1  #F7768E
color9  #F7768E
color2  #9ECE6A
color10 #9ECE6A
color3  #E0AF68
color11 #E0AF68
color4  #7AA2F7
color12 #7AA2F7
color5  #BB9AF7
color13 #BB9AF7
color6  #7DCFFF
color14 #7DCFFF
color7  #565F89
color15 #C0CAF5
EOF

cat > "$CONF/kitty/themes/dracula-square.conf" <<'EOF'
foreground              #F8F8F2
background              #282A36
selection_foreground    #282A36
selection_background    #F8F8F2
cursor                  #BD93F9
cursor_text_color       #282A36

color0  #44475A
color8  #6272A4
color1  #FF5555
color9  #FF5555
color2  #50FA7B
color10 #50FA7B
color3  #F1FA8C
color11 #F1FA8C
color4  #6272A4
color12 #6272A4
color5  #BD93F9
color13 #BD93F9
color6  #8BE9FD
color14 #8BE9FD
color7  #6272A4
color15 #F8F8F2
EOF

cat > "$CONF/kitty/themes/emilia-square.conf" <<'EOF'
foreground              #E8DCC8
background              #1E1A17
selection_foreground    #1E1A17
selection_background    #E8DCC8
cursor                  #E0A458
cursor_text_color       #1E1A17

color0  #2B241F
color8  #9C8F7D
color1  #D9736A
color9  #D9736A
color2  #A8B562
color10 #A8B562
color3  #E0A458
color11 #E0A458
color4  #7FA5B5
color12 #7FA5B5
color5  #B08BBB
color13 #B08BBB
color6  #7FA5B5
color14 #7FA5B5
color7  #9C8F7D
color15 #E8DCC8
EOF

cat > "$CONF/kitty/themes/h4ck3r-square.conf" <<'EOF'
foreground              #00FA5C
background              #0C1018
selection_foreground    #0C1018
selection_background    #00FA5C
cursor                  #76EA00
cursor_text_color       #0C1018

color0  #1B2333
color8  #578A29
color1  #6DDE00
color9  #6DDE00
color2  #00FA5C
color10 #00FA5C
color3  #76EA00
color11 #76EA00
color4  #9CF542
color12 #9CF542
color5  #00FA5C
color13 #00FA5C
color6  #9CF542
color14 #9CF542
color7  #578A29
color15 #00FA5C
EOF

cat > "$CONF/kitty/themes/hidrot-square.conf" <<'EOF'
foreground              #D6DCE5
background              #1B1E24
selection_foreground    #1B1E24
selection_background    #D6DCE5
cursor                  #7CB88F
cursor_text_color       #1B1E24

color0  #262B33
color8  #6E7684
color1  #D9707A
color9  #D9707A
color2  #7BBF7E
color10 #7BBF7E
color3  #D9B25C
color11 #D9B25C
color4  #5E8FCC
color12 #5E8FCC
color5  #B08FD1
color13 #B08FD1
color6  #4FB0A6
color14 #4FB0A6
color7  #6E7684
color15 #D6DCE5
EOF

cat > "$CONF/kitty/themes/isabel-square.conf" <<'EOF'
foreground              #A8C5C0
background              #10181A
selection_foreground    #10181A
selection_background    #A8C5C0
cursor                  #4FD6BE
cursor_text_color       #10181A

color0  #10181A
color8  #5C7B76
color1  #D67F7F
color9  #D67F7F
color2  #7FBF8F
color10 #7FBF8F
color3  #D6B35C
color11 #D6B35C
color4  #5FA8C7
color12 #5FA8C7
color5  #5FA8C7
color13 #5FA8C7
color6  #4FD6BE
color14 #4FD6BE
color7  #5C7B76
color15 #A8C5C0
EOF

cat > "$CONF/kitty/themes/jan-square.conf" <<'EOF'
foreground              #27FBFE
background              #212A4C
selection_foreground    #212A4C
selection_background    #27FBFE
cursor                  #FB007A
cursor_text_color       #212A4C

color0  #212A4C
color8  #6B7BB0
color1  #FB007A
color9  #FB007A
color2  #00FF00
color10 #00FF00
color3  #F2ED00
color11 #F2ED00
color4  #19BFFE
color12 #19BFFE
color5  #6800D2
color13 #6800D2
color6  #8DF202
color14 #8DF202
color7  #6B7BB0
color15 #27FBFE
EOF

cat > "$CONF/kitty/themes/karla-square.conf" <<'EOF'
foreground              #AFB1DB
background              #0E1113
selection_foreground    #0E1113
selection_background    #AFB1DB
cursor                  #F05393
cursor_text_color       #0E1113

color0  #0E1113
color8  #6272A4
color1  #E7034A
color9  #E7034A
color2  #0FD94F
color10 #0FD94F
color3  #F7F23F
color11 #F7F23F
color4  #4856D4
color12 #4856D4
color5  #7A44E3
color13 #7A44E3
color6  #7DF0F0
color14 #7DF0F0
color7  #6272A4
color15 #AFB1DB
EOF

cat > "$CONF/kitty/themes/marisol-square.conf" <<'EOF'
foreground              #F5E6E0
background              #241C1C
selection_foreground    #241C1C
selection_background    #F5E6E0
cursor                  #E8B84C
cursor_text_color       #241C1C

color0  #332727
color8  #A8827C
color1  #E8604C
color9  #E8604C
color2  #7FBF8F
color10 #7FBF8F
color3  #E8B84C
color11 #E8B84C
color4  #6FA8C7
color12 #6FA8C7
color5  #B98FC7
color13 #B98FC7
color6  #6FA8C7
color14 #6FA8C7
color7  #A8827C
color15 #F5E6E0
EOF

cat > "$CONF/kitty/themes/nord-square.conf" <<'EOF'
foreground              #ECEFF4
background              #2E3440
selection_foreground    #2E3440
selection_background    #ECEFF4
cursor                  #B48EAD
cursor_text_color       #2E3440

color0  #3B4252
color8  #D8DEE9
color1  #BF616A
color9  #E098A0
color2  #A3BE8C
color10 #A3BE8C
color3  #EBCB8B
color11 #EBCB8B
color4  #5E81AC
color12 #5E81AC
color5  #B48EAD
color13 #B48EAD
color6  #8FBCBB
color14 #8FBCBB
color7  #D8DEE9
color15 #ECEFF4
EOF

cat > "$CONF/kitty/themes/pamela-square.conf" <<'EOF'
foreground              #FDFDFD
background              #1D1F28
selection_foreground    #1D1F28
selection_background    #FDFDFD
cursor                  #F2A272
cursor_text_color       #1D1F28

color0  #3D435C
color8  #8C8C8C
color1  #F37F97
color9  #F37F97
color2  #5ADECD
color10 #5ADECD
color3  #F2A272
color11 #F2A272
color4  #8897F4
color12 #8897F4
color5  #C574DD
color13 #C574DD
color6  #79E6F3
color14 #79E6F3
color7  #8C8C8C
color15 #FDFDFD
EOF

cat > "$CONF/kitty/themes/silvia-square.conf" <<'EOF'
foreground              #EBDBB2
background              #3C3836
selection_foreground    #3C3836
selection_background    #EBDBB2
cursor                  #8EC07C
cursor_text_color       #3C3836

color0  #504945
color8  #928374
color1  #CC241D
color9  #FB4934
color2  #98971A
color10 #98971A
color3  #D79921
color11 #D79921
color4  #458588
color12 #83A598
color5  #B16286
color13 #B16286
color6  #689D6A
color14 #689D6A
color7  #928374
color15 #EBDBB2
EOF

cat > "$CONF/kitty/themes/varinka-square.conf" <<'EOF'
foreground              #F8F9FA
background              #212529
selection_foreground    #212529
selection_background    #F8F9FA
cursor                  #DC5BBC
cursor_text_color       #212529

color0  #343A40
color8  #6C757D
color1  #DC5BBC
color9  #DC5BBC
color2  #ADB5BD
color10 #ADB5BD
color3  #DE8658
color11 #DE8658
color4  #495057
color12 #495057
color5  #DC5BBC
color13 #DC5BBC
color6  #495057
color14 #495057
color7  #6C757D
color15 #F8F9FA
EOF

cat > "$CONF/kitty/themes/yael-square.conf" <<'EOF'
foreground              #FFFFFF
background              #161616
selection_foreground    #161616
selection_background    #FFFFFF
cursor                  #33B1FF
cursor_text_color       #161616

color0  #262626
color8  #8C8C8C
color1  #EE5396
color9  #EE5396
color2  #42BE65
color10 #42BE65
color3  #FFE97B
color11 #FFE97B
color4  #33B1FF
color12 #33B1FF
color5  #FF7EB6
color13 #FF7EB6
color6  #3DDBD9
color14 #3DDBD9
color7  #8C8C8C
color15 #FFFFFF
EOF

cat > "$CONF/kitty/themes/z0mbi3-square.conf" <<'EOF'
foreground              #A5B6CF
background              #0D0F18
selection_foreground    #0D0F18
selection_background    #A5B6CF
cursor                  #86AAEC
cursor_text_color       #0D0F18

color0  #1C1E27
color8  #6E8DB4
color1  #DD6777
color9  #DD6777
color2  #90CEAA
color10 #90CEAA
color3  #ECD3A0
color11 #ECD3A0
color4  #86AAEC
color12 #86AAEC
color5  #C296EB
color13 #C296EB
color6  #93CEE9
color14 #93CEE9
color7  #6E8DB4
color15 #A5B6CF
EOF


cp "$CONF/kitty/themes/catppuccin-mocha.conf" "$CONF/kitty/current.conf"

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
# Guard against overlapping invocations. xss-lock calls this script on
# idle/sleep AND Mod+l calls it directly, bypassing xss-lock entirely - if
# both fire close together (e.g. pressing Mod+l right as an idle-triggered
# lock is already showing the screensaver), a second i3lock process starts
# and can never win the X11 pointer/keyboard grab the first one already
# holds. i3lock retries for ~10s, displays "lock failed!" on screen, then
# gives up and exits - a real i3lock-color behavior (confirmed straight
# from i3lock.c/unlock_indicator.c on github.com/Raymo111/i3lock-color:
# grab_pointer_and_keyboard is retried for 1000ms then 9000ms before
# STATE_I3LOCK_LOCK_FAILED renders lock_failed_text and errx()s out) - not
# a bug in this script, but a race this script can trivially avoid by just
# not starting a redundant instance. flock (not a plain `pgrep i3lock`
# check) closes the TOCTOU gap between two lock.sh processes checking and
# acting at the same time.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lock.sh.lock"
flock -n 9 || exit 0

# --with-screensaver (passed by both xss-lock on idle activation and the
# Mod+l keybind) runs the block-art screensaver first; dismissing it (any
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
# 11a. Block-art screensaver (Terminal Text Effects) - Mod+Escape, and shown
#      automatically before an idle-triggered lock (see --with-screensaver
#      above). Inspired by Omarchy's built-in one, same underlying tool
#      (`tte`) AND the same logo style Omarchy itself ships (a solid Unicode
#      half-block render, not typed ASCII letters), just run in a plain
#      fullscreen kitty window instead of Omarchy's Astal/AGS shell (which i3
#      doesn't have an equivalent of).
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
# Astal/AGS shell (which i3 doesn't have an equivalent of). Exits on any
# keypress OR mouse movement.
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
# - the same ANSI palette ~/.local/bin/polybar-theme.sh keeps in sync with
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
  *""*)   i3-msg exit ;;
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
  read -r -p "Screensaver text (or a path to an image): " INPUT
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

if [ -f "$INPUT" ]; then
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
# 11e1. Polybar theme switcher - reachable from the app menu below, and
#       standalone as its own script.
# ----------------------------------------------------------------------------
log "Writing polybar theme switcher script..."
cat > "$BIN/polybar-theme.sh" <<'EOF'
#!/usr/bin/env bash
# Lists available themes (~/.config/polybar/themes/*.ini) via rofi and, on
# selection, applies matching polybar + rofi + kitty themes together, so
# one pick retints the whole desktop instead of just the bar. Each of the
# three is its own COMPLETE, standalone config (a polybar config.ini, a
# rofi .rasi pair, a kitty color .conf) generated from the same underlying
# palette per theme name - not a shared [colors] fragment three different
# tools each interpret slightly differently - applied with a plain file
# copy, no splicing to keep in sync.
#
# Usage:
#   polybar-theme.sh          # prompts via rofi
#   polybar-theme.sh <name>   # applies themes/<name>.* directly, no prompt
set -euo pipefail

POLY_THEMES_DIR="$HOME/.config/polybar/themes"
POLY_CONFIG="$HOME/.config/polybar/config.ini"
ROFI_THEMES_DIR="$HOME/.config/rofi/themes"
ROFI_CURRENT="$HOME/.config/rofi/current.rasi"
ROFI_POWERMENU_CURRENT="$HOME/.config/rofi/current-powermenu.rasi"
KITTY_THEMES_DIR="$HOME/.config/kitty/themes"
KITTY_CURRENT="$HOME/.config/kitty/current.conf"

mapfile -t THEME_FILES < <(find "$POLY_THEMES_DIR" -maxdepth 1 -name '*.ini' 2>/dev/null | sort)
if [ "${#THEME_FILES[@]}" -eq 0 ]; then
  notify-send "Desktop Theme" "No themes found in $POLY_THEMES_DIR"
  exit 1
fi

NAMES=()
for f in "${THEME_FILES[@]}"; do
  NAMES+=("$(basename "$f" .ini)")
done

CHOSEN="${1:-}"
if [ -z "$CHOSEN" ]; then
  CHOSEN="$(printf '%s\n' "${NAMES[@]}" | rofi -dmenu -i -p "Desktop Theme" -theme "$ROFI_CURRENT")"
fi
[ -z "$CHOSEN" ] && exit 0

POLY_FILE="$POLY_THEMES_DIR/$CHOSEN.ini"
ROFI_FILE="$ROFI_THEMES_DIR/$CHOSEN.rasi"
ROFI_POWERMENU_FILE="$ROFI_THEMES_DIR/$CHOSEN-powermenu.rasi"
KITTY_FILE="$KITTY_THEMES_DIR/$CHOSEN.conf"

if [ ! -f "$POLY_FILE" ]; then
  notify-send "Desktop Theme" "No such theme: $CHOSEN"
  exit 1
fi

cp "$POLY_FILE" "$POLY_CONFIG"
~/.local/bin/polybar-launch.sh

# rofi/kitty theme files are generated in lockstep with the polybar ones -
# missing here would mean a broken generation step, not a legitimate
# per-theme choice, so warn rather than silently skip.
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
  # Retint every already-open kitty window immediately via its remote-
  # control socket (listen_on in kitty.conf) - a fresh window picks up
  # current.conf on its own via kitty.conf's own include, but an existing
  # one needs to be told directly. kitty always appends the actual PID to
  # a unix socket path (confirmed empirically - a literal, non-templated
  # listen_on path is NOT what gets created), so every open kitty window
  # has its own distinctly-named socket under /tmp/kitty-mgns-<PID> - loop
  # over all of them rather than assuming a single fixed path. Best-effort:
  # no open kitty window (or one from before listen_on was added) just
  # means this loop no-ops for that socket.
  for sock in /tmp/kitty-mgns-*; do
    [ -S "$sock" ] || continue
    kitty @ --to "unix:$sock" set-colors -a "$KITTY_CURRENT" >/dev/null 2>&1 || true
  done
else
  notify-send "Desktop Theme" "No kitty theme for $CHOSEN, keeping previous"
fi

notify-send "Desktop Theme" "Switched to $CHOSEN"
EOF
chmod +x "$BIN/polybar-theme.sh"

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
# window - see the AppMenuTask for_window rule in i3/config - matching how
# copyq/cliamp already float; everything else just runs directly.
LABELS=(
  $'  Desktop Theme'
  $'  Set Screensaver Text/Image'
  $'  Preview Screensaver'
  $'  Toggle Caffeine'
  $'  Toggle Do Not Disturb'
  $'  Music Player'
  $'  Clipboard History'
  $'  Lock Screen'
  $'  Power Menu'
  $'  Reload i3'
  $'  Restart i3'
  $'  Keybinding Help'
)
COMMANDS=(
  "~/.local/bin/polybar-theme.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/set-screensaver-text.sh"
  "kitty --class Screensaver -e ~/.local/bin/screensaver.sh"
  "~/.local/bin/caffeine-toggle.sh"
  "~/.local/bin/dnd-toggle.sh"
  "kitty --class Cliamp -e cliamp"
  "copyq toggle"
  "~/.local/bin/lock.sh --with-screensaver"
  "~/.local/bin/powermenu.sh"
  "i3-msg reload"
  "i3-msg restart"
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

# ----------------------------------------------------------------------------
# 14c. CLIamp (terminal music player) - Mod+m
# ----------------------------------------------------------------------------
# Not packaged for Fedora - vendor curl|sh installer fetches a prebuilt
# release binary (no Go/build deps needed) into ~/.local/bin, same shape as
# the Claude Code installer pattern used elsewhere. Best-effort like
# snixembed/the Nerd Font above - a failed install just logs a warning.
if ! command -v cliamp >/dev/null 2>&1; then
  log "Installing CLIamp (terminal music player)..."
  if curl -fsSL https://raw.githubusercontent.com/bjarneo/cliamp/HEAD/install.sh | sh >/dev/null 2>&1 \
      && command -v cliamp >/dev/null 2>&1; then
    log "CLIamp installed ($(command -v cliamp)) - launch with Mod+m."
  else
    warn "CLIamp install failed (network issue) - install manually from https://www.cliamp.stream/ if you want it."
  fi
else
  log "CLIamp already installed, skipping."
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