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
#           18-theme bspwm collection) - each a full
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
  xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-xauth xrandr xset xsetroot xrdb \
  i3 i3lock \
  picom polybar rofi dunst kitty \
  xss-lock network-manager-applet pasystray blueman lxqt-policykit pipewire-pulseaudio \
  copyq udiskie pcmanfm gammastep libnotify nitrogen gnome-calendar \
  system-config-printer hplip \
  vala gtk3-devel libdbusmenu-devel libdbusmenu-gtk3-devel \
  lxappearance papirus-icon-theme \
  fastfetch git curl unzip jq flameshot ImageMagick xclip slop \
  brightnessctl playerctl numlockx dex-autostart autorandr arandr xdotool python3-xlib \
  dnf-utils \
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
#     is copied, only the *look*. The bullet/entry/lock/progress bar are
#     recolored to this rice's Mocha text color (#cdd6f4) via ImageMagick,
#     exactly how Omarchy's own theme-switcher does it; the wordmark itself
#     instead gets a left-to-right gradient across the Mocha accent
#     palette (mauve -> pink -> red -> peach -> yellow -> green -> teal ->
#     sky -> blue -> lavender, composited under the same letter-shape alpha
#     mask), since a single flat color read as plain/boring next to the
#     rest of this rice's colorful theming. The background is Mocha base
#     (#1e1e2e). All assets are embedded
#     below as base64 (a few KB total) rather than downloaded at setup
#     time - there's no upstream release to track the way the Nerd Font
#     download has, so there's nothing to fetch over the network here.
#
#     To revert to the stock boot splash later:
#       sudo plymouth-set-default-theme -R bgrt
# ----------------------------------------------------------------------------
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
iVBORw0KGgoAAAANSUhEUgAAAxAAAACoEAYAAAAgGNQ7AAAAIGNIUk0AAHomAACAhAAA+gAAAIDo
AAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRP///////wlY99wAAAAHdElNRQfqCQcKFjIyFKkN
AAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTA3VDEwOjIyOjQwKzAwOjAwGAvfqgAAACV0RVh0
ZGF0ZTptb2RpZnkAMjAyNi0wOS0wN1QxMDoyMjo0MCswMDowMGlWZxYAAAAodEVYdGRhdGU6dGlt
ZXN0YW1wADIwMjYtMDktMDdUMTA6MjI6NDkrMDA6MDCr2wMaAAAAEGNhTnYAAABOAAAAqAAAAAAA
AAAASyGaQwAADRpJREFUeNrt23+spNVdx/HPee7M3fIjW9iYLtJkCaBFKkpJaGtNaxExKVoi2ko0
RoPRVGywpWoQLJWisPysscRWaghpaEVTQru1SSuVQlMaG6XVUgxtlXVBfhXYttlll3t39945/rFL
jBqVvXPCYZjX65/N/jH3fp9nnnPmTt455Z57brllaSnwX/1LHi/rk/xpPpNXJvXSemtOSfLhfD7f
l2RXljNO8gd5a76aDD9a7q1XJcMPDb+Tk5KF3x7OmmxJxh9ZeNnk9cn4vNGNkx3J4pdG35x8OVm8
Y+G+yb3J+KdGV05WktE7Fp6enJ2MTho21XuSYan8TD0tKUeWT+eGJL+SN2Zrkm15Mocn9QO5PScm
uTQfyylJbqp35vuT+kR25JDeN4+DVvLSHJlkVN5V/jApi7ml3JlkXP4styVZyBnlrCSrubV+OKm7
61frR5I8ufrx1V9IsnX11JVbknx573v2bknyhT0/sfymJJ/d8ydL707qZ5d/Y/nNSe7Y86Wlv03y
d3u37Plikq/tO3bf+Ul9eHXrynlJvjv5wcljSZbryXVDkmRHvpNkVH4r70mymL84MNeHyieSLOTM
vKX3zWPNlnJPTkqyvb6//FKSp3JVfj3JzmzJjycZcliWkrw8N+SPkvL64Zz6WJK3DW+abErKTQvX
rH5Pkn8c37DymqQ8NT5t5dakLC9eue9dSdk5Pm/lmqQ8MH58ZXdSPjUaVj6Z5JKFuye3J+XNw5Z6
Y5IT8m/1zCSHljfkK0mW6z/lxCTbc332z3Vl+bWk7qwfzxlJJtltn5tBJY/lySRDrs/NSVmoF9TN
SRZyVf48SeoDeSjJpPxmfjGpe8spZZRk13Dq8GCS7aPrFsZJHh3vHv1IkgcXnxwfkmTr4vmLFybZ
uu7C8XuTbFtcPz4hySPjk8dvT/LU6IGFM5O6c3jncGSSPcO55aQkq7mu/F6S5Ok8k2TIB+pHk4zq
BbkiyZDN9UNJSr0/D/S+eRys8pIkJcn7MslRSXk6qzkxKTuyWk5MclVqNib5dEqeTuqlGdW7ktUH
c2guTvb+fY6oxyTLryhH1duSpeNzzOScZPf2HDc5Ltl1RY6fHPGf/3/m+BxTz0mWX5GjJrcl+w68
/tmfN7k0o9yV5DP7f1+5cv/vLzsOzHVgvmfnzbPz83+otfcE/8MRKbk3yckZ6u8n5bUZ5dwkJ2ao
VycZJ9mZ5B+yWm4spV6cPeWKpG7IzoVPJnVznhr9ZDJZyCOLdySrn8i2dZ9KJpuzdd0Jyeq12bru
6GRyRx5cd20yOTqPji9J6kfr9tG3k/oD2TVckOTa7B1+NqnfyCS/m2R9Sr6RlB/OkEuSvDYL9dwk
r8xQNyc5NCWP9L55HLSFDNmbZGMOz31Jji0b8rkkm3Jkvphkfdbl0STfzVKOS3J33ZaLk1ydu8p3
kvpj+eBwRVIfrW8bTk3qX9Yzhr9OJpfnVQt7k8m760mjQ5P6x/U1w8NJ/Vw9e+HKpC7momFnUs+t
f1VOT3JzvlLuSHJ/nshbkqxmksUkL8vh+eckx2ZD7jww191JXpqX1Id73zzWrrw625Mk78z9SZKL
cl+SlLOz/33dnVGS1PPyuiSpHyvvTZLJ3+Rfk2TlwuGtSbLvvOH2JNn3+WE5SfZdPGxIkr03DOuS
ZN/3lq8nycpkuCxJJm8ohyTJ5Oxyc5LU4w58D707G5Mkp+TbSZJ35OtJUi7eP1d+rj6UJDksK73v
HQftW9mXSZIb8608k9RL8lB2Jbk+j+eZpG7LclaTcm425pCkbMxpOToZRuWi8qpk4Y35Qs5KxleX
9Tk/Gb99OL1clixuK7+c65LFJ8uvlvcl42uGM3N5Mr6zvLxckIyuKl/LzyfD63J5Xp2U0/PTZVNS
LiubcliSXVlNTepN9YksJbkk/55dSX1/HsszSb6Zpep5478Zeg8AAAAAAAC8+AgQAAAAAABAcwIE
AAAAAADQnAABAAAAAAA0J0AAAAAAAADNCRAAAAAAAEBzAgQAAAAAANDcaP8/tfYeBGZXKb0n6Mv+
AWtn/+g9AfNs3tffvLP/9NX7/lv/s63388N8s3/Qk/2vL+t/rZyAAAAAAAAAmhMgAAAAAACA5gQI
AAAAAACgOQECAAAAAABoToAAAAAAAACaEyAAAAAAAIDmBAgAAAAAAKC5Ue8BAADg+Vdr399fSu87
MNt6v3/Mtt7Pj/UPs8v+AfNr2vU/v+vXCQgAAAAAAKA5AQIAAAAAAGhOgAAAAAAAAJoTIAAAAAAA
gOYECAAAAAAAoDkBAgAAAAAAaE6AAAAAAAAAmhv1HgAAAAAA+P/UOt3rS+l9BcD8cQICAAAAAABo
ToAAAAAAAACaEyAAAAAAAIDmBAgAAAAAAKA5AQIAAAAAAGhOgAAAAAAAAJoTIAAAAAAAgOZGvQd4
cSil9wRAL9Y/sFazvn/U2nuC2Tbt/fP8zDfv/2yb9/XPdOb9/Z/3/QNg9jgBAQAAAAAANCdAAAAA
AAAAzQkQAAAAAABAcwIEAAAAAADQnAABAAAAAAA0J0AAAAAAAADNCRAAAAAAAEBzo94DvDCU0nsC
AIDZ0vvvp1p73wFYu97rp7dpr9/6h/ll/2CWef6YT05AAAAAAAAAzQkQAAAAAABAcwIEAAAAAADQ
nAABAAAAAAA0J0AAAAAAAADNCRAAAAAAAEBzAgQAAAAAANDcqPcAAAAAAAC8mJUy3etr7X0FrI0T
EAAAAAAAQHMCBAAAAAAA0JwAAQAAAAAANCdAAAAAAAAAzQkQAAAAAABAcwIEAAAAAADQnAABAAAA
AAA0N+o9AAAAAAAAvHjVOt3rS+l9BWvlBAQAAAAAANCcAAEAAAAAADQnQAAAAAAAAM0JEAAAAAAA
QHMCBAAAAAAA0JwAAQAAAAAANCdAAAAAAAAAzQkQAAAAAABAcwIEAAAAAADQnAABAAAAAAA0J0AA
AAAAAADNCRAAAAAAAEBzAgQAAAAAANCcAAEAAAAAADQnQAAAAAAAAM2Neg/wwlBr7wnoqZTeEzDL
7B/zzf4BAADPne9PMLt8/2VtnIAAAAAAAACaEyAAAAAAAIDmBAgAAAAAAKA5AQIAAAAAAGhOgAAA
AAAAAJoTIAAAAAAAgOYECAAAAAAAoLlR7wEAAAAAeC5q7T0BPZXSe4L5Zv31Ne3z7/3rxQkIAAAA
AACgOQECAAAAAABoToAAAAAAAACaEyAAAAAAAIDmBAgAAAAAAKA5AQIAAAAAAGhOgAAAAAAAAJob
9R4AAAAAAAD439Q63etL6TW5ExAAAAAAAEBzAgQAAAAAANCcAAEAAAAAADQnQAAAAAAAAM0JEAAA
AAAAQHMCBAAAAAAA0JwAAQAAAAAANDfqPQDAfCul9wQAAAA8F76/ARwsJyAAAAAAAIDmBAgAAAAA
AKA5AQIAAAAAAGhOgAAAAAAAAJoTIAAAAAAAgOYECAAAAAAAoDkBAgAAAAAAaG7Ue4AXhlJ6TwDM
KvsHAADwfOn9/aPW3ncA6MX6Z22cgAAAAAAAAJoTIAAAAAAAgOYECAAAAAAAoDkBAgAAAAAAaE6A
AAAAAAAAmhMgAAAAAACA5gQIAAAAAACguVHvAQAAAADgha/W6V5fSu8rmG/Tvn/AWjgBAQAAAAAA
NCdAAAAAAAAAzQkQAAAAAABAcwIEAAAAAADQnAABAAAAAAA0J0AAAAAAAADNCRAAAAAAAEBzo94D
AAAAADALSpnu9bX2vgKA+TTt/rv2/d8JCAAAAAAAoDkBAgAAAAAAaE6AAAAAAAAAmhMgAAAAAACA
5gQIAAAAAACgOQECAAAAAABoToAAAAAAAACaG/UeAACAeVRr7wkAAJ5f0/79U0rvK2CWeX6m4/vL
WjkBAQAAAAAANCdAAAAAAAAAzQkQAAAAAABAcwIEAAAAAADQnAABAAAAAAA0J0AAAAAAAADNCRAA
AAAAAEBzo94DAMy2WntPwCwrpfcE9GT/gPnVe/1P+/nTe35gdtl/AOaNExAAAAAAAEBzAgQAAAAA
ANCcAAEAAAAAADQnQAAAAAAAAM0JEAAAAAAAQHMCBAAAAAAA0JwAAQAAAAAANDfqPQAAAMyfUnpP
MNvXX2vvK5ht7l9f877+gbWbdv+e9f3H5xfMIicgAAAAAACA5gQIAAAAAACgOQECAAAAAABoToAA
AAAAAACaEyAAAAAAAIDmBAgAAAAAAKA5AQIAAAAAAGhu1HsAAACYPaX0nmC+TXv/a+19Bcwy6x/6
sf8zz3z+0NPa908nIAAAAAAAgOYECAAAAAAAoDkBAgAAAAAAaE6AAAAAAAAAmhMgAAAAAACA5gQI
AAAAAACgOQECAAAAAABobtR7AAAAOHil9J6AWTbt81Nr7ytgGvYPYF5N+/ll/2Se+ftxrZyAAAAA
AAAAmhMgAAAAAACA5gQIAAAAAACgOQECAAAAAABoToAAAAAAAACaEyAAAAAAAIDmBAgAAAAAAKC5
/wB+iUl4PjHaZgAAAABJRU5ErkJggg==
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

# Always overwrite rather than skip-if-exists (this rice's usual
# convention everywhere else) - re-running after an asset/script change
# used to silently no-op forever once the theme directory existed once,
# which is exactly what made a wordmark recolor invisible until someone
# noticed and asked how to force a reinstall. sudo rm + cp -r instead of
# cp -rT since -T isn't available in all cp versions this might run on.
sudo rm -rf /usr/share/plymouth/themes/catppuccin-mocha
if sudo cp -r "$TMPPLYMOUTH" /usr/share/plymouth/themes/catppuccin-mocha \
    && sudo plymouth-set-default-theme -R catppuccin-mocha; then
  log "Plymouth theme set to catppuccin-mocha (reboot to see it on the LUKS decrypt screen)."
else
  warn "Plymouth theme install/activation failed; boot splash left on its current theme. Revert/retry manually: sudo plymouth-set-default-theme -R bgrt"
fi
rm -rf "$TMPPLYMOUTH"

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
# Force a normal border on every window, regardless of what the app itself
# asks for. VS Code, Claude Desktop, and some Electron/CSD-style Edge
# windows explicitly set _MOTIF_WM_HINTS requesting zero decorations
# (confirmed live via `xprop _MOTIF_WM_HINTS`: flags=0x2, decorations=0),
# and i3 honors that per-window request over `default_border` - the
# visible symptom was no border/focus indicator at all on those specific
# windows, so with two side by side (e.g. two VS Code windows) neither
# showed which one actually had focus. A wildcard for_window rule matching
# every class runs after the automatic no-decoration handling and wins,
# restoring the focused/unfocused border distinction uniformly. Only
# applies to windows as they're first mapped, same as every other
# for_window rule here - an already-open offending window needs a one-off
# `i3-msg '[class="..."] border pixel 2'` to fix retroactively.
for_window [class=".*"] border pixel 2
# Settings-style dialogs launched from the polybar network/bluetooth widgets,
# copyq's clipboard menu, and Evolution's calendar/task reminder popup - float
# + center + shrink instead of tiling full-height like a regular window.
for_window [class="^Nm-connection-editor$"] floating enable, resize set 550 450, move position center
for_window [class="^Blueman-manager$"] floating enable, resize set 500 400, move position center
for_window [class="^copyq$"] floating enable, resize set 450 500, move position center
# mark lets cliamp-toggle.sh scratchpad-hide/show this specific window
# (i3's closest equivalent to minimize) instead of quitting cliamp being
# the only way to get it out of the way.
# Split into two for_window lines rather than chaining `mark` onto the
# floating/resize/move command list on one line - confirmed live that the
# chained form silently never applies the mark (floating/resize/move all
# take effect, mark alone doesn't stick), while a separate line for it
# works every time.
for_window [class="^Cliamp$"] floating enable, resize set 700 500, move position center
for_window [class="^Cliamp$"] mark cliamp-scratch
# Fullscreen, not a fixed floating size - cliamp setup is a full-TUI
# wizard that redraws the whole screen rather than appending scrollable
# terminal output, so a form taller than the window is just clipped with
# no way to reach it (confirmed directly: a fixed 700x550 box cut off
# fields on some provider forms). Fullscreen guarantees the maximum
# space every time instead of guessing a size that might still be short
# for some provider's form.
for_window [class="^CliampSetup$"] fullscreen enable
# Same "own line, not chained" requirement as the Cliamp rule above - a
# chained `mark` silently never applies.
for_window [class="^AIVibe$"] floating enable, resize set 900 650, move position center
for_window [class="^AIVibe$"] mark ai-window-scratch
for_window [class="^AppMenuTask$"] floating enable, resize set 600 400, move position center
for_window [class="^KeybindingsHelp$"] floating enable, resize set 950 850, move position center
for_window [class="^UpdatesTask$"] floating enable, resize set 1000 550, move position center
for_window [class="^gnome-calendar$"] floating enable, resize set 700 550, move position center
for_window [class="^System-config-printer\.py$"] floating enable, resize set 750 550, move position center
# Sized so the sidebar (chat list/projects), the chat input's model/mode
# selectors, and the scheduled-tasks section below it are all visible at
# once without clipping - confirmed live at this size (a tighter one left
# the scheduled-tasks list cut off at the bottom).
for_window [class="^com\.anthropic\.Claude$"] floating enable, resize set 1200 850, move position center
# Own line, not chained onto the rule above - same "a chained `mark`
# silently never applies" gotcha as the AIVibe/Cliamp rules.
for_window [class="^com\.anthropic\.Claude$"] mark claude-desktop-scratch
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

# --- colorpicker (grab any on-screen pixel's color as hex) ---
bindsym $mod+shift+g exec --no-startup-id ~/.local/bin/colorpicker.sh

# --- clipboard history (copyq) ---
bindsym $mod+shift+v exec --no-startup-id copyq toggle

# --- music (cliamp, https://www.cliamp.stream/) ---
# cliamp-toggle.sh launches it fresh if not running, otherwise
# scratchpad-hides/shows the window (i3's closest equivalent to minimize) -
# playback, MPRIS, and its IPC socket all keep working while hidden, so
# polybar's media widget still controls it.
bindsym $mod+m exec --no-startup-id ~/.local/bin/cliamp-toggle.sh
# `cliamp setup` - a genuinely different command from bare cliamp above,
# not the same app reached a different way. Picking/configuring a remote
# source (Navidrome, Plex, Spotify, ...) only happens in this wizard's own
# "Pick a provider to configure" screen - the player's own TUI (mod+m) has
# no path to it at all, confirmed by testing its actual keybindings.
bindsym $mod+shift+m exec --no-startup-id ~/.local/bin/cliamp-setup.sh

# --- AI window (Mistral Vibe CLI, `vibe`) ---
# Same scratchpad show/hide toggle as cliamp above: ai-window-toggle.sh
# launches a fresh floating kitty+vibe session if none exists yet,
# otherwise just tucks the existing one away/back so an in-progress
# conversation isn't lost by pressing the key again.
bindsym $mod+a exec --no-startup-id ~/.local/bin/ai-window-toggle.sh

# --- keybinding help ---
# Mod+k/Mod+shift+k are both already taken (focus/move window up), so this
# is Mod+i instead - also reachable from the app menu below. Opens in its
# own floating kitty window (for_window rule above), dismissed by any
# keypress.
bindsym $mod+i exec --no-startup-id kitty --class KeybindingsHelp -e ~/.local/bin/keybindings-help.sh

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
bindsym $mod+shift+XF86Assistant exec --no-startup-id ~/.local/bin/claude-desktop-toggle.sh

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
# h/v/l are already taken above (focus-left, copyq, lock), so these use free
# keys instead of i3's own h/v defaults. Sets the split direction for the
# NEXT window opened in the focused container - not a drag-and-drop tile
# picker - so e.g. two terminals stacked with a third beside them is: open
# terminal 1, $mod+v, open terminal 2 (stacks below), focus that column,
# $mod+b, open terminal 3 (appears beside the column).
bindsym $mod+v split v
bindsym $mod+b split h
bindsym $mod+t layout toggle split

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
# GDM's i3.desktop just execs i3 directly - unlike gnome-session, nothing
# ever imports this session's DISPLAY/XAUTHORITY into systemd --user's
# activation environment. dbus-update-activation-environment fixes that
# half; separately, logind isn't wiring a Desktop= property onto this
# session (checked via `loginctl show-session <id>` - Type/Class/Active
# are all correct, Desktop= is just absent), so graphical-session.target
# (systemd --user) never auto-activates, and it's RefuseManualStart=yes so
# it can't be started by hand either. Everything gated on it -
# xdg-desktop-portal.service and its gtk backend, both
# Requisite=graphical-session.target - then fails with "Dependency
# failed" (see journalctl --user), which breaks org.freedesktop.portal.
# Desktop: the D-Bus service apps without their own GTK/Qt file chooser
# (e.g. Zed) call for the native Open File/Folder dialog, so it shows up
# empty/broken instead of listing files. Bypass systemd's normal
# activation for just these two: run them as their own transient units
# (still gets a real cgroup/lifecycle, unlike a bare backgrounded
# process) so they claim their D-Bus names directly regardless of
# graphical-session.target's state. The busctl check keeps `i3 restart`
# (which re-runs exec, not just exec_always) from spawning a second
# instance on top of one that's already claimed the name.
# Loads Xcursor.theme/Xcursor.size (written to ~/.Xresources during setup)
# into the X RESOURCE_MANAGER - some xcb-cursor-based apps (confirmed:
# polybar) resolve the cursor theme through these X resources rather than
# (or in addition to) the XCURSOR_THEME/XCURSOR_SIZE environment variables,
# and this rice never used Xresources/xrdb before so nothing ever loaded
# them. Must run before xsetroot/polybar below, not after.
exec --no-startup-id xrdb -merge ~/.Xresources
# i3 never sets a root-window cursor of its own - without this, the
# desktop background (anywhere with no window under the pointer) shows
# X11's stock default cursor regardless of XCURSOR_THEME/gtk-cursor-theme-
# name above, since those only cover apps that ask libXcursor/GTK for a
# themed cursor, not the root window itself. `left_ptr` still resolves
# through the current XCURSOR_THEME, so this picks up the Catppuccin
# cursor theme too, not a hardcoded fallback shape.
exec --no-startup-id xsetroot -cursor_name left_ptr
exec --no-startup-id dbus-update-activation-environment --systemd --all
exec --no-startup-id sh -c 'busctl --user status org.freedesktop.portal.Desktop >/dev/null 2>&1 || systemd-run --user --unit=xdg-desktop-portal-manual --collect /usr/libexec/xdg-desktop-portal'
exec --no-startup-id sh -c 'busctl --user status org.freedesktop.impl.portal.desktop.gtk >/dev/null 2>&1 || systemd-run --user --unit=xdg-desktop-portal-gtk-manual --collect /usr/libexec/xdg-desktop-portal-gtk'
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
# Guard against a duplicate dunst instance (harmless if it ever happens -
# only one wins the org.freedesktop.Notifications D-Bus name - but cheap
# to avoid). Plain `exec` only runs on a genuine fresh i3 startup, not on
# `i3 restart` (confirmed directly - restart does NOT re-run these), so
# this mainly guards against manually re-triggering the same exec by hand.
exec --no-startup-id sh -c 'pgrep -x dunst >/dev/null || dunst'
# playerctld tracks which MPRIS player (browser tab, cliamp, Spotify, ...)
# was MOST RECENTLY active and exposes it as a virtual player - without
# it, plain unprefixed `playerctl` calls (what polybar-media.sh uses) just
# pick whichever player happens to be first in an arbitrary discovery
# order, which is why the polybar media buttons only ever seemed to
# control the browser/cliamp and never Spotify (confirmed directly:
# `playerctl -p spotify play-pause` always worked fine on its own -
# Spotify's MPRIS interface was never the problem). With playerctld
# running, the same unprefixed calls automatically follow whichever
# player was touched most recently, no changes needed to polybar-media.sh.
exec --no-startup-id sh -c 'pgrep -x playerctld >/dev/null || playerctld'
# Evolution's own calendar/task reminder popup (evolution-alarm-notify) is
# disabled entirely (autostart Hidden=true + `systemctl --user mask
# evolution-alarm-notify.service` - masking, not just disabling, since it's
# a D-Bus-activatable service and would otherwise still get launched the
# moment anything talks to its bus name regardless of systemd enablement)
# because it's a GTK window fixed to Catppuccin Mocha with no way to follow
# this rice's active theme. This polls the same real calendar data via the
# same EDataServer/ECal API evolution-alarm-notify itself uses and fires a
# themed dunst notification instead - dunst already tracks the active
# theme, and its own DND pause state already suppresses these the same way
# it suppresses everything else, no separate toggle needed.
# Same pgrep-guard intent as dunst above, and more important here: a
# duplicate would mean two processes polling and writing
# ~/.cache/calendar-reminder-notified.json at once. The obvious inline
# version - sh -c 'pgrep -f calendar-reminder-daemon.py >/dev/null ||
# python3 ~/.local/bin/calendar-reminder-daemon.py' - looked right but
# never actually worked: pgrep -f matches a process's FULL command line,
# and that inline command's own argv literally contains the search text
# twice (the pgrep pattern and the fallback command), so it always
# matched itself and never fell through to actually launch the daemon.
# Confirmed the hard way: a real reboot left the daemon silently not
# running at all, with no error anywhere. Kept as its own script so the
# checking process's command line has no reason to contain that text.
exec --no-startup-id ~/.local/bin/calendar-reminder-daemon-launch.sh
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
# Idle-based lock: screensaver activation at 20min (triggers xss-lock ->
# lock.sh --with-screensaver, which force-blanks the display immediately on
# lock regardless of these DPMS timers - see lock_and_blank() in lock.sh).
# DPMS standby/suspend/off all at 50min is a fallback for total abandonment
# (screensaver.sh has no timeout of its own - it just keeps rendering until
# a keypress, so without this the monitor would stay lit forever). Must
# stay strictly LATER than the screensaver's own 20min mark, not equal to
# it: DPMS is a separate subsystem from the X screensaver extension xss-
# lock listens to, and blanks the monitor at the hardware level regardless
# of what's on screen - confirmed live, with both set to the same value
# the monitor was going dark at the 20min mark right along with (sometimes
# fractionally before) the screensaver itself became visible, making it
# look like idle skipped straight to sleep instead of showing the
# screensaver first.
exec --no-startup-id xset s 1200 dpms 3000 3000 3000

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
  "window_type = 'menu'",
  "override_redirect = true"
];
# slop's own click-to-pick overlay (colorpicker.sh, Mod+shift+g) is an
# override-redirect window with no conventional WM_CLASS - same shape as
# i3lock and the browser context menus above, and the same property
# fade-exclude already uses to target i3lock specifically. Without this,
# picom blurs the entire screen behind slop's crosshair while it's active,
# making it hard to see the exact pixel being picked. This is a blanket
# rule (matches every override-redirect window, not just slop) - the same
# trade-off fade-exclude's own override_redirect entry already accepts,
# so dropdown menus/tooltips/notifications lose background blur too.

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
modules-right = sep-base-mauve-cap tray-cap sep-mauve-cap-surface0 tray sep-surface0-sky backlight sep-sky-mauve pulseaudio sep-mauve-teal media sep-teal-blue network-wired network-wireless sep-blue-teal bluetooth sep-teal-green caffeine sep-green-red dnd sep-red-peach battery sep-peach-yellow memory sep-yellow-green cpu sep-green-yellow updates sep-yellow-lavender layout sep-yellow-lavender date-icon date

[bar/top-secondary]
inherit = bar/base
; same as top-primary minus tray/battery - without this split every extra
; monitor showed a permanently empty tray slot since only one instance can
; ever win the X11 tray selection.
modules-right = sep-base-sky backlight sep-sky-mauve pulseaudio sep-mauve-teal media sep-teal-blue network-wired network-wireless sep-blue-yellow memory sep-yellow-green cpu sep-green-yellow updates sep-yellow-lavender date-icon date

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

[module/sep-green-yellow]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.green}
label-background = ${colors.yellow}

[module/sep-yellow-lavender]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.yellow}
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
label = "%{A1:GTK_THEME=Rice-catppuccin-mocha gnome-calendar &:}    %{A}"
label-font = 1
label-foreground = ${colors.base}
format-background = ${colors.lavender}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-catppuccin-mocha gnome-calendar &:}  %date%  %time%  %{A}"
label-font = 3
label-foreground = ${colors.base}
format-background = ${colors.lavender}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "  󰃟 %output%% "
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.base}
format-background = ${colors.yellow}
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
type = custom/script
exec = WIFI_PREFIX='   ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#1e1e2e' WIFI_OFF_FG='#f38ba8' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #89b4fa

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
ICO_SPLIT_H=$'󰯌'   # nf-md-view_split_vertical (vertical divider -> side-by-side panes = i3 splith)
ICO_SPLIT_V=$'󰯋'   # nf-md-view_split_horizontal (horizontal divider -> stacked panes = i3 splitv)
ICO_STACKING=$'󰕪'  # nf-md-view_agenda (i3 "stacked" layout)
ICO_TABBED=$'󰓩'    # nf-md-tab (i3 "tabbed" layout)

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
# request rather than iterated on further.
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
radius = 8
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
modules-right = tray sep-plain backlight sep-plain pulseaudio sep-plain media sep-plain cliamp sep-plain network-wired network-wireless sep-plain bluetooth sep-plain caffeine sep-plain dnd sep-plain battery sep-plain memory sep-plain cpu sep-plain updates sep-plain layout sep-plain date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep-plain pulseaudio sep-plain media sep-plain cliamp sep-plain network-wired network-wireless sep-plain memory sep-plain cpu sep-plain updates sep-plain date-icon date

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
label = "%{A1:GTK_THEME=Rice-dracula gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.mauve}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-dracula gnome-calendar &:}%date%  %time%%{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = " 󰃟 %output%%"
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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='  ' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#8be9fd' WIFI_OFF_FG='#ff5555' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-right = backlight pulseaudio media cliamp network-wired network-wireless bluetooth gap-nord caffeine dnd battery gap-nord memory cpu updates gap-nord layout gap-nord tray gap-nord date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless gap-nord memory cpu updates gap-nord date-icon date

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
label = "%{A1:GTK_THEME=Rice-nord gnome-calendar &:} 󰃰 %{A}"
label-font = 1
label-foreground = ${colors.lavender}
format-background = ${colors.surface0}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-nord gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}
format-background = ${colors.surface0}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = " 󰃟 %output%% "
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
format-background = ${colors.surface0}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.green}
format = <label>
format-background = ${colors.surface0}

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.sky}
format-connected-background = ${colors.surface0}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='  ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#88c0d0' WIFI_OFF_FG='#bf616a' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #3b4252

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>
format-background = ${colors.surface0}

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/alireza.ini" <<'EOF'
; Alireza - modeled directly on codeberg.org/alirezaalavi/dotfiles' real i3
; setup, corrected against its own screenshots (screenshots/i3_dracula_2025-
; {1,2,3}.png) after an earlier config-only pass missed the actual look:
; that i3bar/i3status-rust bar renders almost everything in plain WHITE
; text (icons.icons="awesome6" gives small monochrome glyphs, not per-
; module colored ones) on a bar that's visibly near-black - noticeably
; darker than the #282a36 window/terminal background seen in the same
; screenshots (nvim, the file manager, the terminal), not the same shade -
; ported here as a distinct "mantle" (bar-only) vs "base" (everything
; else) split, unlike most other themes in this set which keep the two
; identical. Color is reserved for the workspace indicator (their own
; colorscheme.conf: focused/urgent both FILL border+background with
; accent, not just text) and for in-app selection highlights, which the
; screenshots show as PINK far more often than the purple their i3
; colorscheme.conf uses for window borders (the file manager's selected
; row, the terminal music player's selected track, and the cava-style
; volume bars are all pink) - ported as this theme's dominant in-app
; accent, with purple kept specifically for the window-border/workspace-
; chip role their colorscheme.conf actually specifies. Two of their own
; deviations from stock Dracula carry over unchanged from the first pass:
; a brighter red (#FF5E76, used consistently in both their i3 colorscheme
; and their sway waybar CSS - not a one-off) instead of stock #ff5555, and
; a second lighter purple ("purple_dark1", #938BFF, named "lavender" here)
; for inactive workspace text.
[colors]
base     = #282A36
mantle   = #191A21
surface0 = #44475A
text     = #F8F8F2
subtext  = #6272A4
purple   = #BD93F9
lavender = #938BFF
red      = #FF5E76
green    = #50FA7B
orange   = #FFB86C
pink     = #FF79C6
yellow   = #F1FA8C
cyan     = #8BE9FD

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.mantle}
foreground = ${colors.text}
radius = 8
padding-left = 2
padding-right = 2
module-margin = 1
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
underline-size = 2
overline-size = 2
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Plain white text throughout, matching the source's actual near-monochrome
; bar (its own real accents show up on window borders and in-app selections,
; not here) - only the workspace chip and low-battery/muted-volume states
; get real color, same restraint the source's own bar shows.
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
; Focused gets a frame (underline+overline), not a solid fill - a filled
; chip on top of the font read visually heavier/larger than intended.
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.purple}
label-focused-underline = ${colors.purple}
label-focused-overline = ${colors.purple}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.lavender}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-alireza gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "%percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#F8F8F2' WIFI_OFF_FG='#FF5E76' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.pink}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.pink}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

; Only the "low" state (under low-at%, not charging) actually gets colored -
; one of the only places the source's otherwise monochrome bar shows real
; color at all.
[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/archblur.ini" <<'EOF'
; Archblur - modeled directly on github.com/kiddae/polybar-themes'
; "arch-blur" bar (confirmed by reading a full local clone). That whole
; archive's configs pull every color from the user's own ~/.Xresources via
; xrdb, with only bare black/white as fallbacks - no fixed palette is
; actually checked in for any of its themes. Its bspwmrc, though, sources
; "$HOME/.colors/gruvbox/gruvbox.sh" for its actual real desktop colors
; (confirmed live in the source archive's own "tiny" folder screenshot,
; showing that exact
; source line) - real, published Gruvbox Dark values used here for every
; theme drawn from this archive, differing between them by structure
; (height/radius/spacing/accent role) rather than a from-scratch palette
; each time, the same way the archive's own bar variants were always
; meant to share one desktop colorscheme.
[colors]
base     = #282828
mantle   = #1D2021
surface0 = #3C3836
surface1 = #504945
text     = #EBDBB2
subtext  = #A89984
red      = #FB4934
green    = #B8BB26
yellow   = #FABD2F
blue     = #83A598
purple   = #D3869B
aqua     = #8EC07C
orange   = #FE8019
gray     = #928374

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 32
background = ${colors.base}
foreground = ${colors.text}
bottom = true
radius = 10
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center = media

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.orange}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.orange}
label-focused-underline = ${colors.orange}
label-focused-overline = ${colors.orange}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-archblur gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "%percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#EBDBB2' WIFI_OFF_FG='#FB4934' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.orange}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.orange}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

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
radius = 8
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
modules-right = backlight dot pulseaudio dot media dot cliamp dot network-wired network-wireless dot bluetooth dot caffeine dot dnd dot battery dot memory dot cpu dot updates dot layout dot LD date-icon date RD

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dot pulseaudio dot media dot cliamp dot network-wired network-wireless dot memory dot cpu dot updates dot LD date-icon date RD

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
label = "%{A1:GTK_THEME=Rice-archcraft gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.peach}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:GTK_THEME=Rice-archcraft gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = " 󰃟 %output%% "
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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='  ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#56b6c2' WIFI_OFF_FG='#e06c75' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
teal = #9CCFD8
; Dedicated dark, fully-opaque backdrop for the system tray specifically -
; most tray icons (Discord, 1Password, etc.) are drawn in white/light
; colors expecting a dark bar and become invisible against this theme's
; own light cream chips (caught via direct feedback, not assumed).
tray-bg = #3D3757
green = #286983
yellow = #EA9D34
red = #B4637A
blue = #56949F

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
modules-right = bi backlight pulseaudio media cliamp bd sep bi network-wired network-wireless bd sep bi bluetooth caffeine dnd bd sep bi battery memory cpu filesystem updates layout bd sep bi-tray tray bd-tray

[bar/top-secondary]
inherit = bar/base
modules-right = bi backlight pulseaudio media cliamp bd sep bi network-wired network-wireless bd sep bi memory cpu filesystem updates bd

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
ws-icon-0 = 1;%{F#76aaff}󰬺%{F-}
ws-icon-1 = 2;%{F#ad78cf}󰬻%{F-}
ws-icon-2 = 3;%{F#70d7c5}󰬼%{F-}
ws-icon-3 = 4;%{F#f09e6c}󰬽%{F-}
ws-icon-4 = 5;%{F#f46bc9}󰬾%{F-}
ws-icon-5 = 6;%{F#ef658c}󰬿%{F-}
ws-icon-6 = 7;%{F#76aaff}󰭀%{F-}
ws-icon-7 = 8;%{F#ad78cf}󰭁%{F-}
ws-icon-8 = 9;%{F#70d7c5}󰭂%{F-}
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
label = "%{A1:GTK_THEME=Rice-aline gnome-calendar &:}%date%  %time%%{A}"
label-font = 3

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %output%% "

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#575279' WIFI_OFF_FG='#B4637A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #F2E9E1

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-background = ${colors.surface0}
format-mounted-prefix = " "
format-mounted-prefix-foreground = ${colors.text}
label-mounted = " %percentage_used%% "

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.tray-bg}
format-background = ${colors.tray-bg}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/breddie.ini" <<'EOF'
; Breddie - modeled directly on codeberg.org/breddiesucks/dotfiles' real
; polybar/rofi/dunst/alacritty configs and its actual XMonad window-border
; colors (xmonad/xmonad.hs: myFocusedBorderColor "#acb0d0", myNormalBorder-
; Color "#444b61" - confirmed by reading a full local clone), plus its own
; screenshots (.showoff/01.png, 02.png) for the overall look: a near-black
; TokyoNight-family background (#1a1b26, its alacritty.toml's own primary
; background - the same well-known open palette this rice's own "daniela"
; theme already called "Tokyo-Night-ADJACENT" rather than exact; this port
; uses the source's real hex values directly) with an almost monochrome
; bar - workspace numbers and stats all in one muted light color, no
; per-module color-coding - color reserved for the focused-workspace
; accent and alert states, the same restraint this rice's own "isabel"/
; "alireza" ports already follow for similarly minimal sources.
;
; Two real bugs in the source were not carried over, same policy already
; applied to this rice's own "isabel"/"pamela" ports: its polybar
; [colors] "alert" is a literal typo (`#D9EBCB8R` - R isn't a hex digit),
; clearly meant to be its alacritty yellow (`#ebcb8c`) - used here as
; intended. Its xworkspaces "active" state sets a background-alt that's
; IDENTICAL to the bar's own background (`background-alt = background`),
; making the focused-workspace indicator invisible in practice - given a
; real underline+overline frame instead (this rice's own "alireza" fix for
; the same class of problem), using the real accent its xmonad.hs actually
; assigns to focused windows (`#acb0d0`) rather than an invisible chip.
[colors]
base     = #1A1B26
mantle   = #1A1B26
surface0 = #292A44
text     = #E5E9F0
subtext  = #444B61
lavender = #ACB0D0
blue     = #7AA2F7
cyan     = #0DB9D7
green    = #9ECE6A
yellow   = #EBCB8C
orange   = #FF9E64
red      = #F7768E
purple   = #BB9AF7

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 8
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.lavender}
label-focused-underline = ${colors.lavender}
label-focused-overline = ${colors.lavender}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.yellow}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-breddie gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "VOL %percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "MUTED"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#E5E9F0' WIFI_OFF_FG='#F7768E' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.purple}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

; Only the "low" state (under low-at%, not charging) actually gets colored -
; matching the near-monochrome restraint the source's own bar shows.
[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
; A filesystem widget (real source has one) was tried and reverted -
; tested live, its extra icon+value box pushed the whole cluster past
; the bar's own right edge, spilling half outside the rounded corner.
; Fitting first, not squeezing in a widget that doesn't fit.
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
radius = 8
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
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep cliamp sep network-icon network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery-icon battery sep memory-icon memory sep cpu-icon cpu sep updates sep layout sep tray sep date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep cliamp sep network-icon network-wired network-wireless sep memory-icon memory sep cpu-icon cpu sep updates sep date-icon date

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
label = "%{A1:GTK_THEME=Rice-brenda gnome-calendar &:} %date%  %time% %{A}"
label-foreground = ${colors.base}

[module/backlight-icon]
type = custom/text
format = <label>
format-background = ${colors.yellow}
label = " 󰃟 "
label-foreground = ${colors.base}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
label = " %output%% "
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
exec = ~/.local/bin/polybar-media-boxed.sh
interval = 1
click-left = playerctl previous &
click-middle = playerctl play-pause &
click-right = playerctl next &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}
label-padding = 1

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#2D353B' WIFI_OFF_FG='#E67E80' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #F8F5E4

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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
[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}
label-padding = 1

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.base}
format-background = ${colors.base}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/cherryblocks.ini" <<'EOF'
; Cherryblocks - modeled directly on github.com/kiddae/polybar-themes'
; real "cherryblocks" bar (config read from a full local clone). Its
; defining, name-giving trait is SOLID FILLED CHIPS: every widget renders
; as `format-background = <accent>` with inverted (base-colored) text,
; not a shared group background or an underline - confirmed directly in
; its own config (`format-background = ${color.color1}`, `format-
; foreground = ${color.background}` on the workspace/mpd/time modules).
; The real source also splits this into three separate floating bars
; (workspace, music, tray) with true gaps of desktop between them - this
; rice's shared polybar-launch.sh only ever launches one bar per monitor,
; so that part is approximated with real gap modules between clusters
; inside a single bar instead (the chip look itself, its main visual
; identity, is not approximated - it's the real thing). Gruvbox Dark
; palette (see "archblur" for how that was confirmed).
[colors]
base     = #282828
mantle   = #1D2021
surface0 = #3C3836
surface1 = #504945
text     = #EBDBB2
subtext  = #A89984
red      = #FB4934
green    = #B8BB26
yellow   = #FABD2F
blue     = #83A598
purple   = #D3869B
aqua     = #8EC07C
orange   = #FE8019
gray     = #928374

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 10
padding-left = 2
padding-right = 2
module-margin = 3
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray gap-cb backlight pulseaudio media cliamp gap-cb network-wired network-wireless bluetooth gap-cb caffeine dnd battery gap-cb memory cpu updates layout gap-cb date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp gap-cb network-wired network-wireless gap-cb memory cpu updates gap-cb date

; --- real widgets ------------------------------------------------------------
[module/gap-cb]
type = custom/text
format = <label>
label = "  "

; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.red}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.blue}
label = "%{A1:GTK_THEME=Rice-cherryblocks gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.base}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format-background = ${colors.yellow}
format = <label>
label = "%output%%"
label-foreground = ${colors.base}

[module/pulseaudio]
type = internal/pulseaudio
format-background = ${colors.purple}
label-volume = "%percentage%%"
label-volume-foreground = ${colors.base}
label-muted = "muted"
label-muted-foreground = ${colors.base}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-background = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#282828' WIFI_OFF_FG='#FB4934' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format-background = ${colors.aqua}
format = <label>
label-foreground = ${colors.base}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format-background = ${colors.red}
label-foreground = ${colors.base}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format-background = ${colors.red}
label-foreground = ${colors.base}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format-background = ${colors.green}
format = <label>
label-foreground = ${colors.base}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format-background = ${colors.red}
format = <label>
label-foreground = ${colors.base}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
format-background = ${colors.orange}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}
label-low-foreground = ${colors.base}

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.purple}
label = "%percentage_used%%"
label-foreground = ${colors.base}

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.aqua}
label = "%percentage%%"
label-foreground = ${colors.base}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format-background = ${colors.yellow}
label-foreground = ${colors.base}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF
cat > "$CONF/polybar/themes/classic.ini" <<'EOF'
; Classic - modeled directly on github.com/kiddae/polybar-themes'
; real "classic" bar (config read from a full local clone) - genuinely
; the most minimal/monochrome theme in the whole archive: its own
; [colors] block defines only background and foreground, nothing else,
; and its bspwm module sets every workspace state (focused/occupied/
; empty) to that same plain foreground - no accent hue anywhere at all,
; confirmed by reading its real config directly rather than assumed from
; "classic2-rounded" (a different, README-undocumented folder this port
; mistakenly cited before). Ported here as fully monochrome to match -
; every widget in plain text/subtext, with only the two universal,
; disclosed exceptions every theme in this rice already applies (urgent
; must stand out; low battery must stand out). Gruvbox Dark palette (see
; "archblur" for how that was confirmed) still backs text/subtext, but no
; accent hue from it is used anywhere in this theme's own widgets.
[colors]
base     = #282828
mantle   = #1D2021
surface0 = #3C3836
surface1 = #504945
text     = #EBDBB2
subtext  = #A89984
red      = #FB4934
green    = #B8BB26
yellow   = #FABD2F
blue     = #83A598
purple   = #D3869B
aqua     = #8EC07C
orange   = #FE8019
gray     = #928374

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 28
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.text}
label-focused-underline = ${colors.text}
label-focused-overline = ${colors.text}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-classic gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "%percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#EBDBB2' WIFI_OFF_FG='#FB4934' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.subtext}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.subtext}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.subtext}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

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
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center = title

[bar/top-primary]
inherit = bar/base
modules-right = bli backlight bld sep voli pulseaudio vold sep media sep cliamp sep neti network-wired network-wireless netd sep bluetooth sep caffeine sep dnd sep battery sep memi memory memd sep cpi cpu cpd sep fsi filesystem fsd sep updates sep layout sep tray sep dti date dtd

[bar/top-secondary]
inherit = bar/base
modules-right = bli backlight bld sep voli pulseaudio vold sep media sep cliamp sep neti network-wired network-wireless netd sep memi memory memd sep cpi cpu cpd sep fsi filesystem fsd sep updates sep dti date dtd

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

[module/fsi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.orange}
label-background = ${colors.base}

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-background = ${colors.orange}
label-mounted = "%percentage_used%%"
label-mounted-foreground = ${colors.base}

[module/fsd]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.base}
label-background = ${colors.orange}

[module/title]
type = internal/xwindow
label = %title:0:40:...%
label-foreground = ${colors.purple}
label-background = ${colors.base}
label-padding = 5

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
label-focused-font = 3
label-focused-foreground = ${colors.lime}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.purple}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.purple}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.indigo}
label = "%{A1:GTK_THEME=Rice-cristina gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.green}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#E0DEF4' WIFI_OFF_FG='#EA6F91' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
radius = 8
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
modules-right = bi memory cpu filesystem bd sep bi network-wired network-wireless bd sep bluetooth sep caffeine sep dnd sep battery sep backlight sep pulseaudio sep media sep cliamp sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = bi memory cpu filesystem bd sep bi network-wired network-wireless bd sep backlight sep pulseaudio sep media sep cliamp sep updates sep date

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
label = "%{A1:GTK_THEME=Rice-cynthia gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#C5C9C5' WIFI_OFF_FG='#E46876' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #242121

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-prefix = " "
label-mounted = "%percentage_used%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
radius = 8
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
modules-right = backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu filesystem updates layout tray date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu filesystem updates date

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.blue}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.orange}
label = "%{A1:GTK_THEME=Rice-daniela gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "BRT "
format-prefix-font = 1
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#C0CAF5' WIFI_OFF_FG='#F7768E' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-prefix = "DISK "
format-mounted-prefix-font = 1
format-mounted-prefix-foreground = ${colors.orange}
label-mounted = "%percentage_used%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = bli backlight bld sep voli pulseaudio vold sep media sep cliamp
modules-center = bi i3 bd

[bar/top-primary]
inherit = bar/base
modules-right = neti network-wired network-wireless netd sep bti bluetooth btd sep cafi caffeine cafd sep dndi dnd dndd sep bati battery batd sep memi memory memd sep cpi cpu cpd sep fsi filesystem fsd sep updates sep layout sep tray sep dti date dtd

[bar/top-secondary]
inherit = bar/base
modules-right = neti network-wired network-wireless netd sep memi memory memd sep cpi cpu cpd sep fsi filesystem fsd sep updates sep dti date dtd

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

[module/fsi]
type = custom/text
format = <label>
label = ""
label-font = 2
label-foreground = ${colors.surface0}
label-background = ${colors.base}

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-background = ${colors.surface0}
format-mounted-prefix = " "
label-mounted = "%percentage_used%%"

[module/fsd]
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
label = "%{A1:GTK_THEME=Rice-emilia gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#E8DCC8' WIFI_OFF_FG='#D9736A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #2B241F

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
radius = 8
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
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

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
label = "%{A1:GTK_THEME=Rice-h4ck3r gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#00FA5C' WIFI_OFF_FG='#6DDE00' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/isabel.ini" <<'EOF'
; Isabel - deliberately understated: no chip backgrounds anywhere, no
; per-state color coding at all (focused/occupied workspaces share the
; SAME plain foreground color - only the icon SHAPE tells them apart,
; confirmed by reading the source's own [module/bspwm] block, which sets
; every state's label-*-foreground to the same ${color.fg}). One
; deliberate deviation from that source fidelity: label-urgent gets its
; own ${colors.red} foreground below rather than also sharing the plain
; default - an urgent workspace (a window demanding attention on one you
; aren't looking at) needs to actually be visually distinct from a merely
; occupied one on every theme in this rice, not just the ones that already
; happened to color-code by state.
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
; A filesystem widget and a title module (real source has both) were
; tried and reverted - tested live, the combined width pushed the bar
; past the screen edge entirely. Fitting first, not squeezing in
; widgets that don't fit.
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
radius = 8
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
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots updates dots layout dots tray dots date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots memory dots cpu dots updates dots date

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
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:GTK_THEME=Rice-isabel gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#A8C5C0' WIFI_OFF_FG='#D67F7F' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.orange}
click-left = ~/.local/bin/powermenu.sh &

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
label-focused-foreground = ${colors.magenta}
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
label = "%{A1:GTK_THEME=Rice-jan gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#27FBFE' WIFI_OFF_FG='#DB330A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.pink}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.pink}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.blue}
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
format-prefix-foreground = ${colors.magenta}
label = "%percentage%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; plain foreground; label-urgent below still gets its own red, the
; same disclosed "urgent must stand out" exception applied rice-wide).
; Modeled directly on github.com/gh0stzk/dotfiles'
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
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = " | "
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = "󱓇"
label-focused-foreground = ${colors.text}
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
label = "%{A1:GTK_THEME=Rice-karla gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#AFB1DB' WIFI_OFF_FG='#E7034A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
radius = 8
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
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

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
label = "%{A1:GTK_THEME=Rice-marisol gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#F5E6E0' WIFI_OFF_FG='#E8604C' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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
[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; (yellow focused, blue occupied/urgent in the source). One deliberate
; deviation from that source fidelity: label-urgent below gets its own
; ${colors.red} instead of sharing occupied's blue - the real gh0stzk
; config genuinely doesn't distinguish "occupied" from "needs your
; attention", but that's a real gap for this rice's purposes, not a
; stylistic choice worth preserving; every theme here needs urgent to
; actually stand out from merely-occupied. Otherwise splitting the
; difference between Isabel's fully-plain no-color treatment and the
; others' boxed ones. Modeled directly on github.com/gh0stzk/dotfiles' real "pamela"
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
pink   = #EC407A

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

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
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:GTK_THEME=Rice-pamela gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#FDFDFD' WIFI_OFF_FG='#F37F97' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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
format-prefix-foreground = ${colors.pink}
label = "%percentage%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots updates dots layout dots tray dots date dots power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots memory dots cpu dots updates dots date

[module/dots]
type = custom/text
format = <label>
label = " 󰇙 "
label-foreground = ${colors.orange}

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.text}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

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
label = "%{A1:GTK_THEME=Rice-silvia gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#EBDBB2' WIFI_OFF_FG='#CC241D' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/tobi.ini" <<'EOF'
; Tobi - modeled directly on codeberg.org/justTOBBI/dotfiles' real bspwm/
; polybar/dunst setup (confirmed by reading a full local clone), plus its
; own screenshots (assets/justtobbi-bspwm.png, workflow.png) for the
; overall look. Its own README calls the whole rice "Catppuccin", and its
; base background (#1e1e2e) is exactly Catppuccin Mocha's - but its real
; colors.ini tweaks most of the actual accents away from stock Mocha
; (fg=#d9e0ee vs Mocha's #cdd6f4, fg-alt=#6e6c7e vs #a6adc8, blue=#96cdfb
; vs #89b4fa, red=#f28fad vs #f38ba8, green=#abe9b3 vs #a6e3a1, yellow=
; #fae3b0 vs #f9e2af) - different enough from this rice's own stock
; "catppuccin-mocha" port to be worth a separate theme rather than a
; duplicate, so ported with its own real tweaked values rather than
; swapped for an unrelated palette the way this rice's "daniela" port
; (genuinely byte-identical to stock Mocha) had to be.
;
; Its real modules.ini fills the focused-workspace chip with a solid
; background (`label-focused-background = ${colors.blue-alt}`) - given a
; frame (underline+overline) instead here, same fix already applied to
; this rice's own "alireza"/"breddie" ports: a filled chip on top of the
; font reads visually heavier/larger than intended. Its rofi setup turned
; out to just import the same generic third-party "Arc Dark" theme already
; seen (and skipped for the same reason) porting this rice's "alireza"
; source - not really Tobi's own design, so this port's rofi/dunst/kitty
; all draw from Tobi's real Catppuccin-tweaked colors.ini instead, matching
; how every other tool here already shares one theme's palette.
[colors]
base     = #1E1E2E
mantle   = #181825
surface0 = #313244
text     = #D9E0EE
subtext  = #6E6C7E
blue     = #62B4F9
sky      = #96CDFB
cyan     = #89DCEB
green    = #ABE9B3
yellow   = #FAE3B0
red      = #F28FAD
pink     = #F5C2E7

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 10
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu filesystem updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu filesystem updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.blue}
label-focused-underline = ${colors.blue}
label-focused-overline = ${colors.blue}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-tobi gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.green}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#96CDFB' WIFI_OFF_FG='#F28FAD' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.pink}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.pink}
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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
label-mounted = "%percentage_used%%"
label-mounted-foreground = ${colors.blue}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

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
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=16;5"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.orange}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.orange}
click-left = ~/.local/bin/powermenu.sh &

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
label-unfocused-foreground = ${colors.grey}
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
label = "%{A1:GTK_THEME=Rice-varinka gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#F8F9FA' WIFI_OFF_FG='#DE8658' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
radius = 8
padding-left = 2
padding-right = 2
module-margin = 0
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.blue}
click-left = ~/.local/bin/powermenu.sh &

[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-padding = 2
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.blue}
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-padding = 2
label-unfocused-foreground = ${colors.indigo}
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-padding = 2
label-urgent-foreground = ${colors.red}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.cyan}
label = "%{A1:GTK_THEME=Rice-yael gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#FFFFFF' WIFI_OFF_FG='#EE5396' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF
cat > "$CONF/polybar/themes/yucklys.ini" <<'EOF'
; Yucklys - modeled directly on github.com/Yucklys/polybar-nord-theme's real
; dark-colors/nord-top/nord-down/nord-config (a full local clone read
; directly) plus its own polybar-nord.png screenshot. Real, distinguishing
; choice vs this rice's existing "nord" port: that one is built from
; nord1/nord2 surface layers + nord10 (#5e81ac) as its main accent; this
; source never touches nord10 or nord1/nord2 at all - it stays fully flat
; (no chip backgrounds anywhere except a genuine urgent-workspace/
; temperature-warning invert and the powermenu "pill"), using underline-
; only accents in nord7 (#8fbcbb, teal - focused workspace/title) and nord9
; (#81a1c1, its real dominant secondary accent) instead. Colors below are
; copied byte-for-byte from its real colors/dark-colors.
;
; Workspace switcher is genuinely unusual and kept as-is: focused shows a
; roman-numeral icon (I-X, from its real ws-icon-N config) framed by a
; teal underline; every UNFOCUSED workspace shows only a plain "*" dot in
; nord9, not its own number - confirmed real (label-unfocused = "•" in its
; actual nord-top), not a fetch artifact, unlike several icon glyphs
; elsewhere in its config that came back blank (nerd-font codepoints that
; didn't survive plain-text fetching) - those were filled in with icons
; already used elsewhere in this rice's own themes rather than guessed.
;
; Its own module set leans on several services this system doesn't run
; (mpd, an OpenWeather API key, a clash proxy, a personal onedrive client,
; clipmenu, mullvad, a private daily-poem API, and a borrowed third-party
; "nord-oneline" rofi launcher theme from lr-tech/rofi-themes-collection -
; not really Yucklys' own design, same situation already hit porting
; "alireza"'s rofi setup) - skipped rather than shipped broken or empty.
; Its real, dependency-free modules (i3, title, capslock, pulseaudio,
; network signal-ramp, cpu/memory, temperature, powermenu) are kept and
; restyled only enough to fit this rice's font/icon set; this rice's own
; usual widgets (backlight, media, cliamp, bluetooth, caffeine, dnd,
; updates, layout, tray, date) are appended alongside them rather than
; replacing anything. Powermenu keeps its real filled-pill look (solid
; nord9 background) but is rewired to this rice's own powermenu.sh
; ($mod+shift+p) instead of the source's rofi-power-menu modi, which isn\'t
; installed here.
[colors]
base     = #2E3440
mantle   = #2E3440
surface0 = #4C566A
surface1 = #4C566A
text     = #D8DEE9
subtext  = #4C566A
mauve    = #81A1C1
lavender = #B48EAD
sky      = #88C0D0
green    = #A3BE8C
teal     = #8FBCBB
yellow   = #EBCB8B
peach    = #D08770
red      = #BF616A

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 4
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3 title
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = keyboard backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu temperature updates layout tray date powermenu

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu temperature updates date

; --- real widgets, from the source's own nord-top/nord-down -----------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
enable-scroll = true
wrapping-scroll = true
ws-icon-0 = 1;I
ws-icon-1 = 2;II
ws-icon-2 = 3;III
ws-icon-3 = 4;IV
ws-icon-4 = 5;V
ws-icon-5 = 6;VI
ws-icon-6 = 7;VII
ws-icon-7 = 8;VIII
ws-icon-8 = 9;IX
ws-icon-9 = 10;X
label-focused = %icon%
label-focused-font = 3
label-focused-foreground = ${colors.teal}
label-focused-underline = ${colors.teal}
label-focused-padding = 2
label-unfocused = *
label-unfocused-font = 3
label-unfocused-foreground = ${colors.mauve}
label-unfocused-padding = 2
label-urgent = %icon%
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/title]
type = internal/xwindow
format = <label>
format-underline = ${colors.teal}
label = %title%
label-maxlen = 20
label-empty = Desktop
label-padding = 2

[module/keyboard]
type = internal/xkeyboard
blacklist-0 = num lock
blacklist-1 = scroll lock
format = <label-indicator>
label-indicator-on = " CL"
label-indicator-on-foreground = ${colors.peach}
format-underline = ${colors.peach}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
format-volume-underline = ${colors.lavender}
label-volume = "  %percentage%%"
label-volume-foreground = ${colors.green}
label-muted = " muted"
label-muted-foreground = ${colors.red}

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:} %ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

; Real 4-level signal-strength ramp from the source (urgent/notify/nord7/
; success by strength) - its actual distinguishing touch vs every other
; theme's plain-text network module here.
[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#D8DEE9' WIFI_OFF_FG='#BF616A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/cpu]
type = internal/cpu
interval = 2
format = <label>
label = "  %percentage%%"
label-foreground = ${colors.green}

[module/memory]
type = internal/memory
interval = 2
format = <label>
label = "  %percentage_used%%"
label-foreground = ${colors.yellow}

[module/temperature]
type = internal/temperature
thermal-zone = 0
base-temperature = 20
warn-temperature = 70
format = <ramp><label>
format-warn = <label-warn>
format-warn-background = ${colors.text}
label = " %temperature-c%"
label-warn = " %temperature-c%"
label-warn-foreground = ${colors.red}
ramp-0 =
ramp-0-foreground = ${colors.sky}
ramp-1 =
ramp-1-foreground = ${colors.green}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "  %output%%"
label-foreground = ${colors.mauve}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>
label-foreground = ${colors.green}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>
label-foreground = ${colors.green}

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging = <label-charging>
format-charging-underline = ${colors.text}
label-charging = "  %percentage%%"
label-charging-foreground = ${colors.text}
format-discharging = <label-discharging>
format-discharging-underline = ${colors.yellow}
label-discharging = "  %percentage%%"
label-discharging-foreground = ${colors.text}
label-full = " Full"
label-full-foreground = ${colors.green}
format-full-underline = ${colors.green}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>
label-foreground = ${colors.yellow}

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %a
format = <label>
label = "%{A1:GTK_THEME=Rice-yucklys gnome-calendar &:} %date%%{A}"
label-foreground = ${colors.text}
label-underline = ${colors.sky}

; Real filled "pill" - the source's own distinctive treatment for its
; powermenu icon (solid nord9 background, base-color text) rather than an
; underline like everything else here.
[module/powermenu]
type = custom/text
format = <label>
label = " ⏻ "
label-background = ${colors.mauve}
label-foreground = ${colors.base}
click-left = ~/.local/bin/powermenu.sh &

[settings]
screenchange-reload = true
EOF
cat > "$CONF/polybar/themes/yucklys-light.ini" <<'EOF'
; Yucklys Light - the source's own light/dark PAIR (github.com/Yucklys/
; polybar-nord-theme's real colors/light-colors + bars/light-config, a full
; local clone read directly): same module set and layout as this rice's
; "yucklys" (dark), background/text/muted swap to the source's real light
; values (base=nord6 #eceff4, text=nord0 #2e3440, muted=nord1 #3b4252 -
; copied byte-for-byte), while every Frost/Aurora accent hue (teal/sky/
; mauve/green/yellow/peach/red/lavender) stays the exact same real hex the
; dark theme uses - that part of the source's own light-colors file is
; identical to dark-colors, confirmed by diffing them directly.
;
; Those accent hexes are genuinely unreadable as TEXT on this bright a
; background though - computed contrast against #eceff4 (WCAG relative
; luminance, not eyeballed): teal 1.81:1, sky 1.74:1, mauve 2.34:1, yellow
; 1.35:1 - all well under even the lenient 3:1 floor for icon-sized text,
; the same class of bug this rice's own README already documents fixing
; on "aline" and "nord" (unreadable accents on a light chip/dark surface
; kept for luminance reasons). Each accent below gets a same-hue, darkened
; "text-safe" value (>=4.5:1 against #eceff4) for use as underline/label
; text; the ORIGINAL vivid value is kept under -bg for anything used as a
; filled chip instead (urgent workspace, powermenu pill, temperature-warn),
; where the vivid tone is the chip color and a separately-chosen readable
; foreground goes on top of it - not a fabricated palette, the same real
; hues just split into two roles the way this rice's own "nord" theme
; already splits red/red-light for the same reason.
[colors]
base     = #ECEFF4
mantle   = #ECEFF4
surface0 = #3B4252
surface1 = #3B4252
text     = #2E3440
subtext  = #3B4252
mauve    = #496F95
mauve-bg = #81A1C1
lavender = #8C5D83
sky      = #357587
green    = #597442
teal     = #457473
yellow   = #8D6618
peach    = #AA5338
red      = #B54954
red-bg   = #BF616A

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 4
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3 title
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = keyboard backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu temperature updates layout tray date powermenu

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu temperature updates date

; --- real widgets, from the source's own nord-top/nord-down -----------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
enable-scroll = true
wrapping-scroll = true
ws-icon-0 = 1;I
ws-icon-1 = 2;II
ws-icon-2 = 3;III
ws-icon-3 = 4;IV
ws-icon-4 = 5;V
ws-icon-5 = 6;VI
ws-icon-6 = 7;VII
ws-icon-7 = 8;VIII
ws-icon-8 = 9;IX
ws-icon-9 = 10;X
label-focused = %icon%
label-focused-font = 3
label-focused-foreground = ${colors.teal}
label-focused-underline = ${colors.teal}
label-focused-padding = 2
label-unfocused = *
label-unfocused-font = 3
label-unfocused-foreground = ${colors.mauve}
label-unfocused-padding = 2
label-urgent = %icon%
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red-bg}
label-urgent-padding = 2

[module/title]
type = internal/xwindow
format = <label>
format-underline = ${colors.teal}
label = %title%
label-maxlen = 20
label-empty = Desktop
label-padding = 2

[module/keyboard]
type = internal/xkeyboard
blacklist-0 = num lock
blacklist-1 = scroll lock
format = <label-indicator>
label-indicator-on = " CL"
label-indicator-on-foreground = ${colors.peach}
format-underline = ${colors.peach}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
format-volume-underline = ${colors.lavender}
label-volume = "  %percentage%%"
label-volume-foreground = ${colors.green}
label-muted = " muted"
label-muted-foreground = ${colors.red}

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:} %ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#2E3440' WIFI_OFF_FG='#B54954' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/cpu]
type = internal/cpu
interval = 2
format = <label>
label = "  %percentage%%"
label-foreground = ${colors.green}

[module/memory]
type = internal/memory
interval = 2
format = <label>
label = "  %percentage_used%%"
label-foreground = ${colors.yellow}

[module/temperature]
type = internal/temperature
thermal-zone = 0
base-temperature = 20
warn-temperature = 70
format = <ramp><label>
format-warn = <label-warn>
format-warn-background = ${colors.text}
label = " %temperature-c%"
label-warn = " %temperature-c%"
label-warn-foreground = ${colors.red-bg}
ramp-0 =
ramp-0-foreground = ${colors.sky}
ramp-1 =
ramp-1-foreground = ${colors.green}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "  %output%%"
label-foreground = ${colors.mauve}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>
label-foreground = ${colors.green}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>
label-foreground = ${colors.green}

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging = <label-charging>
format-charging-underline = ${colors.text}
label-charging = "  %percentage%%"
label-charging-foreground = ${colors.text}
format-discharging = <label-discharging>
format-discharging-underline = ${colors.yellow}
label-discharging = "  %percentage%%"
label-discharging-foreground = ${colors.text}
label-full = " Full"
label-full-foreground = ${colors.green}
format-full-underline = ${colors.green}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>
label-foreground = ${colors.yellow}

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

; Dedicated dark backdrop for the tray specifically - most tray icons
; (Discord, 1Password, etc.) are drawn in white/light colors expecting a
; dark bar, and would otherwise inherit this theme's own light base and
; effectively disappear (same real bug already fixed on this rice's own
; "aline"/"brenda" themes). Reuses surface0 (nord1, the theme's one real
; dark tone) rather than a fabricated new color.
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %a
format = <label>
label = "%{A1:GTK_THEME=Rice-yucklys-light gnome-calendar &:} %date%%{A}"
label-foreground = ${colors.text}
label-underline = ${colors.sky}

; Real filled "pill" - the source's own distinctive treatment for its
; powermenu icon. Chip stays the original vivid nord9, text goes on
; subtext (dark) instead of base (light-on-light would be unreadable
; against this mid-tone chip - checked: 2.34:1 vs 3.74:1).
[module/powermenu]
type = custom/text
format = <label>
label = " ⏻ "
label-background = ${colors.mauve-bg}
label-foreground = ${colors.subtext}
click-left = ~/.local/bin/powermenu.sh &

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
surface0 = #151720
surface1 = #1C1E27
text   = #A5B6CF
subtext = #6E8DB4
focus  = #8EA6C4
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
radius = 8
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
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

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
label-focused-font = 3
label-focused-foreground = ${colors.focus}
label-focused-padding = 2
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent = ${self.ws-label}
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
format-prefix-foreground = ${colors.blue}
label = "%{A1:GTK_THEME=Rice-z0mbi3 gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %output%% "

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#A5B6CF' WIFI_OFF_FG='#DD6777' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #151720

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
teal = #9CCFD8
; Dedicated dark, fully-opaque backdrop for the system tray specifically -
; most tray icons (Discord, 1Password, etc.) are drawn in white/light
; colors expecting a dark bar and become invisible against this theme's
; own light cream chips (caught via direct feedback, not assumed).
tray-bg = #3D3757
green = #286983
yellow = #EA9D34
red = #B4637A
blue = #56949F

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
modules-right = backlight pulseaudio media sep cliamp sep network-wired network-wireless sep bluetooth caffeine dnd sep battery memory cpu filesystem updates sep layout sep tray

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media sep cliamp sep network-wired network-wireless sep memory cpu filesystem updates

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
ws-icon-0 = 1;%{F#76aaff}󰬺%{F-}
ws-icon-1 = 2;%{F#ad78cf}󰬻%{F-}
ws-icon-2 = 3;%{F#70d7c5}󰬼%{F-}
ws-icon-3 = 4;%{F#f09e6c}󰬽%{F-}
ws-icon-4 = 5;%{F#f46bc9}󰬾%{F-}
ws-icon-5 = 6;%{F#ef658c}󰬿%{F-}
ws-icon-6 = 7;%{F#76aaff}󰭀%{F-}
ws-icon-7 = 8;%{F#ad78cf}󰭁%{F-}
ws-icon-8 = 9;%{F#70d7c5}󰭂%{F-}
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
label = "%{A1:GTK_THEME=Rice-aline gnome-calendar &:}%date%  %time%%{A}"
label-font = 3

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %output%% "

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#575279' WIFI_OFF_FG='#B4637A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #F2E9E1

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-background = ${colors.surface0}
format-mounted-prefix = " "
format-mounted-prefix-foreground = ${colors.text}
label-mounted = " %percentage_used%% "

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.tray-bg}
format-background = ${colors.tray-bg}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/alireza-square.ini" <<'EOF'
; Alireza - modeled directly on codeberg.org/alirezaalavi/dotfiles' real i3
; setup, corrected against its own screenshots (screenshots/i3_dracula_2025-
; {1,2,3}.png) after an earlier config-only pass missed the actual look:
; that i3bar/i3status-rust bar renders almost everything in plain WHITE
; text (icons.icons="awesome6" gives small monochrome glyphs, not per-
; module colored ones) on a bar that's visibly near-black - noticeably
; darker than the #282a36 window/terminal background seen in the same
; screenshots (nvim, the file manager, the terminal), not the same shade -
; ported here as a distinct "mantle" (bar-only) vs "base" (everything
; else) split, unlike most other themes in this set which keep the two
; identical. Color is reserved for the workspace indicator (their own
; colorscheme.conf: focused/urgent both FILL border+background with
; accent, not just text) and for in-app selection highlights, which the
; screenshots show as PINK far more often than the purple their i3
; colorscheme.conf uses for window borders (the file manager's selected
; row, the terminal music player's selected track, and the cava-style
; volume bars are all pink) - ported as this theme's dominant in-app
; accent, with purple kept specifically for the window-border/workspace-
; chip role their colorscheme.conf actually specifies. Two of their own
; deviations from stock Dracula carry over unchanged from the first pass:
; a brighter red (#FF5E76, used consistently in both their i3 colorscheme
; and their sway waybar CSS - not a one-off) instead of stock #ff5555, and
; a second lighter purple ("purple_dark1", #938BFF, named "lavender" here)
; for inactive workspace text.
[colors]
base     = #282A36
mantle   = #191A21
surface0 = #44475A
text     = #F8F8F2
subtext  = #6272A4
purple   = #BD93F9
lavender = #938BFF
red      = #FF5E76
green    = #50FA7B
orange   = #FFB86C
pink     = #FF79C6
yellow   = #F1FA8C
cyan     = #8BE9FD

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.mantle}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
underline-size = 2
overline-size = 2
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Plain white text throughout, matching the source's actual near-monochrome
; bar (its own real accents show up on window borders and in-app selections,
; not here) - only the workspace chip and low-battery/muted-volume states
; get real color, same restraint the source's own bar shows.
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
; Focused gets a frame (underline+overline), not a solid fill - a filled
; chip on top of the font read visually heavier/larger than intended.
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.purple}
label-focused-underline = ${colors.purple}
label-focused-overline = ${colors.purple}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.lavender}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-alireza gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "%percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#F8F8F2' WIFI_OFF_FG='#FF5E76' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.pink}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.pink}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

; Only the "low" state (under low-at%, not charging) actually gets colored -
; one of the only places the source's otherwise monochrome bar shows real
; color at all.
[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/archblur-square.ini" <<'EOF'
; Archblur - modeled directly on github.com/kiddae/polybar-themes'
; "arch-blur" bar (confirmed by reading a full local clone). That whole
; archive's configs pull every color from the user's own ~/.Xresources via
; xrdb, with only bare black/white as fallbacks - no fixed palette is
; actually checked in for any of its themes. Its bspwmrc, though, sources
; "$HOME/.colors/gruvbox/gruvbox.sh" for its actual real desktop colors
; (confirmed live in the source archive's own "tiny" folder screenshot,
; showing that exact
; source line) - real, published Gruvbox Dark values used here for every
; theme drawn from this archive, differing between them by structure
; (height/radius/spacing/accent role) rather than a from-scratch palette
; each time, the same way the archive's own bar variants were always
; meant to share one desktop colorscheme.
[colors]
base     = #282828
mantle   = #1D2021
surface0 = #3C3836
surface1 = #504945
text     = #EBDBB2
subtext  = #A89984
red      = #FB4934
green    = #B8BB26
yellow   = #FABD2F
blue     = #83A598
purple   = #D3869B
aqua     = #8EC07C
orange   = #FE8019
gray     = #928374

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 32
background = ${colors.base}
foreground = ${colors.text}
bottom = true
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = launcher i3
modules-center = media

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.orange}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.orange}
label-focused-underline = ${colors.orange}
label-focused-overline = ${colors.orange}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-archblur gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "%percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#EBDBB2' WIFI_OFF_FG='#FB4934' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.orange}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.orange}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

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
modules-right = backlight dot pulseaudio dot media dot cliamp dot network-wired network-wireless dot bluetooth dot caffeine dot dnd dot battery dot memory dot cpu dot updates dot layout dot date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dot pulseaudio dot media dot cliamp dot network-wired network-wireless dot memory dot cpu dot updates dot date-icon date

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
label = "%{A1:GTK_THEME=Rice-archcraft gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.peach}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.surface0}
label = "%{A1:GTK_THEME=Rice-archcraft gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = " 󰃟 %output%% "
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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='  ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#56b6c2' WIFI_OFF_FG='#e06c75' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
format-background = ${colors.surface0}
tray-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/breddie-square.ini" <<'EOF'
; Breddie - modeled directly on codeberg.org/breddiesucks/dotfiles' real
; polybar/rofi/dunst/alacritty configs and its actual XMonad window-border
; colors (xmonad/xmonad.hs: myFocusedBorderColor "#acb0d0", myNormalBorder-
; Color "#444b61" - confirmed by reading a full local clone), plus its own
; screenshots (.showoff/01.png, 02.png) for the overall look: a near-black
; TokyoNight-family background (#1a1b26, its alacritty.toml's own primary
; background - the same well-known open palette this rice's own "daniela"
; theme already called "Tokyo-Night-ADJACENT" rather than exact; this port
; uses the source's real hex values directly) with an almost monochrome
; bar - workspace numbers and stats all in one muted light color, no
; per-module color-coding - color reserved for the focused-workspace
; accent and alert states, the same restraint this rice's own "isabel"/
; "alireza" ports already follow for similarly minimal sources.
;
; Two real bugs in the source were not carried over, same policy already
; applied to this rice's own "isabel"/"pamela" ports: its polybar
; [colors] "alert" is a literal typo (`#D9EBCB8R` - R isn't a hex digit),
; clearly meant to be its alacritty yellow (`#ebcb8c`) - used here as
; intended. Its xworkspaces "active" state sets a background-alt that's
; IDENTICAL to the bar's own background (`background-alt = background`),
; making the focused-workspace indicator invisible in practice - given a
; real underline+overline frame instead (this rice's own "alireza" fix for
; the same class of problem), using the real accent its xmonad.hs actually
; assigns to focused windows (`#acb0d0`) rather than an invisible chip.
[colors]
base     = #1A1B26
mantle   = #1A1B26
surface0 = #292A44
text     = #E5E9F0
subtext  = #444B61
lavender = #ACB0D0
blue     = #7AA2F7
cyan     = #0DB9D7
green    = #9ECE6A
yellow   = #EBCB8C
orange   = #FF9E64
red      = #F7768E
purple   = #BB9AF7

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
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.lavender}
label-focused-underline = ${colors.lavender}
label-focused-overline = ${colors.lavender}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.yellow}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-breddie gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "VOL %percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "MUTED"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#E5E9F0' WIFI_OFF_FG='#F7768E' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.purple}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.purple}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

; Only the "low" state (under low-at%, not charging) actually gets colored -
; matching the near-monochrome restraint the source's own bar shows.
[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
; A filesystem widget (real source has one) was tried and reverted -
; tested live, its extra icon+value box pushed the whole cluster past
; the bar's own right edge, spilling half outside the rounded corner.
; Fitting first, not squeezing in a widget that doesn't fit.
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
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep cliamp sep network-icon network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery-icon battery sep memory-icon memory sep cpu-icon cpu sep updates sep layout sep tray sep date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight-icon backlight sep pulseaudio-icon pulseaudio sep media sep cliamp sep network-icon network-wired network-wireless sep memory-icon memory sep cpu-icon cpu sep updates sep date-icon date

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
label = "%{A1:GTK_THEME=Rice-brenda gnome-calendar &:} %date%  %time% %{A}"
label-foreground = ${colors.base}

[module/backlight-icon]
type = custom/text
format = <label>
format-background = ${colors.yellow}
label = " 󰃟 "
label-foreground = ${colors.base}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
label = " %output%% "
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
exec = ~/.local/bin/polybar-media-boxed.sh
interval = 1
click-left = playerctl previous &
click-middle = playerctl play-pause &
click-right = playerctl next &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}
label-padding = 1

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-background = ${colors.surface0}
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#2D353B' WIFI_OFF_FG='#E67E80' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #F8F5E4

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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
[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>
format-background = ${colors.surface0}
label-foreground = ${colors.base}
label-padding = 1

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-right = tray-cap tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date-icon date

[bar/top-secondary]
inherit = bar/base
; same as top-primary minus tray/battery - without this split every extra
; monitor showed a permanently empty tray slot since only one instance can
; ever win the X11 tray selection.
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu updates date-icon date

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
label = "%{A1:GTK_THEME=Rice-catppuccin-mocha gnome-calendar &:}    %{A}"
label-font = 1
label-foreground = ${colors.base}
format-background = ${colors.lavender}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-catppuccin-mocha gnome-calendar &:}  %date%  %time%  %{A}"
label-font = 3
label-foreground = ${colors.base}
format-background = ${colors.lavender}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "  󰃟 %output%% "
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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.base}
format-background = ${colors.teal}
format = <label>

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.base}
format-background = ${colors.yellow}
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
type = custom/script
exec = WIFI_PREFIX='   ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#1e1e2e' WIFI_OFF_FG='#f38ba8' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #89b4fa

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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

cat > "$CONF/polybar/themes/cherryblocks-square.ini" <<'EOF'
; Cherryblocks - modeled directly on github.com/kiddae/polybar-themes'
; real "cherryblocks" bar (config read from a full local clone). Its
; defining, name-giving trait is SOLID FILLED CHIPS: every widget renders
; as `format-background = <accent>` with inverted (base-colored) text,
; not a shared group background or an underline - confirmed directly in
; its own config (`format-background = ${color.color1}`, `format-
; foreground = ${color.background}` on the workspace/mpd/time modules).
; The real source also splits this into three separate floating bars
; (workspace, music, tray) with true gaps of desktop between them - this
; rice's shared polybar-launch.sh only ever launches one bar per monitor,
; so that part is approximated with real gap modules between clusters
; inside a single bar instead (the chip look itself, its main visual
; identity, is not approximated - it's the real thing). Gruvbox Dark
; palette (see "archblur" for how that was confirmed).
[colors]
base     = #282828
mantle   = #1D2021
surface0 = #3C3836
surface1 = #504945
text     = #EBDBB2
subtext  = #A89984
red      = #FB4934
green    = #B8BB26
yellow   = #FABD2F
blue     = #83A598
purple   = #D3869B
aqua     = #8EC07C
orange   = #FE8019
gray     = #928374

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 30
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 3
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray gap-cb backlight pulseaudio media cliamp gap-cb network-wired network-wireless bluetooth gap-cb caffeine dnd battery gap-cb memory cpu updates layout gap-cb date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp gap-cb network-wired network-wireless gap-cb memory cpu updates gap-cb date

; --- real widgets ------------------------------------------------------------
[module/gap-cb]
type = custom/text
format = <label>
label = "  "

; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.red}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-background = ${colors.blue}
label = "%{A1:GTK_THEME=Rice-cherryblocks gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.base}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format-background = ${colors.yellow}
format = <label>
label = "%output%%"
label-foreground = ${colors.base}

[module/pulseaudio]
type = internal/pulseaudio
format-background = ${colors.purple}
label-volume = "%percentage%%"
label-volume-foreground = ${colors.base}
label-muted = "muted"
label-muted-foreground = ${colors.base}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-background = ${colors.green}
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.base}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#282828' WIFI_OFF_FG='#FB4934' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format-background = ${colors.aqua}
format = <label>
label-foreground = ${colors.base}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format-background = ${colors.red}
label-foreground = ${colors.base}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format-background = ${colors.red}
label-foreground = ${colors.base}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format-background = ${colors.green}
format = <label>
label-foreground = ${colors.base}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format-background = ${colors.red}
format = <label>
label-foreground = ${colors.base}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
format-background = ${colors.orange}
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.base}
label-discharging-foreground = ${colors.base}
label-full-foreground = ${colors.base}
label-low-foreground = ${colors.base}

[module/memory]
type = internal/memory
interval = 2
format-background = ${colors.purple}
label = "%percentage_used%%"
label-foreground = ${colors.base}

[module/cpu]
type = internal/cpu
interval = 2
format-background = ${colors.aqua}
label = "%percentage%%"
label-foreground = ${colors.base}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format-background = ${colors.yellow}
label-foreground = ${colors.base}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[settings]
screenchange-reload = true
EOF
cat > "$CONF/polybar/themes/classic-square.ini" <<'EOF'
; Classic - modeled directly on github.com/kiddae/polybar-themes'
; real "classic" bar (config read from a full local clone) - genuinely
; the most minimal/monochrome theme in the whole archive: its own
; [colors] block defines only background and foreground, nothing else,
; and its bspwm module sets every workspace state (focused/occupied/
; empty) to that same plain foreground - no accent hue anywhere at all,
; confirmed by reading its real config directly rather than assumed from
; "classic2-rounded" (a different, README-undocumented folder this port
; mistakenly cited before). Ported here as fully monochrome to match -
; every widget in plain text/subtext, with only the two universal,
; disclosed exceptions every theme in this rice already applies (urgent
; must stand out; low battery must stand out). Gruvbox Dark palette (see
; "archblur" for how that was confirmed) still backs text/subtext, but no
; accent hue from it is used anywhere in this theme's own widgets.
[colors]
base     = #282828
mantle   = #1D2021
surface0 = #3C3836
surface1 = #504945
text     = #EBDBB2
subtext  = #A89984
red      = #FB4934
green    = #B8BB26
yellow   = #FABD2F
blue     = #83A598
purple   = #D3869B
aqua     = #8EC07C
orange   = #FE8019
gray     = #928374

[bar/base]
monitor = ${env:MONITOR:}
width = 100%
height = 28
background = ${colors.base}
foreground = ${colors.text}
radius = 0
padding-left = 2
padding-right = 2
module-margin = 1
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.text}
label-focused-underline = ${colors.text}
label-focused-overline = ${colors.text}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-classic gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "%output%%"
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "%percentage%%"
label-volume-foreground = ${colors.text}
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.text}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#EBDBB2' WIFI_OFF_FG='#FB4934' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.text}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.subtext}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.subtext}
format = <label>

[module/caffeine]
type = custom/script
exec = ~/.local/bin/polybar-caffeine.sh
interval = 3
click-left = ~/.local/bin/caffeine-toggle.sh &
click-right = xset s activate &
format = <label>
label-foreground = ${colors.text}

[module/dnd]
type = custom/script
exec = ~/.local/bin/polybar-dnd.sh
interval = 2
click-left = ~/.local/bin/dnd-toggle.sh &
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.text}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.subtext}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

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
modules-center = title

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep filesystem sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep filesystem sep updates sep date

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
label-focused-font = 3
label-focused-foreground = ${colors.lime}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.purple}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.purple}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.indigo}
label = "%{A1:GTK_THEME=Rice-cristina gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.green}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#E0DEF4' WIFI_OFF_FG='#EA6F91' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-prefix = " "
format-mounted-prefix-foreground = ${colors.orange}
label-mounted = "%percentage_used%%"

[module/title]
type = internal/xwindow
label = %title:0:40:...%
label-foreground = ${colors.purple}
label-padding = 5

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
modules-right = memory cpu filesystem sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep backlight sep pulseaudio sep media sep cliamp sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = memory cpu filesystem sep network-wired network-wireless sep backlight sep pulseaudio sep media sep cliamp sep updates sep date

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
label = "%{A1:GTK_THEME=Rice-cynthia gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#C5C9C5' WIFI_OFF_FG='#E46876' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #242121

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-prefix = " "
label-mounted = "%percentage_used%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
modules-right = backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu filesystem updates layout tray date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu filesystem updates date

; --- real widgets ------------------------------------------------------------
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.blue}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.orange}
label = "%{A1:GTK_THEME=Rice-daniela gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "BRT "
format-prefix-font = 1
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#C0CAF5' WIFI_OFF_FG='#F7768E' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-prefix = "DISK "
format-mounted-prefix-font = 1
format-mounted-prefix-foreground = ${colors.orange}
label-mounted = "%percentage_used%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-right = tray sep-plain backlight sep-plain pulseaudio sep-plain media sep-plain cliamp sep-plain network-wired network-wireless sep-plain bluetooth sep-plain caffeine sep-plain dnd sep-plain battery sep-plain memory sep-plain cpu sep-plain updates sep-plain layout sep-plain date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep-plain pulseaudio sep-plain media sep-plain cliamp sep-plain network-wired network-wireless sep-plain memory sep-plain cpu sep-plain updates sep-plain date-icon date

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
label = "%{A1:GTK_THEME=Rice-dracula gnome-calendar &:}  %{A}"
label-font = 1
label-foreground = ${colors.mauve}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-dracula gnome-calendar &:}%date%  %time%%{A}"
label-font = 3
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = " 󰃟 %output%%"
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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='  ' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#8be9fd' WIFI_OFF_FG='#ff5555' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
modules-left = backlight sep pulseaudio sep media sep cliamp
modules-center = i3

[bar/top-primary]
inherit = bar/base
modules-right = network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep filesystem sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = network-wired network-wireless sep memory sep cpu sep filesystem sep updates sep date

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
label = "%{A1:GTK_THEME=Rice-emilia gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#E8DCC8' WIFI_OFF_FG='#D9736A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #2B241F

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
format-mounted-background = ${colors.surface0}
format-mounted-prefix = " "
label-mounted = "%percentage_used%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; Label-urgent below deliberately breaks from the source's real same-
; as-occupied urgent color - an urgent workspace (demanding attention on
; one you aren't looking at) should actually stand out, the same disclosed
; rice-wide exception already applied on this rice's own Isabel/Karla.
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
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

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
label = "%{A1:GTK_THEME=Rice-h4ck3r gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#00FA5C' WIFI_OFF_FG='#6DDE00' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/isabel-square.ini" <<'EOF'
; Isabel - deliberately understated: no chip backgrounds anywhere, no
; per-state color coding at all (focused/occupied workspaces share the
; SAME plain foreground color - only the icon SHAPE tells them apart,
; confirmed by reading the source's own [module/bspwm] block, which sets
; every state's label-*-foreground to the same ${color.fg}). One
; deliberate deviation from that source fidelity: label-urgent gets its
; own ${colors.red} foreground below rather than also sharing the plain
; default - an urgent workspace (a window demanding attention on one you
; aren't looking at) needs to actually be visually distinct from a merely
; occupied one on every theme in this rice, not just the ones that already
; happened to color-code by state.
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
; A filesystem widget and a title module (real source has both) were
; tried and reverted - tested live, the combined width pushed the bar
; past the screen edge entirely. Fitting first, not squeezing in
; widgets that don't fit.
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
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots updates dots layout dots tray dots date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots memory dots cpu dots updates dots date

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
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:GTK_THEME=Rice-isabel gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#A8C5C0' WIFI_OFF_FG='#D67F7F' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.orange}
click-left = ~/.local/bin/powermenu.sh &

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
label-focused-foreground = ${colors.magenta}
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
label = "%{A1:GTK_THEME=Rice-jan gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#27FBFE' WIFI_OFF_FG='#DB330A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.pink}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging-prefix = " "
format-charging-prefix-foreground = ${colors.pink}
format-discharging-prefix = " "
format-discharging-prefix-foreground = ${colors.blue}
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
format-prefix-foreground = ${colors.magenta}
label = "%percentage%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; plain foreground; label-urgent below still gets its own red, the
; same disclosed "urgent must stand out" exception applied rice-wide).
; Modeled directly on github.com/gh0stzk/dotfiles'
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
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = " | "
label-foreground = ${colors.subtext}

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

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
label = "%{A1:GTK_THEME=Rice-karla gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#AFB1DB' WIFI_OFF_FG='#E7034A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

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
label = "%{A1:GTK_THEME=Rice-marisol gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#F5E6E0' WIFI_OFF_FG='#E8604C' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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
[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-right = backlight pulseaudio media cliamp network-wired network-wireless bluetooth gap-nord caffeine dnd battery gap-nord memory cpu updates gap-nord layout gap-nord tray gap-nord date-icon date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless gap-nord memory cpu updates gap-nord date-icon date

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
label = "%{A1:GTK_THEME=Rice-nord gnome-calendar &:} 󰃰 %{A}"
label-font = 1
label-foreground = ${colors.lavender}
format-background = ${colors.surface0}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-nord gnome-calendar &:}%date%  %time% %{A}"
label-font = 3
label-foreground = ${colors.text}
format-background = ${colors.surface0}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = " 󰃟 %output%% "
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
format-background = ${colors.surface0}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.green}
format = <label>
format-background = ${colors.surface0}

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}  %ifname% %{A}"
label-connected-foreground = ${colors.sky}
format-connected-background = ${colors.surface0}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='  ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#88c0d0' WIFI_OFF_FG='#bf616a' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #3b4252

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>
format-background = ${colors.surface0}

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
; (yellow focused, blue occupied/urgent in the source). One deliberate
; deviation from that source fidelity: label-urgent below gets its own
; ${colors.red} instead of sharing occupied's blue - the real gh0stzk
; config genuinely doesn't distinguish "occupied" from "needs your
; attention", but that's a real gap for this rice's purposes, not a
; stylistic choice worth preserving; every theme here needs urgent to
; actually stand out from merely-occupied. Otherwise splitting the
; difference between Isabel's fully-plain no-color treatment and the
; others' boxed ones. Modeled directly on github.com/gh0stzk/dotfiles' real "pamela"
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
pink   = #EC407A

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
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

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
label-urgent-foreground = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
label = "%{A1:GTK_THEME=Rice-pamela gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#FDFDFD' WIFI_OFF_FG='#F37F97' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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
format-prefix-foreground = ${colors.pink}
label = "%percentage%%"

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots bluetooth dots caffeine dots dnd dots battery dots memory dots cpu dots updates dots layout dots tray dots date dots power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight dots pulseaudio dots media dots cliamp dots network-wired network-wireless dots memory dots cpu dots updates dots date

[module/dots]
type = custom/text
format = <label>
label = " 󰇙 "
label-foreground = ${colors.orange}

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.text}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu.sh &

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
label = "%{A1:GTK_THEME=Rice-silvia gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#EBDBB2' WIFI_OFF_FG='#CC241D' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF

cat > "$CONF/polybar/themes/tobi-square.ini" <<'EOF'
; Tobi - modeled directly on codeberg.org/justTOBBI/dotfiles' real bspwm/
; polybar/dunst setup (confirmed by reading a full local clone), plus its
; own screenshots (assets/justtobbi-bspwm.png, workflow.png) for the
; overall look. Its own README calls the whole rice "Catppuccin", and its
; base background (#1e1e2e) is exactly Catppuccin Mocha's - but its real
; colors.ini tweaks most of the actual accents away from stock Mocha
; (fg=#d9e0ee vs Mocha's #cdd6f4, fg-alt=#6e6c7e vs #a6adc8, blue=#96cdfb
; vs #89b4fa, red=#f28fad vs #f38ba8, green=#abe9b3 vs #a6e3a1, yellow=
; #fae3b0 vs #f9e2af) - different enough from this rice's own stock
; "catppuccin-mocha" port to be worth a separate theme rather than a
; duplicate, so ported with its own real tweaked values rather than
; swapped for an unrelated palette the way this rice's "daniela" port
; (genuinely byte-identical to stock Mocha) had to be.
;
; Its real modules.ini fills the focused-workspace chip with a solid
; background (`label-focused-background = ${colors.blue-alt}`) - given a
; frame (underline+overline) instead here, same fix already applied to
; this rice's own "alireza"/"breddie" ports: a filled chip on top of the
; font reads visually heavier/larger than intended. Its rofi setup turned
; out to just import the same generic third-party "Arc Dark" theme already
; seen (and skipped for the same reason) porting this rice's "alireza"
; source - not really Tobi's own design, so this port's rofi/dunst/kitty
; all draw from Tobi's real Catppuccin-tweaked colors.ini instead, matching
; how every other tool here already shares one theme's palette.
[colors]
base     = #1E1E2E
mantle   = #181825
surface0 = #313244
text     = #D9E0EE
subtext  = #6E6C7E
blue     = #62B4F9
sky      = #96CDFB
cyan     = #89DCEB
green    = #ABE9B3
yellow   = #FAE3B0
red      = #F28FAD
pink     = #F5C2E7

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
underline-size = 2
overline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = tray backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu filesystem updates layout date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu filesystem updates date

; --- real widgets ------------------------------------------------------------
; Frame (underline+overline), not a solid fill, for focused - a filled chip
; on top of the font reads visually heavier/larger than intended (confirmed
; the hard way porting this rice's own "alireza" theme).
[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-foreground = ${colors.blue}
label-focused-underline = ${colors.blue}
label-focused-overline = ${colors.blue}
label-focused-padding = 1
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 1
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
label = "%{A1:GTK_THEME=Rice-tobi gnome-calendar &:}%date%  %time%%{A}"
label-foreground = ${colors.text}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

[module/pulseaudio]
type = internal/pulseaudio
format-volume-prefix = " "
format-volume-prefix-foreground = ${colors.green}
label-volume = "%percentage%%"
label-muted = "muted"
label-muted-foreground = ${colors.subtext}

; Split wired/wireless so whichever is actually up is the only one that
; renders anything - format-disconnected is left blank so the inactive one
; takes up no space instead of showing a permanent "offline" label.
[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#96CDFB' WIFI_OFF_FG='#F28FAD' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/bluetooth]
type = custom/script
exec = ~/.local/bin/polybar-bluetooth.sh
interval = 5
click-left = blueman-manager &
format = <label>
label-foreground = ${colors.cyan}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
label-foreground = ${colors.pink}
format = <label>

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
label-foreground = ${colors.pink}
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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
low-at = 15
label-charging = "%percentage%%"
label-discharging = "%percentage%%"
label-full = "Full"
label-low = "%percentage%%"
label-charging-foreground = ${colors.text}
label-discharging-foreground = ${colors.text}
label-full-foreground = ${colors.text}
label-low-foreground = ${colors.red}

[module/memory]
type = internal/memory
interval = 2
label = "%percentage_used%%"
label-foreground = ${colors.text}

[module/cpu]
type = internal/cpu
interval = 2
label = "%percentage%%"
label-foreground = ${colors.text}

[module/filesystem]
type = internal/fs
mount-0 = /
interval = 30
label-mounted = "%percentage_used%%"
label-mounted-foreground = ${colors.blue}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

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
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.orange}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.orange}
click-left = ~/.local/bin/powermenu.sh &

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
label-unfocused-foreground = ${colors.grey}
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
label = "%{A1:GTK_THEME=Rice-varinka gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
format-connected-prefix = " "
label-connected = "%{A1:nm-connection-editor &:}%ifname%%{A}"
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#F8F9FA' WIFI_OFF_FG='#DE8658' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

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
modules-left = launcher i3
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date sep power

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

[module/sep]
type = custom/text
format = <label>
label = "  "

; --- real widgets ------------------------------------------------------------
[module/launcher]
type = custom/text
format = <label>
label = "󰣇"
label-foreground = ${colors.blue}
click-left = ~/.local/bin/app-menu.sh &

[module/power]
type = custom/text
format = <label>
label = ""
label-foreground = ${colors.blue}
click-left = ~/.local/bin/powermenu.sh &

[module/i3]
type = internal/i3
format = <label-state>
index-sort = true
wrapping-scroll = false
ws-label = %index%
label-focused = ${self.ws-label}
label-focused-font = 3
label-focused-padding = 2
label-focused-foreground = ${colors.base}
label-focused-background = ${colors.blue}
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-padding = 2
label-unfocused-foreground = ${colors.indigo}
label-urgent = ${self.ws-label}
label-urgent-font = 3
label-urgent-padding = 2
label-urgent-foreground = ${colors.red}

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d
time = %H:%M
format-prefix = " "
format-prefix-foreground = ${colors.cyan}
label = "%{A1:GTK_THEME=Rice-yael gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = "%output%%"

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX='' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#FFFFFF' WIFI_OFF_FG='#EE5396' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[settings]
screenchange-reload = true
EOF
cat > "$CONF/polybar/themes/yucklys-square.ini" <<'EOF'
; Yucklys - modeled directly on github.com/Yucklys/polybar-nord-theme's real
; dark-colors/nord-top/nord-down/nord-config (a full local clone read
; directly) plus its own polybar-nord.png screenshot. Real, distinguishing
; choice vs this rice's existing "nord" port: that one is built from
; nord1/nord2 surface layers + nord10 (#5e81ac) as its main accent; this
; source never touches nord10 or nord1/nord2 at all - it stays fully flat
; (no chip backgrounds anywhere except a genuine urgent-workspace/
; temperature-warning invert and the powermenu "pill"), using underline-
; only accents in nord7 (#8fbcbb, teal - focused workspace/title) and nord9
; (#81a1c1, its real dominant secondary accent) instead. Colors below are
; copied byte-for-byte from its real colors/dark-colors.
;
; Workspace switcher is genuinely unusual and kept as-is: focused shows a
; roman-numeral icon (I-X, from its real ws-icon-N config) framed by a
; teal underline; every UNFOCUSED workspace shows only a plain "*" dot in
; nord9, not its own number - confirmed real (label-unfocused = "•" in its
; actual nord-top), not a fetch artifact, unlike several icon glyphs
; elsewhere in its config that came back blank (nerd-font codepoints that
; didn't survive plain-text fetching) - those were filled in with icons
; already used elsewhere in this rice's own themes rather than guessed.
;
; Its own module set leans on several services this system doesn't run
; (mpd, an OpenWeather API key, a clash proxy, a personal onedrive client,
; clipmenu, mullvad, a private daily-poem API, and a borrowed third-party
; "nord-oneline" rofi launcher theme from lr-tech/rofi-themes-collection -
; not really Yucklys' own design, same situation already hit porting
; "alireza"'s rofi setup) - skipped rather than shipped broken or empty.
; Its real, dependency-free modules (i3, title, capslock, pulseaudio,
; network signal-ramp, cpu/memory, temperature, powermenu) are kept and
; restyled only enough to fit this rice's font/icon set; this rice's own
; usual widgets (backlight, media, cliamp, bluetooth, caffeine, dnd,
; updates, layout, tray, date) are appended alongside them rather than
; replacing anything. Powermenu keeps its real filled-pill look (solid
; nord9 background) but is rewired to this rice's own powermenu.sh
; ($mod+shift+p) instead of the source's rofi-power-menu modi, which isn\'t
; installed here.
[colors]
base     = #2E3440
mantle   = #2E3440
surface0 = #4C566A
surface1 = #4C566A
text     = #D8DEE9
subtext  = #4C566A
mauve    = #81A1C1
lavender = #B48EAD
sky      = #88C0D0
green    = #A3BE8C
teal     = #8FBCBB
yellow   = #EBCB8B
peach    = #D08770
red      = #BF616A

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
underline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3 title
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = keyboard backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu temperature updates layout tray date powermenu

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu temperature updates date

; --- real widgets, from the source's own nord-top/nord-down -----------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
enable-scroll = true
wrapping-scroll = true
ws-icon-0 = 1;I
ws-icon-1 = 2;II
ws-icon-2 = 3;III
ws-icon-3 = 4;IV
ws-icon-4 = 5;V
ws-icon-5 = 6;VI
ws-icon-6 = 7;VII
ws-icon-7 = 8;VIII
ws-icon-8 = 9;IX
ws-icon-9 = 10;X
label-focused = %icon%
label-focused-font = 3
label-focused-foreground = ${colors.teal}
label-focused-underline = ${colors.teal}
label-focused-padding = 2
label-unfocused = *
label-unfocused-font = 3
label-unfocused-foreground = ${colors.mauve}
label-unfocused-padding = 2
label-urgent = %icon%
label-urgent-font = 3
label-urgent-foreground = ${colors.text}
label-urgent-background = ${colors.red}
label-urgent-padding = 2

[module/title]
type = internal/xwindow
format = <label>
format-underline = ${colors.teal}
label = %title%
label-maxlen = 20
label-empty = Desktop
label-padding = 2

[module/keyboard]
type = internal/xkeyboard
blacklist-0 = num lock
blacklist-1 = scroll lock
format = <label-indicator>
label-indicator-on = " CL"
label-indicator-on-foreground = ${colors.peach}
format-underline = ${colors.peach}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
format-volume-underline = ${colors.lavender}
label-volume = "  %percentage%%"
label-volume-foreground = ${colors.green}
label-muted = " muted"
label-muted-foreground = ${colors.red}

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:} %ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

; Real 4-level signal-strength ramp from the source (urgent/notify/nord7/
; success by strength) - its actual distinguishing touch vs every other
; theme's plain-text network module here.
[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#D8DEE9' WIFI_OFF_FG='#BF616A' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/cpu]
type = internal/cpu
interval = 2
format = <label>
label = "  %percentage%%"
label-foreground = ${colors.green}

[module/memory]
type = internal/memory
interval = 2
format = <label>
label = "  %percentage_used%%"
label-foreground = ${colors.yellow}

[module/temperature]
type = internal/temperature
thermal-zone = 0
base-temperature = 20
warn-temperature = 70
format = <ramp><label>
format-warn = <label-warn>
format-warn-background = ${colors.text}
label = " %temperature-c%"
label-warn = " %temperature-c%"
label-warn-foreground = ${colors.red}
ramp-0 =
ramp-0-foreground = ${colors.sky}
ramp-1 =
ramp-1-foreground = ${colors.green}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "  %output%%"
label-foreground = ${colors.mauve}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>
label-foreground = ${colors.green}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>
label-foreground = ${colors.green}

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging = <label-charging>
format-charging-underline = ${colors.text}
label-charging = "  %percentage%%"
label-charging-foreground = ${colors.text}
format-discharging = <label-discharging>
format-discharging-underline = ${colors.yellow}
label-discharging = "  %percentage%%"
label-discharging-foreground = ${colors.text}
label-full = " Full"
label-full-foreground = ${colors.green}
format-full-underline = ${colors.green}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>
label-foreground = ${colors.yellow}

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %a
format = <label>
label = "%{A1:GTK_THEME=Rice-yucklys gnome-calendar &:} %date%%{A}"
label-foreground = ${colors.text}
label-underline = ${colors.sky}

; Real filled "pill" - the source's own distinctive treatment for its
; powermenu icon (solid nord9 background, base-color text) rather than an
; underline like everything else here.
[module/powermenu]
type = custom/text
format = <label>
label = " ⏻ "
label-background = ${colors.mauve}
label-foreground = ${colors.base}
click-left = ~/.local/bin/powermenu.sh &

[settings]
screenchange-reload = true
EOF
cat > "$CONF/polybar/themes/yucklys-light-square.ini" <<'EOF'
; Yucklys Light - the source's own light/dark PAIR (github.com/Yucklys/
; polybar-nord-theme's real colors/light-colors + bars/light-config, a full
; local clone read directly): same module set and layout as this rice's
; "yucklys" (dark), background/text/muted swap to the source's real light
; values (base=nord6 #eceff4, text=nord0 #2e3440, muted=nord1 #3b4252 -
; copied byte-for-byte), while every Frost/Aurora accent hue (teal/sky/
; mauve/green/yellow/peach/red/lavender) stays the exact same real hex the
; dark theme uses - that part of the source's own light-colors file is
; identical to dark-colors, confirmed by diffing them directly.
;
; Those accent hexes are genuinely unreadable as TEXT on this bright a
; background though - computed contrast against #eceff4 (WCAG relative
; luminance, not eyeballed): teal 1.81:1, sky 1.74:1, mauve 2.34:1, yellow
; 1.35:1 - all well under even the lenient 3:1 floor for icon-sized text,
; the same class of bug this rice's own README already documents fixing
; on "aline" and "nord" (unreadable accents on a light chip/dark surface
; kept for luminance reasons). Each accent below gets a same-hue, darkened
; "text-safe" value (>=4.5:1 against #eceff4) for use as underline/label
; text; the ORIGINAL vivid value is kept under -bg for anything used as a
; filled chip instead (urgent workspace, powermenu pill, temperature-warn),
; where the vivid tone is the chip color and a separately-chosen readable
; foreground goes on top of it - not a fabricated palette, the same real
; hues just split into two roles the way this rice's own "nord" theme
; already splits red/red-light for the same reason.
[colors]
base     = #ECEFF4
mantle   = #ECEFF4
surface0 = #3B4252
surface1 = #3B4252
text     = #2E3440
subtext  = #3B4252
mauve    = #496F95
mauve-bg = #81A1C1
lavender = #8C5D83
sky      = #357587
green    = #597442
teal     = #457473
yellow   = #8D6618
peach    = #AA5338
red      = #B54954
red-bg   = #BF616A

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
underline-size = 2
font-0 = "JetBrainsMono Nerd Font:size=10;2"
font-1 = "JetBrainsMono Nerd Font:size=14;4"
font-2 = "JetBrains Mono:size=10;2"
modules-left = i3 title
modules-center =

[bar/top-primary]
inherit = bar/base
modules-right = keyboard backlight pulseaudio media cliamp network-wired network-wireless bluetooth caffeine dnd battery memory cpu temperature updates layout tray date powermenu

[bar/top-secondary]
inherit = bar/base
modules-right = backlight pulseaudio media cliamp network-wired network-wireless memory cpu temperature updates date

; --- real widgets, from the source's own nord-top/nord-down -----------------
[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
enable-scroll = true
wrapping-scroll = true
ws-icon-0 = 1;I
ws-icon-1 = 2;II
ws-icon-2 = 3;III
ws-icon-3 = 4;IV
ws-icon-4 = 5;V
ws-icon-5 = 6;VI
ws-icon-6 = 7;VII
ws-icon-7 = 8;VIII
ws-icon-8 = 9;IX
ws-icon-9 = 10;X
label-focused = %icon%
label-focused-font = 3
label-focused-foreground = ${colors.teal}
label-focused-underline = ${colors.teal}
label-focused-padding = 2
label-unfocused = *
label-unfocused-font = 3
label-unfocused-foreground = ${colors.mauve}
label-unfocused-padding = 2
label-urgent = %icon%
label-urgent-font = 3
label-urgent-foreground = ${colors.base}
label-urgent-background = ${colors.red-bg}
label-urgent-padding = 2

[module/title]
type = internal/xwindow
format = <label>
format-underline = ${colors.teal}
label = %title%
label-maxlen = 20
label-empty = Desktop
label-padding = 2

[module/keyboard]
type = internal/xkeyboard
blacklist-0 = num lock
blacklist-1 = scroll lock
format = <label-indicator>
label-indicator-on = " CL"
label-indicator-on-foreground = ${colors.peach}
format-underline = ${colors.peach}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
format-volume-underline = ${colors.lavender}
label-volume = "  %percentage%%"
label-volume-foreground = ${colors.green}
label-muted = " muted"
label-muted-foreground = ${colors.red}

[module/network-wired]
type = internal/network
interface-type = wired
interval = 3
label-connected = "%{A1:nm-connection-editor &:} %ifname%%{A}"
label-connected-foreground = ${colors.sky}
format-disconnected =

[module/network-wireless]
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX='' WIFI_CONNECTED_FG='#2E3440' WIFI_OFF_FG='#B54954' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>

[module/cpu]
type = internal/cpu
interval = 2
format = <label>
label = "  %percentage%%"
label-foreground = ${colors.green}

[module/memory]
type = internal/memory
interval = 2
format = <label>
label = "  %percentage_used%%"
label-foreground = ${colors.yellow}

[module/temperature]
type = internal/temperature
thermal-zone = 0
base-temperature = 20
warn-temperature = 70
format = <ramp><label>
format-warn = <label-warn>
format-warn-background = ${colors.text}
label = " %temperature-c%"
label-warn = " %temperature-c%"
label-warn-foreground = ${colors.red-bg}
ramp-0 =
ramp-0-foreground = ${colors.sky}
ramp-1 =
ramp-1-foreground = ${colors.green}

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
label = "  %output%%"
label-foreground = ${colors.mauve}

[module/media]
type = custom/script
exec = ~/.local/bin/polybar-media.sh
interval = 1
format = <label>
label-foreground = ${colors.green}

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
format = <label>
label-foreground = ${colors.green}

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
format = <label>
label-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
format-charging = <label-charging>
format-charging-underline = ${colors.text}
label-charging = "  %percentage%%"
label-charging-foreground = ${colors.text}
format-discharging = <label-discharging>
format-discharging-underline = ${colors.yellow}
label-discharging = "  %percentage%%"
label-discharging-foreground = ${colors.text}
label-full = " Full"
label-full-foreground = ${colors.green}
format-full-underline = ${colors.green}

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
format = <label>
label-foreground = ${colors.yellow}

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>
label-foreground = ${colors.text}

; Dedicated dark backdrop for the tray specifically - most tray icons
; (Discord, 1Password, etc.) are drawn in white/light colors expecting a
; dark bar, and would otherwise inherit this theme's own light base and
; effectively disappear (same real bug already fixed on this rice's own
; "aline"/"brenda" themes). Reuses surface0 (nord1, the theme's one real
; dark tone) rather than a fabricated new color.
[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

[module/date]
type = internal/date
interval = 1
date = %H:%M
date-alt = %Y-%m-%d %a
format = <label>
label = "%{A1:GTK_THEME=Rice-yucklys-light gnome-calendar &:} %date%%{A}"
label-foreground = ${colors.text}
label-underline = ${colors.sky}

; Real filled "pill" - the source's own distinctive treatment for its
; powermenu icon. Chip stays the original vivid nord9, text goes on
; subtext (dark) instead of base (light-on-light would be unreadable
; against this mid-tone chip - checked: 2.34:1 vs 3.74:1).
[module/powermenu]
type = custom/text
format = <label>
label = " ⏻ "
label-background = ${colors.mauve-bg}
label-foreground = ${colors.subtext}
click-left = ~/.local/bin/powermenu.sh &

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
surface0 = #151720
surface1 = #1C1E27
text   = #A5B6CF
subtext = #6E8DB4
focus  = #8EA6C4
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
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep bluetooth sep caffeine sep dnd sep battery sep memory sep cpu sep updates sep layout sep tray sep date

[bar/top-secondary]
inherit = bar/base
modules-right = backlight sep pulseaudio sep media sep cliamp sep network-wired network-wireless sep memory sep cpu sep updates sep date

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
label-focused-font = 3
label-focused-foreground = ${colors.focus}
label-focused-padding = 2
label-unfocused = ${self.ws-label}
label-unfocused-font = 3
label-unfocused-foreground = ${colors.subtext}
label-unfocused-padding = 2
label-urgent = ${self.ws-label}
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
format-prefix-foreground = ${colors.blue}
label = "%{A1:GTK_THEME=Rice-z0mbi3 gnome-calendar &:}%date%  %time%%{A}"

[module/backlight]
type = custom/script
exec = ~/.local/bin/polybar-backlight.sh
interval = 1
scroll-up = brightnessctl set +5% &
scroll-down = brightnessctl set 5%- &
format = <label>
format-background = ${colors.surface0}
format-prefix = "󰃟 "
format-prefix-foreground = ${colors.yellow}
label = " %output%% "

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

[module/cliamp]
type = custom/script
exec = ~/.local/bin/polybar-cliamp.sh
interval = 3
click-left = ~/.local/bin/cliamp-toggle.sh &
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
type = custom/script
exec = WIFI_PREFIX=' ' WIFI_SUFFIX=' ' WIFI_CONNECTED_FG='#A5B6CF' WIFI_OFF_FG='#DD6777' ~/.local/bin/polybar-wifi.sh
interval = 3
click-left = ~/.local/bin/wifi-menu.sh &
click-middle = nm-connection-editor &
click-right = ~/.local/bin/wifi-toggle.sh &
format = <label>
format-background = #151720

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
click-middle = ~/.local/bin/notification-center.sh &
click-right = dunstctl history-clear
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

[module/updates]
type = custom/script
exec = ~/.local/bin/polybar-updates.sh
tail = true
click-left = kitty --class UpdatesTask -e ~/.local/bin/software-update.sh &
label-foreground = ${colors.yellow}
format-background = ${colors.surface0}
format = <label>

[module/layout]
type = custom/script
exec = ~/.local/bin/polybar-layout.sh
interval = 1
format = <label>

[module/tray]
type = internal/tray
tray-spacing = 8
tray-padding = 6
tray-background = ${colors.surface0}
format-background = ${colors.surface0}

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
# A plain SIGTERM has repeatedly failed to actually kill polybar during
# rapid theme-switch/restart cycles (confirmed via /proc/<pid>/status - the
# process just sits there in state S, ignoring it) - waiting on it forever
# then hangs this whole script (and anything that calls it, e.g.
# polybar-theme.sh). Escalate to SIGKILL after a bounded ~2s grace period
# instead of waiting indefinitely for a graceful exit.
for _ in $(seq 1 20); do
  pgrep -x polybar >/dev/null || break
  sleep 0.1
done
pgrep -x polybar >/dev/null && pkill -9 -x polybar
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
# A stray, unlabeled window (no WM_CLASS - confirmed by inspecting it
# directly with xprop) sometimes already owns the X11 tray manager
# selection by the time polybar starts, even on a genuinely fresh boot -
# not leftover state from a previous session, since this reproduces right
# after a real reboot with nothing else having run yet. polybar's own
# internal/tray module detects this and logs "Systray selection already
# managed", then simply gives up on ever showing a tray for that run -
# which is what actually caused the tray (and visually everything after
# it, since polybar keeps rendering the rest of the bar fine) to look
# empty. Not fixable by restarting polybar alone, since the same phantom
# window just blocks the next attempt too. Query the real X11 selection
# owner directly (python3-xlib, already installed) rather than spinning up
# a throwaway polybar instance just to read its warning off stderr - near-
# instant, and doesn't flash a duplicate bar on every single reload. A
# window some other legitimate polybar instance owns always has
# WM_CLASS="Polybar" (confirmed) - anything holding the selection without
# that WM_CLASS is the phantom, safe to destroy outright.
python3 - <<'PYEOF'
from Xlib import display
from Xlib.error import BadWindow
d = display.Display()
atom = d.intern_atom("_NET_SYSTEM_TRAY_S0")
owner = d.get_selection_owner(atom)
if owner:
    try:
        wm_class = owner.get_wm_class()
    except BadWindow:
        wm_class = None
    if not wm_class or "Polybar" not in wm_class:
        owner.destroy()
        d.sync()
PYEOF

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

# Only START snixembed if it isn't already running - do NOT kill+restart
# it here on every reload/restart. An earlier version of this script force-
# restarted snixembed every time on the theory that it'd make already-open
# SNI apps notice the watcher's name changed owner and re-register against
# the new polybar tray window (observed once, for Slack and CopyQ, when
# snixembed's own binary had just been rebuilt). Live-tested this properly
# afterwards and that doesn't generalize: forcing the restart left most
# apps' icons (1Password, Spotify, CopyQ, chrome/Claude status icons,
# remmina, Udiskie) permanently un-embedded as bare floating windows -
# manually restarting each individual app didn't fix it either, and even a
# fully clean fresh polybar+snixembed pair (no stale processes at all)
# still failed to claim _NET_SYSTEM_TRAY_S0 afterwards, throwing internal
# "tray: Failed to clear/reconfigure client" XCB errors - a real polybar
# tray bug this script can't work around by restarting things faster.
# Leaving an already-working snixembed alone avoids triggering it, at the
# cost of reintroducing the narrower original problem (an icon that was
# already embedded in a since-closed polybar window can stay orphaned) -
# a smaller, rarer annoyance than breaking most of the tray on every
# single reload.
pgrep -x snixembed >/dev/null || { snixembed --fork & disown; }
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
#   1. xset's screensaver/DPMS timers are disabled, so xss-lock never fires
#      (it triggers off X11's screensaver-activation signal) and the display
#      never blanks/suspends.
#   2. A backgrounded `systemd-inhibit` holds idle/sleep/lid-switch locks so
#      systemd-logind won't suspend even on lid close, matching what the
#      screensaver-based inhibition alone wouldn't cover.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
# Must match the i3 config's own startup `xset s 1200 dpms 3000 3000 3000`
# exactly - this used to be a stale "300 dpms 300 600 900" (5min) left
# over from an earlier default, so toggling caffeine off silently dropped
# the real idle timeout down to 5min from then on for the rest of the
# session, cutting the screensaver's own on-screen time short well before
# intended.
IDLE_RESTORE="1200 dpms 3000 3000 3000"

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
EOF
chmod +x "$BIN/dnd-toggle.sh"

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
# generation time), using polybar's inline %{F#hex}...%{F-} tag so one
# shared script still renders every theme's own colors without a separate
# copy per theme.
if [ "$(nmcli radio wifi 2>/dev/null)" != "enabled" ]; then
  printf '%s%%{F%s}wifi off%%{F-}%s' "$WIFI_PREFIX" "$WIFI_OFF_FG" "$WIFI_SUFFIX"
  exit 0
fi
essid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2}' | head -1)
[ -n "$essid" ] && printf '%s%%{F%s}%s%%{F-}%s' "$WIFI_PREFIX" "$WIFI_CONNECTED_FG" "$essid" "$WIFI_SUFFIX"
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
brightnessctl -m info 2>/dev/null | cut -d, -f4 | tr -d '%'
EOF
chmod +x "$BIN/polybar-backlight.sh"

log "Writing polybar split-layout indicator script..."
cat > "$BIN/polybar-layout.sh" <<'EOF'
#!/usr/bin/env bash
# polybar custom/script module: shows the focused container's current split
# direction - i.e. what direction the NEXT window opened there will go,
# set via Mod+v/Mod+b (see i3 config) - not visible anywhere else in i3
# itself, since split direction has no on-screen effect until a new window
# is actually opened (unlike fullscreen/floating, which are immediately
# visible on their own). Also shows stacked/tabbed if the container is in
# one of those layouts (Mod+t cycles split h/v; stacked/tabbed reachable via
# i3-msg directly, no dedicated keybinding in this rice).
#
# Polled on a short interval (like caffeine/dnd above) rather than an
# `i3-msg -t subscribe` event loop - simpler, no long-running subprocess to
# manage, and split-direction changes don't need sub-second responsiveness.
layout=$(i3-msg -t get_tree 2>/dev/null | jq -r '
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
# script rather than inlined in i3's exec line. Inlining it as
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
    lines: 14;
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

cat > "$CONF/rofi/themes/alireza.rasi" <<'EOF'
* {
    base:     #282A36db;
    mantle:   #282A3603;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    purple:   #BD93F9ff;
    pink:     #FF79C6ff;
    surface0: #44475A80;

    background-color: @mantle;
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

prompt { text-color: @purple; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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

/* Pink, not purple, for the selected row - the source's own screenshots
 * (file manager's selected folder, the terminal music player's selected
 * track) consistently highlight in pink, reserving purple for the window
 * border/workspace-chip role its colorscheme.conf actually assigns it. */
element selected {
    background-color: @surface0;
    text-color: @pink;
}
EOF
cat > "$CONF/rofi/themes/alireza-powermenu.rasi" <<'EOF'
* {
    base:     #282A36db;
    mantle:   #282A3603;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    purple:   #BD93F9ff;
    pink:     #FF79C6ff;
    surface0: #44475A80;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @purple;
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
    border-color: @pink;
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

cat > "$CONF/rofi/themes/archblur.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
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

prompt { text-color: @accent; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @accent;
}
EOF
cat > "$CONF/rofi/themes/archblur-powermenu.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
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
    border-color: @accent;
    border-radius: 14px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
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
    lines: 14;
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

cat > "$CONF/rofi/themes/breddie.rasi" <<'EOF'
/* Same fix as this rice's own "isabel"/"pamela" ports: the source's real
 * rofi config sets bg-selected to the exact same value as bg
 * (`bg: #1a1b2666; bg-selected: #1a1b2666;`), making the selected row
 * invisible in practice - given a real, visible highlight here instead. */
* {
    base:     #1A1B26db;
    mantle:   #1A1B2603;
    text:     #E5E9F0ff;
    subtext:  #444B61ff;
    lavender: #ACB0D0ff;
    surface0: #292A4480;

    background-color: @mantle;
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

prompt { text-color: @lavender; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @lavender;
}
EOF
cat > "$CONF/rofi/themes/breddie-powermenu.rasi" <<'EOF'
* {
    base:     #1A1B26db;
    mantle:   #1A1B2603;
    text:     #E5E9F0ff;
    subtext:  #444B61ff;
    lavender: #ACB0D0ff;
    surface0: #292A4480;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @lavender;
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
    border-color: @lavender;
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
    lines: 14;
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
    lines: 14;
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

cat > "$CONF/rofi/themes/cherryblocks.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FB4934ff;
    surface0: #3C3836ff;

    background-color: @mantle;
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

prompt { text-color: @accent; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @accent;
}
EOF
cat > "$CONF/rofi/themes/cherryblocks-powermenu.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FB4934ff;
    surface0: #3C3836ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
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
    border-color: @accent;
    border-radius: 14px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
    horizontal-align: 0.32;
    vertical-align: 0.5;
}
EOF
cat > "$CONF/rofi/themes/classic.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
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

prompt { text-color: @accent; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @accent;
}
EOF
cat > "$CONF/rofi/themes/classic-powermenu.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
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
    border-color: @accent;
    border-radius: 14px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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

cat > "$CONF/rofi/themes/tobi.rasi" <<'EOF'
* {
    base:     #1E1E2Eff;
    mantle:   #181825ff;
    text:     #D9E0EEff;
    subtext:  #6E6C7Eff;
    blue:     #62B4F9ff;
    surface0: #313244ff;

    background-color: @mantle;
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

prompt { text-color: @blue; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @blue;
}
EOF
cat > "$CONF/rofi/themes/tobi-powermenu.rasi" <<'EOF'
* {
    base:     #1E1E2Eff;
    mantle:   #181825ff;
    text:     #D9E0EEff;
    subtext:  #6E6C7Eff;
    blue:     #62B4F9ff;
    surface0: #313244ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @blue;
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
    border-color: @blue;
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
    lines: 14;
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
cat > "$CONF/rofi/themes/yucklys-powermenu.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #D8DEE9ff;
    subtext:  #4C566Aff;
    mauve:    #81A1C1ff;
    surface0: #4C566Aff;

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
    horizontal-align: 0.32;
    vertical-align: 0.5;
}
EOF
cat > "$CONF/rofi/themes/yucklys-light-powermenu.rasi" <<'EOF'
* {
    base:     #ECEFF4ff;
    mantle:   #ECEFF4ff;
    text:     #2E3440ff;
    subtext:  #3B4252ff;
    mauve:    #496F95ff;
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
    text-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 14px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
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
    lines: 14;
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
cat > "$CONF/rofi/themes/yucklys.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #D8DEE9ff;
    subtext:  #4C566Aff;
    mauve:    #81A1C1ff;
    surface0: #4C566Aff;

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
    lines: 14;
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
cat > "$CONF/rofi/themes/yucklys-light.rasi" <<'EOF'
* {
    base:     #ECEFF4ff;
    mantle:   #ECEFF4ff;
    text:     #2E3440ff;
    subtext:  #3B4252ff;
    mauve:    #496F95ff;
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
    lines: 14;
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

/* Selected element's chip is the dark surface0, not the light mantle - its
   text needs the LIGHT base color to stay readable (checked: base against
   surface0 is 8.73:1; mauve or text against surface0 is 1.2-1.9:1, the
   same "text color kept from the unselected/dark-bg case" mistake this
   rice's README already documents catching elsewhere). */
element selected {
    background-color: @surface0;
    text-color: @base;
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
    lines: 14;
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
    lines: 14;
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

cat > "$CONF/rofi/themes/alireza-square.rasi" <<'EOF'
* {
    base:     #282A36db;
    mantle:   #282A3603;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    purple:   #BD93F9ff;
    pink:     #FF79C6ff;
    surface0: #44475A80;

    background-color: @mantle;
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

prompt { text-color: @purple; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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

/* Pink, not purple, for the selected row - the source's own screenshots
 * (file manager's selected folder, the terminal music player's selected
 * track) consistently highlight in pink, reserving purple for the window
 * border/workspace-chip role its colorscheme.conf actually assigns it. */
element selected {
    background-color: @surface0;
    text-color: @pink;
}
EOF
cat > "$CONF/rofi/themes/alireza-square-powermenu.rasi" <<'EOF'
* {
    base:     #282A36db;
    mantle:   #282A3603;
    text:     #F8F8F2ff;
    subtext:  #6272A4ff;
    purple:   #BD93F9ff;
    pink:     #FF79C6ff;
    surface0: #44475A80;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @purple;
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
    border-color: @pink;
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

cat > "$CONF/rofi/themes/archblur-square.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
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

prompt { text-color: @accent; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @accent;
}
EOF
cat > "$CONF/rofi/themes/archblur-square-powermenu.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
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
    border-color: @accent;
    border-radius: 0px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
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
    lines: 14;
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

cat > "$CONF/rofi/themes/breddie-square.rasi" <<'EOF'
/* Same fix as this rice's own "isabel"/"pamela" ports: the source's real
 * rofi config sets bg-selected to the exact same value as bg
 * (`bg: #1a1b2666; bg-selected: #1a1b2666;`), making the selected row
 * invisible in practice - given a real, visible highlight here instead. */
* {
    base:     #1A1B26db;
    mantle:   #1A1B2603;
    text:     #E5E9F0ff;
    subtext:  #444B61ff;
    lavender: #ACB0D0ff;
    surface0: #292A4480;

    background-color: @mantle;
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

prompt { text-color: @lavender; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @lavender;
}
EOF
cat > "$CONF/rofi/themes/breddie-square-powermenu.rasi" <<'EOF'
* {
    base:     #1A1B26db;
    mantle:   #1A1B2603;
    text:     #E5E9F0ff;
    subtext:  #444B61ff;
    lavender: #ACB0D0ff;
    surface0: #292A4480;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @lavender;
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
    border-color: @lavender;
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
    lines: 14;
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
    lines: 14;
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

cat > "$CONF/rofi/themes/cherryblocks-square.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FB4934ff;
    surface0: #3C3836ff;

    background-color: @mantle;
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

prompt { text-color: @accent; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @accent;
}
EOF
cat > "$CONF/rofi/themes/cherryblocks-square-powermenu.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FB4934ff;
    surface0: #3C3836ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
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
    border-color: @accent;
    border-radius: 0px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
    horizontal-align: 0.32;
    vertical-align: 0.5;
}
EOF
cat > "$CONF/rofi/themes/classic-square.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
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

prompt { text-color: @accent; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @accent;
}
EOF
cat > "$CONF/rofi/themes/classic-square-powermenu.rasi" <<'EOF'
* {
    base:     #282828ff;
    mantle:   #1D2021ff;
    text:     #EBDBB2ff;
    subtext:  #A89984ff;
    accent:   #FE8019ff;
    surface0: #3C3836ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
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
    border-color: @accent;
    border-radius: 0px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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
    lines: 14;
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

cat > "$CONF/rofi/themes/tobi-square.rasi" <<'EOF'
* {
    base:     #1E1E2Eff;
    mantle:   #181825ff;
    text:     #D9E0EEff;
    subtext:  #6E6C7Eff;
    blue:     #62B4F9ff;
    surface0: #313244ff;

    background-color: @mantle;
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

prompt { text-color: @blue; padding: 0 8px 0 0; }
entry  { text-color: @text; }

listview {
    lines: 14;
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
    text-color: @blue;
}
EOF
cat > "$CONF/rofi/themes/tobi-square-powermenu.rasi" <<'EOF'
* {
    base:     #1E1E2Eff;
    mantle:   #181825ff;
    text:     #D9E0EEff;
    subtext:  #6E6C7Eff;
    blue:     #62B4F9ff;
    surface0: #313244ff;

    background-color: @mantle;
    text-color: @text;
    font: "JetBrainsMono Nerd Font 11";
}

window {
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @blue;
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
    border-color: @blue;
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
    lines: 14;
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
    lines: 14;
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
cat > "$CONF/rofi/themes/yucklys-square.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #D8DEE9ff;
    subtext:  #4C566Aff;
    mauve:    #81A1C1ff;
    surface0: #4C566Aff;

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
    lines: 14;
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
cat > "$CONF/rofi/themes/yucklys-light-square.rasi" <<'EOF'
* {
    base:     #ECEFF4ff;
    mantle:   #ECEFF4ff;
    text:     #2E3440ff;
    subtext:  #3B4252ff;
    mauve:    #496F95ff;
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
    lines: 14;
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

/* Selected element's chip is the dark surface0, not the light mantle - its
   text needs the LIGHT base color to stay readable (checked: base against
   surface0 is 8.73:1; mauve or text against surface0 is 1.2-1.9:1, the
   same "text color kept from the unselected/dark-bg case" mistake this
   rice's README already documents catching elsewhere). */
element selected {
    background-color: @surface0;
    text-color: @base;
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
cat > "$CONF/rofi/themes/yucklys-square-powermenu.rasi" <<'EOF'
* {
    base:     #2E3440ff;
    mantle:   #2E3440ff;
    text:     #D8DEE9ff;
    subtext:  #4C566Aff;
    mauve:    #81A1C1ff;
    surface0: #4C566Aff;

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
    horizontal-align: 0.32;
    vertical-align: 0.5;
}
EOF
cat > "$CONF/rofi/themes/yucklys-light-square-powermenu.rasi" <<'EOF'
* {
    base:     #ECEFF4ff;
    mantle:   #ECEFF4ff;
    text:     #2E3440ff;
    subtext:  #3B4252ff;
    mauve:    #496F95ff;
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
    text-color: @base;
    border: 2px;
    border-color: @mauve;
    border-radius: 0px;
}
element-text {
    font: "JetBrainsMono Nerd Font 26";
    background-color: transparent;
    text-color: inherit;
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
    lines: 14;
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
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

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

cat > "$CONF/kitty/themes/alireza.conf" <<'EOF'
foreground              #F8F8F2
background              #282A36
selection_foreground    #282A36
selection_background    #F8F8F2
cursor                  #BD93F9
cursor_text_color       #282A36

color0  #21222C
color8  #6272A4
color1  #FF5E76
color9  #FF6E6E
color2  #50FA7B
color10 #69FF94
color3  #F1FA8C
color11 #FFFFA5
color4  #BD93F9
color12 #D6ACFF
color5  #FF79C6
color13 #FF92DF
color6  #8BE9FD
color14 #A4FFFF
color7  #F8F8F2
color15 #FFFFFF
EOF

cat > "$CONF/kitty/themes/archblur.conf" <<'EOF'
foreground              #EBDBB2
background              #282828
selection_foreground    #282828
selection_background    #EBDBB2
cursor                  #FE8019
cursor_text_color       #282828

color0  #3C3836
color8  #928374
color1  #FB4934
color9  #FB4934
color2  #B8BB26
color10 #B8BB26
color3  #FABD2F
color11 #FABD2F
color4  #83A598
color12 #83A598
color5  #D3869B
color13 #D3869B
color6  #8EC07C
color14 #8EC07C
color7  #EBDBB2
color15 #FBF1C7
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

cat > "$CONF/kitty/themes/breddie.conf" <<'EOF'
foreground              #E5E9F0
background              #1A1B26
selection_foreground    #1A1B26
selection_background    #E5E9F0
cursor                  #ACB0D0
cursor_text_color       #1A1B26

color0  #32344A
color8  #444B6A
color1  #F7768E
color9  #FF7A93
color2  #9ECE6A
color10 #B9F27C
color3  #EBCB8C
color11 #FF9E64
color4  #81A1C1
color12 #7DA6FF
color5  #AD8EE6
color13 #BB9AF7
color6  #7AA2F7
color14 #0DB9D7
color7  #E5E9F0
color15 #ACB0D0
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

cat > "$CONF/kitty/themes/cherryblocks.conf" <<'EOF'
foreground              #EBDBB2
background              #282828
selection_foreground    #282828
selection_background    #EBDBB2
cursor                  #FB4934
cursor_text_color       #282828

color0  #3C3836
color8  #928374
color1  #FB4934
color9  #FB4934
color2  #B8BB26
color10 #B8BB26
color3  #FABD2F
color11 #FABD2F
color4  #83A598
color12 #83A598
color5  #D3869B
color13 #D3869B
color6  #8EC07C
color14 #8EC07C
color7  #EBDBB2
color15 #FBF1C7
EOF
cat > "$CONF/kitty/themes/classic.conf" <<'EOF'
foreground              #EBDBB2
background              #282828
selection_foreground    #282828
selection_background    #EBDBB2
cursor                  #FE8019
cursor_text_color       #282828

color0  #3C3836
color8  #928374
color1  #FB4934
color9  #FB4934
color2  #B8BB26
color10 #B8BB26
color3  #FABD2F
color11 #FABD2F
color4  #83A598
color12 #83A598
color5  #D3869B
color13 #D3869B
color6  #8EC07C
color14 #8EC07C
color7  #EBDBB2
color15 #FBF1C7
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

cat > "$CONF/kitty/themes/tobi.conf" <<'EOF'
foreground              #D9E0EE
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #D9E0EE
cursor                  #62B4F9
cursor_text_color       #1E1E2E

color0  #181825
color8  #6E6C7E
color1  #F28FAD
color9  #F88D96
color2  #ABE9B3
color10 #ABE9B3
color3  #FAE3B0
color11 #FAE3B0
color4  #62B4F9
color12 #96CDFB
color5  #F5C2E7
color13 #F5C2E7
color6  #89DCEB
color14 #89DCEB
color7  #D9E0EE
color15 #FFFFFF
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
cat > "$CONF/kitty/themes/yucklys.conf" <<'EOF'
foreground              #D8DEE9
background              #2E3440
selection_foreground    #2E3440
selection_background    #D8DEE9
cursor                  #81A1C1
cursor_text_color       #2E3440

color0  #3B4252
color8  #4C566A
color1  #BF616A
color9  #BF616A
color2  #A3BE8C
color10 #A3BE8C
color3  #EBCB8B
color11 #EBCB8B
color4  #81A1C1
color12 #81A1C1
color5  #B48EAD
color13 #B48EAD
color6  #88C0D0
color14 #8FBCBB
color7  #D8DEE9
color15 #ECEFF4
EOF
cat > "$CONF/kitty/themes/yucklys-light.conf" <<'EOF'
foreground              #2E3440
background              #ECEFF4
selection_foreground    #ECEFF4
selection_background    #2E3440
cursor                  #496F95
cursor_text_color       #ECEFF4

color0  #E5E9F0
color8  #3B4252
color1  #B54954
color9  #B54954
color2  #597442
color10 #597442
color3  #8D6618
color11 #8D6618
color4  #496F95
color12 #496F95
color5  #8C5D83
color13 #8C5D83
color6  #357587
color14 #457473
color7  #2E3440
color15 #2E3440
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

cat > "$CONF/kitty/themes/alireza-square.conf" <<'EOF'
foreground              #F8F8F2
background              #282A36
selection_foreground    #282A36
selection_background    #F8F8F2
cursor                  #BD93F9
cursor_text_color       #282A36

color0  #21222C
color8  #6272A4
color1  #FF5E76
color9  #FF6E6E
color2  #50FA7B
color10 #69FF94
color3  #F1FA8C
color11 #FFFFA5
color4  #BD93F9
color12 #D6ACFF
color5  #FF79C6
color13 #FF92DF
color6  #8BE9FD
color14 #A4FFFF
color7  #F8F8F2
color15 #FFFFFF
EOF

cat > "$CONF/kitty/themes/archblur-square.conf" <<'EOF'
foreground              #EBDBB2
background              #282828
selection_foreground    #282828
selection_background    #EBDBB2
cursor                  #FE8019
cursor_text_color       #282828

color0  #3C3836
color8  #928374
color1  #FB4934
color9  #FB4934
color2  #B8BB26
color10 #B8BB26
color3  #FABD2F
color11 #FABD2F
color4  #83A598
color12 #83A598
color5  #D3869B
color13 #D3869B
color6  #8EC07C
color14 #8EC07C
color7  #EBDBB2
color15 #FBF1C7
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

cat > "$CONF/kitty/themes/breddie-square.conf" <<'EOF'
foreground              #E5E9F0
background              #1A1B26
selection_foreground    #1A1B26
selection_background    #E5E9F0
cursor                  #ACB0D0
cursor_text_color       #1A1B26

color0  #32344A
color8  #444B6A
color1  #F7768E
color9  #FF7A93
color2  #9ECE6A
color10 #B9F27C
color3  #EBCB8C
color11 #FF9E64
color4  #81A1C1
color12 #7DA6FF
color5  #AD8EE6
color13 #BB9AF7
color6  #7AA2F7
color14 #0DB9D7
color7  #E5E9F0
color15 #ACB0D0
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

cat > "$CONF/kitty/themes/cherryblocks-square.conf" <<'EOF'
foreground              #EBDBB2
background              #282828
selection_foreground    #282828
selection_background    #EBDBB2
cursor                  #FB4934
cursor_text_color       #282828

color0  #3C3836
color8  #928374
color1  #FB4934
color9  #FB4934
color2  #B8BB26
color10 #B8BB26
color3  #FABD2F
color11 #FABD2F
color4  #83A598
color12 #83A598
color5  #D3869B
color13 #D3869B
color6  #8EC07C
color14 #8EC07C
color7  #EBDBB2
color15 #FBF1C7
EOF
cat > "$CONF/kitty/themes/classic-square.conf" <<'EOF'
foreground              #EBDBB2
background              #282828
selection_foreground    #282828
selection_background    #EBDBB2
cursor                  #FE8019
cursor_text_color       #282828

color0  #3C3836
color8  #928374
color1  #FB4934
color9  #FB4934
color2  #B8BB26
color10 #B8BB26
color3  #FABD2F
color11 #FABD2F
color4  #83A598
color12 #83A598
color5  #D3869B
color13 #D3869B
color6  #8EC07C
color14 #8EC07C
color7  #EBDBB2
color15 #FBF1C7
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

cat > "$CONF/kitty/themes/tobi-square.conf" <<'EOF'
foreground              #D9E0EE
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #D9E0EE
cursor                  #62B4F9
cursor_text_color       #1E1E2E

color0  #181825
color8  #6E6C7E
color1  #F28FAD
color9  #F88D96
color2  #ABE9B3
color10 #ABE9B3
color3  #FAE3B0
color11 #FAE3B0
color4  #62B4F9
color12 #96CDFB
color5  #F5C2E7
color13 #F5C2E7
color6  #89DCEB
color14 #89DCEB
color7  #D9E0EE
color15 #FFFFFF
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
cat > "$CONF/kitty/themes/yucklys-square.conf" <<'EOF'
foreground              #D8DEE9
background              #2E3440
selection_foreground    #2E3440
selection_background    #D8DEE9
cursor                  #81A1C1
cursor_text_color       #2E3440

color0  #3B4252
color8  #4C566A
color1  #BF616A
color9  #BF616A
color2  #A3BE8C
color10 #A3BE8C
color3  #EBCB8B
color11 #EBCB8B
color4  #81A1C1
color12 #81A1C1
color5  #B48EAD
color13 #B48EAD
color6  #88C0D0
color14 #8FBCBB
color7  #D8DEE9
color15 #ECEFF4
EOF
cat > "$CONF/kitty/themes/yucklys-light-square.conf" <<'EOF'
foreground              #2E3440
background              #ECEFF4
selection_foreground    #ECEFF4
selection_background    #2E3440
cursor                  #496F95
cursor_text_color       #ECEFF4

color0  #E5E9F0
color8  #3B4252
color1  #B54954
color9  #B54954
color2  #597442
color10 #597442
color3  #8D6618
color11 #8D6618
color4  #496F95
color12 #496F95
color5  #8C5D83
color13 #8C5D83
color6  #357587
color14 #457473
color7  #2E3440
color15 #2E3440
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
# 6f. i3 border-color theming - matches window border/title colors to
#     whichever desktop theme is active, the same way kitty/rofi/dunst
#     already do. i3 has no equivalent of kitty's `set-colors` remote-
#     control push, so unlike kitty this can't retint already-open windows
#     live - polybar-theme.sh instead runs a plain `i3-msg reload` after
#     swapping the file, which re-reads client.* for every window
#     immediately (existing windows/layout are untouched by a reload,
#     unlike `i3-msg restart`).
#
#     Colors are derived from each theme's own already-generated kitty
#     palette (background/foreground/cursor/color1/7/8), the same
#     derive-from-kitty's-resolved-colors approach the starship section
#     below already uses: cursor doubles as the accent for the focused
#     border/indicator, color8 (bright black) for unfocused/inactive
#     borders, color1 (red) for urgent. catppuccin-mocha keeps its
#     original hand-picked scheme (mauve/surface0/surface1/red) instead of
#     the generic derivation, since that one predates this per-theme setup
#     and was tuned on its own.
# ----------------------------------------------------------------------------
log "Writing per-theme i3 border-color configs..."
mkdir -p "$CONF/i3/themes"

cat > "$CONF/i3/themes/aline.conf" <<'EOF'
client.focused          #2e5d66  #faf4ed  #575279  #2e5d66   #2e5d66
client.unfocused        #9893a5  #faf4ed  #9893a5  #9893a5   #9893a5
client.focused_inactive #9893a5  #faf4ed  #9893a5  #9893a5   #9893a5
client.urgent           #b4637a  #faf4ed  #575279  #b4637a   #b4637a
EOF

cat > "$CONF/i3/themes/alireza.conf" <<'EOF'
client.focused          #BD93F9  #BD93F9  #F8F8F2  #F8F8F2   #BD93F9
client.unfocused        #282A36  #282A36  #938BFF  #44475A   #282A36
client.focused_inactive #282A36  #282A36  #938BFF  #44475A   #282A36
client.urgent           #FF5E76  #FF5E76  #F8F8F2  #8BE9FD   #FF5E76
EOF

cat > "$CONF/i3/themes/archblur.conf" <<'EOF'
client.focused          #FE8019  #FE8019  #282828  #FE8019   #FE8019
client.unfocused        #3C3836  #282828  #EBDBB2  #3C3836   #3C3836
client.focused_inactive #3C3836  #282828  #EBDBB2  #3C3836   #3C3836
client.urgent           #FB4934  #FB4934  #282828  #FB4934   #FB4934
EOF

cat > "$CONF/i3/themes/archcraft.conf" <<'EOF'
client.focused          #da6e89  #da6e89  #1e222a  #98c379   #da6e89
client.focused_inactive #61afef  #61afef  #1e222a  #98c379   #61afef
client.unfocused        #292e39  #292e39  #c8ccd4  #98c379   #292e39
client.urgent           #c678dd  #c678dd  #c8ccd4  #98c379   #c678dd
EOF

cat > "$CONF/i3/themes/breddie.conf" <<'EOF'
client.focused          #ACB0D0  #ACB0D0  #1A1B26  #ACB0D0   #ACB0D0
client.unfocused        #444B61  #1A1B26  #E5E9F0  #444B61   #444B61
client.focused_inactive #444B61  #1A1B26  #E5E9F0  #444B61   #444B61
client.urgent           #F7768E  #F7768E  #1A1B26  #F7768E   #F7768E
EOF

cat > "$CONF/i3/themes/brenda.conf" <<'EOF'
client.focused          #e69875  #2d353b  #d3c6aa  #e69875   #e69875
client.unfocused        #859289  #2d353b  #859289  #859289   #859289
client.focused_inactive #859289  #2d353b  #859289  #859289   #859289
client.urgent           #e67e80  #2d353b  #d3c6aa  #e67e80   #e67e80
EOF

cat > "$CONF/i3/themes/catppuccin-mocha.conf" <<'EOF'
client.focused          #cba6f7  #1e1e2e  #cdd6f4  #cba6f7   #cba6f7
client.unfocused        #313244  #1e1e2e  #6c7086  #313244   #313244
client.focused_inactive #45475a  #1e1e2e  #a6adc8  #45475a   #45475a
client.urgent           #f38ba8  #1e1e2e  #f38ba8  #f38ba8   #f38ba8
EOF

cat > "$CONF/i3/themes/cherryblocks.conf" <<'EOF'
client.focused          #FB4934  #FB4934  #282828  #FB4934   #FB4934
client.unfocused        #3C3836  #282828  #EBDBB2  #3C3836   #3C3836
client.focused_inactive #3C3836  #282828  #EBDBB2  #3C3836   #3C3836
client.urgent           #FB4934  #FB4934  #282828  #FB4934   #FB4934
EOF
cat > "$CONF/i3/themes/classic.conf" <<'EOF'
client.focused          #FE8019  #FE8019  #282828  #FE8019   #FE8019
client.unfocused        #3C3836  #282828  #EBDBB2  #3C3836   #3C3836
client.focused_inactive #3C3836  #282828  #EBDBB2  #3C3836   #3C3836
client.urgent           #FB4934  #FB4934  #282828  #FB4934   #FB4934
EOF

cat > "$CONF/i3/themes/cristina.conf" <<'EOF'
client.focused          #8ec07c  #232136  #e0def4  #8ec07c   #8ec07c
client.unfocused        #908caa  #232136  #908caa  #908caa   #908caa
client.focused_inactive #908caa  #232136  #908caa  #908caa   #908caa
client.urgent           #ea6f91  #232136  #e0def4  #ea6f91   #ea6f91
EOF

cat > "$CONF/i3/themes/cynthia.conf" <<'EOF'
client.focused          #7fb4ca  #181616  #c5c9c5  #7fb4ca   #7fb4ca
client.unfocused        #708491  #181616  #708491  #708491   #708491
client.focused_inactive #708491  #181616  #708491  #708491   #708491
client.urgent           #e46876  #181616  #c5c9c5  #e46876   #e46876
EOF

cat > "$CONF/i3/themes/daniela.conf" <<'EOF'
client.focused          #7aa2f7  #1a1b26  #c0caf5  #7aa2f7   #7aa2f7
client.unfocused        #565f89  #1a1b26  #565f89  #565f89   #565f89
client.focused_inactive #565f89  #1a1b26  #565f89  #565f89   #565f89
client.urgent           #f7768e  #1a1b26  #c0caf5  #f7768e   #f7768e
EOF

cat > "$CONF/i3/themes/dracula.conf" <<'EOF'
client.focused          #6272a4  #6272a4  #f8f8f2  #6272a4   #6272a4
client.focused_inactive #44475a  #44475a  #f8f8f2  #44475a   #44475a
client.unfocused        #282a36  #282a36  #bfbfbf  #282a36   #282a36
client.urgent           #44475a  #ff5555  #f8f8f2  #ff5555   #ff5555
EOF

cat > "$CONF/i3/themes/emilia.conf" <<'EOF'
client.focused          #e0a458  #1e1a17  #e8dcc8  #e0a458   #e0a458
client.unfocused        #9c8f7d  #1e1a17  #9c8f7d  #9c8f7d   #9c8f7d
client.focused_inactive #9c8f7d  #1e1a17  #9c8f7d  #9c8f7d   #9c8f7d
client.urgent           #d9736a  #1e1a17  #e8dcc8  #d9736a   #d9736a
EOF

cat > "$CONF/i3/themes/h4ck3r.conf" <<'EOF'
client.focused          #76ea00  #0c1018  #00fa5c  #76ea00   #76ea00
client.unfocused        #578a29  #0c1018  #578a29  #578a29   #578a29
client.focused_inactive #578a29  #0c1018  #578a29  #578a29   #578a29
client.urgent           #6dde00  #0c1018  #00fa5c  #6dde00   #6dde00
EOF

cat > "$CONF/i3/themes/isabel.conf" <<'EOF'
client.focused          #4fd6be  #10181a  #a8c5c0  #4fd6be   #4fd6be
client.unfocused        #5c7b76  #10181a  #5c7b76  #5c7b76   #5c7b76
client.focused_inactive #5c7b76  #10181a  #5c7b76  #5c7b76   #5c7b76
client.urgent           #d67f7f  #10181a  #a8c5c0  #d67f7f   #d67f7f
EOF

cat > "$CONF/i3/themes/jan.conf" <<'EOF'
client.focused          #fb007a  #212a4c  #27fbfe  #fb007a   #fb007a
client.unfocused        #6b7bb0  #212a4c  #6b7bb0  #6b7bb0   #6b7bb0
client.focused_inactive #6b7bb0  #212a4c  #6b7bb0  #6b7bb0   #6b7bb0
client.urgent           #fb007a  #212a4c  #27fbfe  #fb007a   #fb007a
EOF

cat > "$CONF/i3/themes/karla.conf" <<'EOF'
client.focused          #f05393  #0e1113  #afb1db  #f05393   #f05393
client.unfocused        #6272a4  #0e1113  #6272a4  #6272a4   #6272a4
client.focused_inactive #6272a4  #0e1113  #6272a4  #6272a4   #6272a4
client.urgent           #e7034a  #0e1113  #afb1db  #e7034a   #e7034a
EOF

cat > "$CONF/i3/themes/marisol.conf" <<'EOF'
client.focused          #e8b84c  #241c1c  #f5e6e0  #e8b84c   #e8b84c
client.unfocused        #a8827c  #241c1c  #a8827c  #a8827c   #a8827c
client.focused_inactive #a8827c  #241c1c  #a8827c  #a8827c   #a8827c
client.urgent           #e8604c  #241c1c  #f5e6e0  #e8604c   #e8604c
EOF

cat > "$CONF/i3/themes/nord.conf" <<'EOF'
client.focused          #b48ead  #2e3440  #eceff4  #b48ead   #b48ead
client.unfocused        #d8dee9  #2e3440  #d8dee9  #d8dee9   #d8dee9
client.focused_inactive #d8dee9  #2e3440  #d8dee9  #d8dee9   #d8dee9
client.urgent           #bf616a  #2e3440  #eceff4  #bf616a   #bf616a
EOF

cat > "$CONF/i3/themes/pamela.conf" <<'EOF'
client.focused          #f2a272  #1d1f28  #fdfdfd  #f2a272   #f2a272
client.unfocused        #8c8c8c  #1d1f28  #8c8c8c  #8c8c8c   #8c8c8c
client.focused_inactive #8c8c8c  #1d1f28  #8c8c8c  #8c8c8c   #8c8c8c
client.urgent           #f37f97  #1d1f28  #fdfdfd  #f37f97   #f37f97
EOF

cat > "$CONF/i3/themes/silvia.conf" <<'EOF'
client.focused          #8ec07c  #3c3836  #ebdbb2  #8ec07c   #8ec07c
client.unfocused        #928374  #3c3836  #928374  #928374   #928374
client.focused_inactive #928374  #3c3836  #928374  #928374   #928374
client.urgent           #cc241d  #3c3836  #ebdbb2  #cc241d   #cc241d
EOF

cat > "$CONF/i3/themes/tobi.conf" <<'EOF'
client.focused          #62B4F9  #62B4F9  #FFFFFF  #62B4F9   #62B4F9
client.unfocused        #313244  #1E1E2E  #D9E0EE  #313244   #313244
client.focused_inactive #313244  #1E1E2E  #D9E0EE  #313244   #313244
client.urgent           #F28FAD  #F28FAD  #FFFFFF  #F28FAD   #F28FAD
EOF

cat > "$CONF/i3/themes/varinka.conf" <<'EOF'
client.focused          #dc5bbc  #212529  #f8f9fa  #dc5bbc   #dc5bbc
client.unfocused        #6c757d  #212529  #6c757d  #6c757d   #6c757d
client.focused_inactive #6c757d  #212529  #6c757d  #6c757d   #6c757d
client.urgent           #dc5bbc  #212529  #f8f9fa  #dc5bbc   #dc5bbc
EOF

cat > "$CONF/i3/themes/yael.conf" <<'EOF'
client.focused          #33b1ff  #161616  #ffffff  #33b1ff   #33b1ff
client.unfocused        #8c8c8c  #161616  #8c8c8c  #8c8c8c   #8c8c8c
client.focused_inactive #8c8c8c  #161616  #8c8c8c  #8c8c8c   #8c8c8c
client.urgent           #ee5396  #161616  #ffffff  #ee5396   #ee5396
EOF
cat > "$CONF/i3/themes/yucklys.conf" <<'EOF'
client.focused          #8FBCBB  #2E3440  #D8DEE9  #8FBCBB   #8FBCBB
client.unfocused        #D8DEE9  #2E3440  #D8DEE9  #D8DEE9   #D8DEE9
client.focused_inactive #D8DEE9  #2E3440  #D8DEE9  #D8DEE9   #D8DEE9
client.urgent           #BF616A  #2E3440  #D8DEE9  #BF616A   #BF616A
EOF
cat > "$CONF/i3/themes/yucklys-light.conf" <<'EOF'
client.focused          #457473  #ECEFF4  #2E3440  #457473   #457473
client.unfocused        #2E3440  #ECEFF4  #2E3440  #2E3440   #2E3440
client.focused_inactive #2E3440  #ECEFF4  #2E3440  #2E3440   #2E3440
client.urgent           #B54954  #ECEFF4  #2E3440  #B54954   #B54954
EOF

cat > "$CONF/i3/themes/z0mbi3.conf" <<'EOF'
client.focused          #86aaec  #0d0f18  #a5b6cf  #86aaec   #86aaec
client.unfocused        #6e8db4  #0d0f18  #6e8db4  #6e8db4   #6e8db4
client.focused_inactive #6e8db4  #0d0f18  #6e8db4  #6e8db4   #6e8db4
client.urgent           #dd6777  #0d0f18  #a5b6cf  #dd6777   #dd6777
EOF

cp "$CONF/i3/themes/catppuccin-mocha.conf" "$CONF/i3/current-borders.conf"

# ----------------------------------------------------------------------------
# 6g. Starship prompt theming - matches the shell prompt (powerline segments)
#     to whichever desktop theme is active, the same way kitty/rofi already
#     do. Only relevant if Chris Titus mybash (installed by the separate
#     post-install-fedora.sh script, not this one) is actually in use - its
#     setup.sh points ~/.config/starship.toml at a fixed Nord-colored config
#     via a symlink into ~/.local/share/mybash/starship.toml, completely
#     independent of kitty's own ANSI palette, which is exactly why
#     switching desktop themes never used to touch the prompt at all.
#
#     Colors are derived from each theme's own already-generated kitty
#     palette (color0/4/5/6/8 - reusing resolved colors instead of a third
#     copy of every accent-fallback chain): the format string's six segment
#     colors are the base background lightened (or, on aline, the one light
#     theme, darkened - confirmed via each color's own relative luminance,
#     not assumed dark) in three steps for the neutral username/directory/
#     git segments, then that theme's own cyan/magenta/blue accents for the
#     language-icon/docker/time segments - the same six-color escalating
#     progression the original Nord-based config already used, just re-
#     derived per theme instead of fixed.
#
#     Written unconditionally, like the Jabra/MX-Anywhere hardware fixes
#     elsewhere in this script - harmless if mybash/starship was never
#     installed (the files just sit unused), ready the moment it is.
# ----------------------------------------------------------------------------
log "Writing per-theme starship prompt configs..."
mkdir -p "$CONF/starship/themes"

cat > "$CONF/starship/themes/aline.toml" <<'EOF'
format = """
[](#FAF4ED)\
$python\
$username\
[](bg:#DCD7D1 fg:#FAF4ED)\
$directory\
[](fg:#DCD7D1 bg:#BEB9B4)\
$git_branch\
$git_status\
[](fg:#BEB9B4 bg:#2E7480)\
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
[](fg:#2E7480 bg:#2E5D66)\
$docker_context\
[](fg:#2E5D66 bg:#2E5D66)\
$time\
[ ](fg:#2E5D66)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#FAF4ED"
style_root = "bg:#FAF4ED"
format = '[$user ]($style)'

[directory]
style = "bg:#DCD7D1"
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
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#2E5D66"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#BEB9B4"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#BEB9B4"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#FAF4ED"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#2E5D66"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/aline-square.toml" <<'EOF'
format = """
[](#FAF4ED)\
$python\
$username\
[](bg:#DCD7D1 fg:#FAF4ED)\
$directory\
[](fg:#DCD7D1 bg:#BEB9B4)\
$git_branch\
$git_status\
[](fg:#BEB9B4 bg:#2E7480)\
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
[](fg:#2E7480 bg:#2E5D66)\
$docker_context\
[](fg:#2E5D66 bg:#2E5D66)\
$time\
[ ](fg:#2E5D66)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#FAF4ED"
style_root = "bg:#FAF4ED"
format = '[$user ]($style)'

[directory]
style = "bg:#DCD7D1"
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
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#2E5D66"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#BEB9B4"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#BEB9B4"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#FAF4ED"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#2E7480"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#2E5D66"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/alireza.toml" <<'EOF'
format = """
[](#282A36)\
$python\
$username\
[](bg:#383A4A fg:#282A36)\
$directory\
[](fg:#383A4A bg:#44475A)\
$git_branch\
$git_status\
[](fg:#44475A bg:#8BE9FD)\
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
[](fg:#8BE9FD bg:#BD93F9)\
$docker_context\
[](fg:#BD93F9 bg:#FF79C6)\
$time\
[ ](fg:#FF79C6)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#282A36"
style_root = "bg:#282A36"
format = '[$user ]($style)'

[directory]
style = "bg:#383A4A"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = "  "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important  " = "  "

[c]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BD93F9"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#44475A"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#44475A"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282A36"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#FF79C6"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/archblur.toml" <<'EOF'
format = """
[](#282828)\
$python\
$username\
[](bg:#3C3836 fg:#282828)\
$directory\
[](fg:#3C3836 bg:#504945)\
$git_branch\
$git_status\
[](fg:#504945 bg:#FE8019)\
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
[](fg:#FE8019 bg:#B8BB26)\
$docker_context\
[](fg:#B8BB26 bg:#FABD2F)\
$time\
[ ](fg:#FABD2F)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

[username]
show_always = true
style_user = "bg:#282828"
style_root = "bg:#282828"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3836"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B8BB26"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#504945"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#504945"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282828"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#FABD2F"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/archcraft.toml" <<'EOF'
format = """
[](#1E222A)\
$python\
$username\
[](bg:#393D44 fg:#1E222A)\
$directory\
[](fg:#393D44 bg:#54575D)\
$git_branch\
$git_status\
[](fg:#54575D bg:#56B6C2)\
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
[](fg:#56B6C2 bg:#C678DD)\
$docker_context\
[](fg:#C678DD bg:#61AFEF)\
$time\
[ ](fg:#61AFEF)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E222A"
style_root = "bg:#1E222A"
format = '[$user ]($style)'

[directory]
style = "bg:#393D44"
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
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C678DD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#54575D"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#54575D"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E222A"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#61AFEF"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/alireza-square.toml" <<'EOF'
format = """
[](#282A36)\
$python\
$username\
[](bg:#383A4A fg:#282A36)\
$directory\
[](fg:#383A4A bg:#44475A)\
$git_branch\
$git_status\
[](fg:#44475A bg:#8BE9FD)\
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
[](fg:#8BE9FD bg:#BD93F9)\
$docker_context\
[](fg:#BD93F9 bg:#FF79C6)\
$time\
[ ](fg:#FF79C6)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#282A36"
style_root = "bg:#282A36"
format = '[$user ]($style)'

[directory]
style = "bg:#383A4A"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = "  "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important  " = "  "

[c]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BD93F9"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#44475A"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#44475A"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282A36"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#FF79C6"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/archblur-square.toml" <<'EOF'
format = """
[](#282828)\
$python\
$username\
[](bg:#3C3836 fg:#282828)\
$directory\
[](fg:#3C3836 bg:#504945)\
$git_branch\
$git_status\
[](fg:#504945 bg:#FE8019)\
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
[](fg:#FE8019 bg:#B8BB26)\
$docker_context\
[](fg:#B8BB26 bg:#FABD2F)\
$time\
[ ](fg:#FABD2F)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

[username]
show_always = true
style_user = "bg:#282828"
style_root = "bg:#282828"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3836"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B8BB26"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#504945"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#504945"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282828"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#FABD2F"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/archcraft-square.toml" <<'EOF'
format = """
[](#1E222A)\
$python\
$username\
[](bg:#393D44 fg:#1E222A)\
$directory\
[](fg:#393D44 bg:#54575D)\
$git_branch\
$git_status\
[](fg:#54575D bg:#56B6C2)\
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
[](fg:#56B6C2 bg:#C678DD)\
$docker_context\
[](fg:#C678DD bg:#61AFEF)\
$time\
[ ](fg:#61AFEF)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E222A"
style_root = "bg:#1E222A"
format = '[$user ]($style)'

[directory]
style = "bg:#393D44"
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
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C678DD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#54575D"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#54575D"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E222A"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#56B6C2"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#61AFEF"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/breddie.toml" <<'EOF'
format = """
[](#1A1B26)\
$python\
$username\
[](bg:#292A44 fg:#1A1B26)\
$directory\
[](fg:#292A44 bg:#444B61)\
$git_branch\
$git_status\
[](fg:#444B61 bg:#7AA2F7)\
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
[](fg:#7AA2F7 bg:#BB9AF7)\
$docker_context\
[](fg:#BB9AF7 bg:#EBCB8C)\
$time\
[ ](fg:#EBCB8C)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1A1B26"
style_root = "bg:#1A1B26"
format = '[$user ]($style)'

[directory]
style = "bg:#292A44"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = "  "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important  " = "  "

[c]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BB9AF7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#444B61"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#444B61"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1A1B26"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#EBCB8C"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/brenda.toml" <<'EOF'
format = """
[](#2D353B)\
$python\
$username\
[](bg:#464D53 fg:#2D353B)\
$directory\
[](fg:#464D53 bg:#5F656A)\
$git_branch\
$git_status\
[](fg:#5F656A bg:#B9C244)\
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
[](fg:#B9C244 bg:#D699B6)\
$docker_context\
[](fg:#D699B6 bg:#7FBBB3)\
$time\
[ ](fg:#7FBBB3)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#2D353B"
style_root = "bg:#2D353B"
format = '[$user ]($style)'

[directory]
style = "bg:#464D53"
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
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#D699B6"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#5F656A"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#5F656A"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#2D353B"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7FBBB3"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/breddie-square.toml" <<'EOF'
format = """
[](#1A1B26)\
$python\
$username\
[](bg:#292A44 fg:#1A1B26)\
$directory\
[](fg:#292A44 bg:#444B61)\
$git_branch\
$git_status\
[](fg:#444B61 bg:#7AA2F7)\
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
[](fg:#7AA2F7 bg:#BB9AF7)\
$docker_context\
[](fg:#BB9AF7 bg:#EBCB8C)\
$time\
[ ](fg:#EBCB8C)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1A1B26"
style_root = "bg:#1A1B26"
format = '[$user ]($style)'

[directory]
style = "bg:#292A44"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = "  "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important  " = "  "

[c]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BB9AF7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#444B61"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#444B61"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1A1B26"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7AA2F7"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#EBCB8C"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/brenda-square.toml" <<'EOF'
format = """
[](#2D353B)\
$python\
$username\
[](bg:#464D53 fg:#2D353B)\
$directory\
[](fg:#464D53 bg:#5F656A)\
$git_branch\
$git_status\
[](fg:#5F656A bg:#B9C244)\
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
[](fg:#B9C244 bg:#D699B6)\
$docker_context\
[](fg:#D699B6 bg:#7FBBB3)\
$time\
[ ](fg:#7FBBB3)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#2D353B"
style_root = "bg:#2D353B"
format = '[$user ]($style)'

[directory]
style = "bg:#464D53"
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
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#D699B6"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#5F656A"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#5F656A"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#2D353B"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#B9C244"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7FBBB3"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/catppuccin-mocha.toml" <<'EOF'
format = """
[](#1E1E2E)\
$python\
$username\
[](bg:#393947 fg:#1E1E2E)\
$directory\
[](fg:#393947 bg:#545460)\
$git_branch\
$git_status\
[](fg:#545460 bg:#94E2D5)\
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
[](fg:#94E2D5 bg:#F5C2E7)\
$docker_context\
[](fg:#F5C2E7 bg:#89B4FA)\
$time\
[ ](fg:#89B4FA)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E1E2E"
style_root = "bg:#1E1E2E"
format = '[$user ]($style)'

[directory]
style = "bg:#393947"
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
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#F5C2E7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#545460"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#545460"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E1E2E"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#89B4FA"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/catppuccin-mocha-square.toml" <<'EOF'
format = """
[](#1E1E2E)\
$python\
$username\
[](bg:#393947 fg:#1E1E2E)\
$directory\
[](fg:#393947 bg:#545460)\
$git_branch\
$git_status\
[](fg:#545460 bg:#94E2D5)\
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
[](fg:#94E2D5 bg:#F5C2E7)\
$docker_context\
[](fg:#F5C2E7 bg:#89B4FA)\
$time\
[ ](fg:#89B4FA)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E1E2E"
style_root = "bg:#1E1E2E"
format = '[$user ]($style)'

[directory]
style = "bg:#393947"
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
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#F5C2E7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#545460"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#545460"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E1E2E"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#94E2D5"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#89B4FA"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/cherryblocks.toml" <<'EOF'
format = """
[](#282828)\
$python\
$username\
[](bg:#3C3836 fg:#282828)\
$directory\
[](fg:#3C3836 bg:#504945)\
$git_branch\
$git_status\
[](fg:#504945 bg:#FB4934)\
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
[](fg:#FB4934 bg:#B8BB26)\
$docker_context\
[](fg:#B8BB26 bg:#FABD2F)\
$time\
[ ](fg:#FABD2F)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

[username]
show_always = true
style_user = "bg:#282828"
style_root = "bg:#282828"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3836"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B8BB26"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#504945"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#504945"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282828"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#FABD2F"
format = '[ $time ]($style)'
EOF
cat > "$CONF/starship/themes/classic.toml" <<'EOF'
format = """
[](#282828)\
$python\
$username\
[](bg:#3C3836 fg:#282828)\
$directory\
[](fg:#3C3836 bg:#504945)\
$git_branch\
$git_status\
[](fg:#504945 bg:#FE8019)\
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
[](fg:#FE8019 bg:#B8BB26)\
$docker_context\
[](fg:#B8BB26 bg:#FABD2F)\
$time\
[ ](fg:#FABD2F)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

[username]
show_always = true
style_user = "bg:#282828"
style_root = "bg:#282828"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3836"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B8BB26"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#504945"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#504945"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282828"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#FABD2F"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/cristina.toml" <<'EOF'
format = """
[](#232136)\
$python\
$username\
[](bg:#3D3C4E fg:#232136)\
$directory\
[](fg:#3D3C4E bg:#585666)\
$git_branch\
$git_status\
[](fg:#585666 bg:#8EC07C)\
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
[](fg:#8EC07C bg:#C3A5E6)\
$docker_context\
[](fg:#C3A5E6 bg:#34738E)\
$time\
[ ](fg:#34738E)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#232136"
style_root = "bg:#232136"
format = '[$user ]($style)'

[directory]
style = "bg:#3D3C4E"
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
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C3A5E6"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#585666"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#585666"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#232136"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#34738E"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/cherryblocks-square.toml" <<'EOF'
format = """
[](#282828)\
$python\
$username\
[](bg:#3C3836 fg:#282828)\
$directory\
[](fg:#3C3836 bg:#504945)\
$git_branch\
$git_status\
[](fg:#504945 bg:#FB4934)\
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
[](fg:#FB4934 bg:#B8BB26)\
$docker_context\
[](fg:#B8BB26 bg:#FABD2F)\
$time\
[ ](fg:#FABD2F)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

[username]
show_always = true
style_user = "bg:#282828"
style_root = "bg:#282828"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3836"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B8BB26"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#504945"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#504945"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282828"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#FB4934"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#FABD2F"
format = '[ $time ]($style)'
EOF
cat > "$CONF/starship/themes/classic-square.toml" <<'EOF'
format = """
[](#282828)\
$python\
$username\
[](bg:#3C3836 fg:#282828)\
$directory\
[](fg:#3C3836 bg:#504945)\
$git_branch\
$git_status\
[](fg:#504945 bg:#FE8019)\
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
[](fg:#FE8019 bg:#B8BB26)\
$docker_context\
[](fg:#B8BB26 bg:#FABD2F)\
$time\
[ ](fg:#FABD2F)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

[username]
show_always = true
style_user = "bg:#282828"
style_root = "bg:#282828"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3836"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B8BB26"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#504945"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#504945"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282828"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#FE8019"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#FABD2F"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/cristina-square.toml" <<'EOF'
format = """
[](#232136)\
$python\
$username\
[](bg:#3D3C4E fg:#232136)\
$directory\
[](fg:#3D3C4E bg:#585666)\
$git_branch\
$git_status\
[](fg:#585666 bg:#8EC07C)\
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
[](fg:#8EC07C bg:#C3A5E6)\
$docker_context\
[](fg:#C3A5E6 bg:#34738E)\
$time\
[ ](fg:#34738E)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#232136"
style_root = "bg:#232136"
format = '[$user ]($style)'

[directory]
style = "bg:#3D3C4E"
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
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C3A5E6"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#585666"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#585666"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#232136"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8EC07C"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#34738E"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/cynthia.toml" <<'EOF'
format = """
[](#181616)\
$python\
$username\
[](bg:#343232 fg:#181616)\
$directory\
[](fg:#343232 bg:#4F4E4E)\
$git_branch\
$git_status\
[](fg:#4F4E4E bg:#7FB4CA)\
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
[](fg:#7FB4CA bg:#938AA9)\
$docker_context\
[](fg:#938AA9 bg:#7FB4CA)\
$time\
[ ](fg:#7FB4CA)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#181616"
style_root = "bg:#181616"
format = '[$user ]($style)'

[directory]
style = "bg:#343232"
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
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#938AA9"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#4F4E4E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#4F4E4E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#181616"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7FB4CA"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/cynthia-square.toml" <<'EOF'
format = """
[](#181616)\
$python\
$username\
[](bg:#343232 fg:#181616)\
$directory\
[](fg:#343232 bg:#4F4E4E)\
$git_branch\
$git_status\
[](fg:#4F4E4E bg:#7FB4CA)\
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
[](fg:#7FB4CA bg:#938AA9)\
$docker_context\
[](fg:#938AA9 bg:#7FB4CA)\
$time\
[ ](fg:#7FB4CA)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#181616"
style_root = "bg:#181616"
format = '[$user ]($style)'

[directory]
style = "bg:#343232"
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
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#938AA9"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#4F4E4E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#4F4E4E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#181616"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7FB4CA"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7FB4CA"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/daniela.toml" <<'EOF'
format = """
[](#1A1B26)\
$python\
$username\
[](bg:#353640 fg:#1A1B26)\
$directory\
[](fg:#353640 bg:#51525A)\
$git_branch\
$git_status\
[](fg:#51525A bg:#7DCFFF)\
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
[](fg:#7DCFFF bg:#BB9AF7)\
$docker_context\
[](fg:#BB9AF7 bg:#7AA2F7)\
$time\
[ ](fg:#7AA2F7)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1A1B26"
style_root = "bg:#1A1B26"
format = '[$user ]($style)'

[directory]
style = "bg:#353640"
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
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BB9AF7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#51525A"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#51525A"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1A1B26"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7AA2F7"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/daniela-square.toml" <<'EOF'
format = """
[](#1A1B26)\
$python\
$username\
[](bg:#353640 fg:#1A1B26)\
$directory\
[](fg:#353640 bg:#51525A)\
$git_branch\
$git_status\
[](fg:#51525A bg:#7DCFFF)\
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
[](fg:#7DCFFF bg:#BB9AF7)\
$docker_context\
[](fg:#BB9AF7 bg:#7AA2F7)\
$time\
[ ](fg:#7AA2F7)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1A1B26"
style_root = "bg:#1A1B26"
format = '[$user ]($style)'

[directory]
style = "bg:#353640"
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
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BB9AF7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#51525A"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#51525A"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1A1B26"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7DCFFF"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7AA2F7"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/dracula.toml" <<'EOF'
format = """
[](#282A36)\
$python\
$username\
[](bg:#42444E fg:#282A36)\
$directory\
[](fg:#42444E bg:#5C5D66)\
$git_branch\
$git_status\
[](fg:#5C5D66 bg:#8BE9FD)\
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
[](fg:#8BE9FD bg:#BD93F9)\
$docker_context\
[](fg:#BD93F9 bg:#6272A4)\
$time\
[ ](fg:#6272A4)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#282A36"
style_root = "bg:#282A36"
format = '[$user ]($style)'

[directory]
style = "bg:#42444E"
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
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BD93F9"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#5C5D66"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#5C5D66"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282A36"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#6272A4"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/dracula-square.toml" <<'EOF'
format = """
[](#282A36)\
$python\
$username\
[](bg:#42444E fg:#282A36)\
$directory\
[](fg:#42444E bg:#5C5D66)\
$git_branch\
$git_status\
[](fg:#5C5D66 bg:#8BE9FD)\
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
[](fg:#8BE9FD bg:#BD93F9)\
$docker_context\
[](fg:#BD93F9 bg:#6272A4)\
$time\
[ ](fg:#6272A4)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#282A36"
style_root = "bg:#282A36"
format = '[$user ]($style)'

[directory]
style = "bg:#42444E"
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
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#BD93F9"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#5C5D66"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#5C5D66"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#282A36"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8BE9FD"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#6272A4"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/emilia.toml" <<'EOF'
format = """
[](#1E1A17)\
$python\
$username\
[](bg:#393533 fg:#1E1A17)\
$directory\
[](fg:#393533 bg:#54514F)\
$git_branch\
$git_status\
[](fg:#54514F bg:#7FA5B5)\
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
[](fg:#7FA5B5 bg:#B08BBB)\
$docker_context\
[](fg:#B08BBB bg:#7FA5B5)\
$time\
[ ](fg:#7FA5B5)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E1A17"
style_root = "bg:#1E1A17"
format = '[$user ]($style)'

[directory]
style = "bg:#393533"
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
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B08BBB"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#54514F"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#54514F"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E1A17"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7FA5B5"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/emilia-square.toml" <<'EOF'
format = """
[](#1E1A17)\
$python\
$username\
[](bg:#393533 fg:#1E1A17)\
$directory\
[](fg:#393533 bg:#54514F)\
$git_branch\
$git_status\
[](fg:#54514F bg:#7FA5B5)\
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
[](fg:#7FA5B5 bg:#B08BBB)\
$docker_context\
[](fg:#B08BBB bg:#7FA5B5)\
$time\
[ ](fg:#7FA5B5)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E1A17"
style_root = "bg:#1E1A17"
format = '[$user ]($style)'

[directory]
style = "bg:#393533"
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
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B08BBB"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#54514F"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#54514F"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E1A17"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7FA5B5"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#7FA5B5"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/h4ck3r.toml" <<'EOF'
format = """
[](#0C1018)\
$python\
$username\
[](bg:#292D34 fg:#0C1018)\
$directory\
[](fg:#292D34 bg:#46494F)\
$git_branch\
$git_status\
[](fg:#46494F bg:#9CF542)\
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
[](fg:#9CF542 bg:#00FA5C)\
$docker_context\
[](fg:#00FA5C bg:#9CF542)\
$time\
[ ](fg:#9CF542)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#0C1018"
style_root = "bg:#0C1018"
format = '[$user ]($style)'

[directory]
style = "bg:#292D34"
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
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#00FA5C"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#46494F"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#46494F"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#0C1018"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#9CF542"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/h4ck3r-square.toml" <<'EOF'
format = """
[](#0C1018)\
$python\
$username\
[](bg:#292D34 fg:#0C1018)\
$directory\
[](fg:#292D34 bg:#46494F)\
$git_branch\
$git_status\
[](fg:#46494F bg:#9CF542)\
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
[](fg:#9CF542 bg:#00FA5C)\
$docker_context\
[](fg:#00FA5C bg:#9CF542)\
$time\
[ ](fg:#9CF542)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#0C1018"
style_root = "bg:#0C1018"
format = '[$user ]($style)'

[directory]
style = "bg:#292D34"
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
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#00FA5C"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#46494F"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#46494F"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#0C1018"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#9CF542"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#9CF542"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/isabel.toml" <<'EOF'
format = """
[](#10181A)\
$python\
$username\
[](bg:#2D3435 fg:#10181A)\
$directory\
[](fg:#2D3435 bg:#494F51)\
$git_branch\
$git_status\
[](fg:#494F51 bg:#4FD6BE)\
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
[](fg:#4FD6BE bg:#5FA8C7)\
$docker_context\
[](fg:#5FA8C7 bg:#5FA8C7)\
$time\
[ ](fg:#5FA8C7)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#10181A"
style_root = "bg:#10181A"
format = '[$user ]($style)'

[directory]
style = "bg:#2D3435"
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
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#5FA8C7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#494F51"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#494F51"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#10181A"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#5FA8C7"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/isabel-square.toml" <<'EOF'
format = """
[](#10181A)\
$python\
$username\
[](bg:#2D3435 fg:#10181A)\
$directory\
[](fg:#2D3435 bg:#494F51)\
$git_branch\
$git_status\
[](fg:#494F51 bg:#4FD6BE)\
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
[](fg:#4FD6BE bg:#5FA8C7)\
$docker_context\
[](fg:#5FA8C7 bg:#5FA8C7)\
$time\
[ ](fg:#5FA8C7)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#10181A"
style_root = "bg:#10181A"
format = '[$user ]($style)'

[directory]
style = "bg:#2D3435"
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
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#5FA8C7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#494F51"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#494F51"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#10181A"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#4FD6BE"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#5FA8C7"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/jan.toml" <<'EOF'
format = """
[](#212A4C)\
$python\
$username\
[](bg:#3C4461 fg:#212A4C)\
$directory\
[](fg:#3C4461 bg:#565D77)\
$git_branch\
$git_status\
[](fg:#565D77 bg:#8DF202)\
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
[](fg:#8DF202 bg:#6800D2)\
$docker_context\
[](fg:#6800D2 bg:#19BFFE)\
$time\
[ ](fg:#19BFFE)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#212A4C"
style_root = "bg:#212A4C"
format = '[$user ]($style)'

[directory]
style = "bg:#3C4461"
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
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#6800D2"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#565D77"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#565D77"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#212A4C"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#19BFFE"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/jan-square.toml" <<'EOF'
format = """
[](#212A4C)\
$python\
$username\
[](bg:#3C4461 fg:#212A4C)\
$directory\
[](fg:#3C4461 bg:#565D77)\
$git_branch\
$git_status\
[](fg:#565D77 bg:#8DF202)\
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
[](fg:#8DF202 bg:#6800D2)\
$docker_context\
[](fg:#6800D2 bg:#19BFFE)\
$time\
[ ](fg:#19BFFE)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#212A4C"
style_root = "bg:#212A4C"
format = '[$user ]($style)'

[directory]
style = "bg:#3C4461"
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
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#6800D2"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#565D77"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#565D77"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#212A4C"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8DF202"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#19BFFE"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/karla.toml" <<'EOF'
format = """
[](#0E1113)\
$python\
$username\
[](bg:#2B2E2F fg:#0E1113)\
$directory\
[](fg:#2B2E2F bg:#484A4C)\
$git_branch\
$git_status\
[](fg:#484A4C bg:#7DF0F0)\
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
[](fg:#7DF0F0 bg:#7A44E3)\
$docker_context\
[](fg:#7A44E3 bg:#4856D4)\
$time\
[ ](fg:#4856D4)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#0E1113"
style_root = "bg:#0E1113"
format = '[$user ]($style)'

[directory]
style = "bg:#2B2E2F"
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
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#7A44E3"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#484A4C"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#484A4C"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#0E1113"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#4856D4"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/karla-square.toml" <<'EOF'
format = """
[](#0E1113)\
$python\
$username\
[](bg:#2B2E2F fg:#0E1113)\
$directory\
[](fg:#2B2E2F bg:#484A4C)\
$git_branch\
$git_status\
[](fg:#484A4C bg:#7DF0F0)\
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
[](fg:#7DF0F0 bg:#7A44E3)\
$docker_context\
[](fg:#7A44E3 bg:#4856D4)\
$time\
[ ](fg:#4856D4)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#0E1113"
style_root = "bg:#0E1113"
format = '[$user ]($style)'

[directory]
style = "bg:#2B2E2F"
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
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#7A44E3"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#484A4C"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#484A4C"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#0E1113"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7DF0F0"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#4856D4"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/marisol.toml" <<'EOF'
format = """
[](#241C1C)\
$python\
$username\
[](bg:#3E3737 fg:#241C1C)\
$directory\
[](fg:#3E3737 bg:#595252)\
$git_branch\
$git_status\
[](fg:#595252 bg:#6FA8C7)\
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
[](fg:#6FA8C7 bg:#B98FC7)\
$docker_context\
[](fg:#B98FC7 bg:#6FA8C7)\
$time\
[ ](fg:#6FA8C7)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#241C1C"
style_root = "bg:#241C1C"
format = '[$user ]($style)'

[directory]
style = "bg:#3E3737"
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
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B98FC7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#595252"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#595252"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#241C1C"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#6FA8C7"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/marisol-square.toml" <<'EOF'
format = """
[](#241C1C)\
$python\
$username\
[](bg:#3E3737 fg:#241C1C)\
$directory\
[](fg:#3E3737 bg:#595252)\
$git_branch\
$git_status\
[](fg:#595252 bg:#6FA8C7)\
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
[](fg:#6FA8C7 bg:#B98FC7)\
$docker_context\
[](fg:#B98FC7 bg:#6FA8C7)\
$time\
[ ](fg:#6FA8C7)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#241C1C"
style_root = "bg:#241C1C"
format = '[$user ]($style)'

[directory]
style = "bg:#3E3737"
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
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B98FC7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#595252"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#595252"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#241C1C"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#6FA8C7"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#6FA8C7"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/nord.toml" <<'EOF'
format = """
[](#2E3440)\
$python\
$username\
[](bg:#474C57 fg:#2E3440)\
$directory\
[](fg:#474C57 bg:#60656E)\
$git_branch\
$git_status\
[](fg:#60656E bg:#8FBCBB)\
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
[](fg:#8FBCBB bg:#B48EAD)\
$docker_context\
[](fg:#B48EAD bg:#5E81AC)\
$time\
[ ](fg:#5E81AC)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#2E3440"
style_root = "bg:#2E3440"
format = '[$user ]($style)'

[directory]
style = "bg:#474C57"
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
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B48EAD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#60656E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#60656E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#2E3440"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#5E81AC"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/nord-square.toml" <<'EOF'
format = """
[](#2E3440)\
$python\
$username\
[](bg:#474C57 fg:#2E3440)\
$directory\
[](fg:#474C57 bg:#60656E)\
$git_branch\
$git_status\
[](fg:#60656E bg:#8FBCBB)\
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
[](fg:#8FBCBB bg:#B48EAD)\
$docker_context\
[](fg:#B48EAD bg:#5E81AC)\
$time\
[ ](fg:#5E81AC)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#2E3440"
style_root = "bg:#2E3440"
format = '[$user ]($style)'

[directory]
style = "bg:#474C57"
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
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B48EAD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#60656E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#60656E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#2E3440"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#5E81AC"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/pamela.toml" <<'EOF'
format = """
[](#1D1F28)\
$python\
$username\
[](bg:#383A42 fg:#1D1F28)\
$directory\
[](fg:#383A42 bg:#53555C)\
$git_branch\
$git_status\
[](fg:#53555C bg:#79E6F3)\
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
[](fg:#79E6F3 bg:#C574DD)\
$docker_context\
[](fg:#C574DD bg:#8897F4)\
$time\
[ ](fg:#8897F4)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1D1F28"
style_root = "bg:#1D1F28"
format = '[$user ]($style)'

[directory]
style = "bg:#383A42"
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
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C574DD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#53555C"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#53555C"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1D1F28"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#8897F4"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/pamela-square.toml" <<'EOF'
format = """
[](#1D1F28)\
$python\
$username\
[](bg:#383A42 fg:#1D1F28)\
$directory\
[](fg:#383A42 bg:#53555C)\
$git_branch\
$git_status\
[](fg:#53555C bg:#79E6F3)\
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
[](fg:#79E6F3 bg:#C574DD)\
$docker_context\
[](fg:#C574DD bg:#8897F4)\
$time\
[ ](fg:#8897F4)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1D1F28"
style_root = "bg:#1D1F28"
format = '[$user ]($style)'

[directory]
style = "bg:#383A42"
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
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C574DD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#53555C"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#53555C"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1D1F28"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#79E6F3"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#8897F4"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/silvia.toml" <<'EOF'
format = """
[](#3C3836)\
$python\
$username\
[](bg:#53504E fg:#3C3836)\
$directory\
[](fg:#53504E bg:#6B6866)\
$git_branch\
$git_status\
[](fg:#6B6866 bg:#689D6A)\
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
[](fg:#689D6A bg:#B16286)\
$docker_context\
[](fg:#B16286 bg:#458588)\
$time\
[ ](fg:#458588)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#3C3836"
style_root = "bg:#3C3836"
format = '[$user ]($style)'

[directory]
style = "bg:#53504E"
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
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B16286"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#6B6866"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#6B6866"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#3C3836"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#458588"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/silvia-square.toml" <<'EOF'
format = """
[](#3C3836)\
$python\
$username\
[](bg:#53504E fg:#3C3836)\
$directory\
[](fg:#53504E bg:#6B6866)\
$git_branch\
$git_status\
[](fg:#6B6866 bg:#689D6A)\
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
[](fg:#689D6A bg:#B16286)\
$docker_context\
[](fg:#B16286 bg:#458588)\
$time\
[ ](fg:#458588)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#3C3836"
style_root = "bg:#3C3836"
format = '[$user ]($style)'

[directory]
style = "bg:#53504E"
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
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B16286"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#6B6866"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#6B6866"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#3C3836"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#689D6A"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#458588"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/tobi.toml" <<'EOF'
format = """
[](#1E1E2E)\
$python\
$username\
[](bg:#313244 fg:#1E1E2E)\
$directory\
[](fg:#313244 bg:#6E6C7E)\
$git_branch\
$git_status\
[](fg:#6E6C7E bg:#62B4F9)\
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
[](fg:#62B4F9 bg:#F5C2E7)\
$docker_context\
[](fg:#F5C2E7 bg:#FAE3B0)\
$time\
[ ](fg:#FAE3B0)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E1E2E"
style_root = "bg:#1E1E2E"
format = '[$user ]($style)'

[directory]
style = "bg:#313244"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = "  "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important  " = "  "

[c]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#F5C2E7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#6E6C7E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#6E6C7E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E1E2E"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#FAE3B0"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/varinka.toml" <<'EOF'
format = """
[](#212529)\
$python\
$username\
[](bg:#3C3F43 fg:#212529)\
$directory\
[](fg:#3C3F43 bg:#56595C)\
$git_branch\
$git_status\
[](fg:#56595C bg:#495057)\
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
[](fg:#495057 bg:#DC5BBC)\
$docker_context\
[](fg:#DC5BBC bg:#495057)\
$time\
[ ](fg:#495057)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#212529"
style_root = "bg:#212529"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3F43"
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
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#DC5BBC"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#56595C"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#56595C"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#212529"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#495057"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/tobi-square.toml" <<'EOF'
format = """
[](#1E1E2E)\
$python\
$username\
[](bg:#313244 fg:#1E1E2E)\
$directory\
[](fg:#313244 bg:#6E6C7E)\
$git_branch\
$git_status\
[](fg:#6E6C7E bg:#62B4F9)\
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
[](fg:#62B4F9 bg:#F5C2E7)\
$docker_context\
[](fg:#F5C2E7 bg:#FAE3B0)\
$time\
[ ](fg:#FAE3B0)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#1E1E2E"
style_root = "bg:#1E1E2E"
format = '[$user ]($style)'

[directory]
style = "bg:#313244"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

# Here is how you can shorten some long paths by text replacement
# similar to mapped_locations in Oh My Posh:
[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "
# Keep in mind that the order matters. For example:
# "Important Documents" = "  "
# will not be replaced, because "Documents" was already substituted before.
# So either put "Important Documents" before "Documents" or use the substituted version:
# "Important  " = "  "

[c]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#F5C2E7"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#6E6C7E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#6E6C7E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#1E1E2E"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#62B4F9"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#FAE3B0"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/varinka-square.toml" <<'EOF'
format = """
[](#212529)\
$python\
$username\
[](bg:#3C3F43 fg:#212529)\
$directory\
[](fg:#3C3F43 bg:#56595C)\
$git_branch\
$git_status\
[](fg:#56595C bg:#495057)\
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
[](fg:#495057 bg:#DC5BBC)\
$docker_context\
[](fg:#DC5BBC bg:#495057)\
$time\
[ ](fg:#495057)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#212529"
style_root = "bg:#212529"
format = '[$user ]($style)'

[directory]
style = "bg:#3C3F43"
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
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#DC5BBC"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#56595C"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#56595C"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#212529"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#495057"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#495057"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/yael.toml" <<'EOF'
format = """
[](#161616)\
$python\
$username\
[](bg:#323232 fg:#161616)\
$directory\
[](fg:#323232 bg:#4E4E4E)\
$git_branch\
$git_status\
[](fg:#4E4E4E bg:#3DDBD9)\
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
[](fg:#3DDBD9 bg:#FF7EB6)\
$docker_context\
[](fg:#FF7EB6 bg:#33B1FF)\
$time\
[ ](fg:#33B1FF)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#161616"
style_root = "bg:#161616"
format = '[$user ]($style)'

[directory]
style = "bg:#323232"
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
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#FF7EB6"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#4E4E4E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#4E4E4E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#161616"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#33B1FF"
format = '[ $time ]($style)'
EOF
cat > "$CONF/starship/themes/yucklys.toml" <<'EOF'
format = """
[](#2E3440)\
$python\
$username\
[](bg:#4C566A fg:#2E3440)\
$directory\
[](fg:#4C566A bg:#81A1C1)\
$git_branch\
$git_status\
[](fg:#81A1C1 bg:#8FBCBB)\
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
[](fg:#8FBCBB bg:#B48EAD)\
$docker_context\
[](fg:#B48EAD bg:#2E3440)\
$time\
[ ](fg:#2E3440)\
"""
command_timeout = 5000

[username]
show_always = true
style_user = "bg:#2E3440"
style_root = "bg:#2E3440"
format = '[$user ]($style)'

[directory]
style = "bg:#4C566A"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B48EAD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#81A1C1"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#81A1C1"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#2E3440"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#2E3440"
format = '[ $time ]($style)'
EOF
cat > "$CONF/starship/themes/yucklys-light.toml" <<'EOF'
format = """
[](#ECEFF4)\
$python\
$username\
[](bg:#3B4252 fg:#ECEFF4)\
$directory\
[](fg:#3B4252 bg:#81A1C1)\
$git_branch\
$git_status\
[](fg:#81A1C1 bg:#8FBCBB)\
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
[](fg:#8FBCBB bg:#B48EAD)\
$docker_context\
[](fg:#B48EAD bg:#ECEFF4)\
$time\
[ ](fg:#ECEFF4)\
"""
command_timeout = 5000

[username]
show_always = true
style_user = "bg:#ECEFF4 fg:#2E3440"
style_root = "bg:#ECEFF4 fg:#2E3440"
format = '[$user ]($style)'

[directory]
style = "bg:#3B4252 fg:#ECEFF4"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B48EAD fg:#2E3440"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#81A1C1 fg:#2E3440"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#81A1C1 fg:#2E3440"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#ECEFF4 fg:#2E3440"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#ECEFF4 fg:#2E3440"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/yael-square.toml" <<'EOF'
format = """
[](#161616)\
$python\
$username\
[](bg:#323232 fg:#161616)\
$directory\
[](fg:#323232 bg:#4E4E4E)\
$git_branch\
$git_status\
[](fg:#4E4E4E bg:#3DDBD9)\
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
[](fg:#3DDBD9 bg:#FF7EB6)\
$docker_context\
[](fg:#FF7EB6 bg:#33B1FF)\
$time\
[ ](fg:#33B1FF)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#161616"
style_root = "bg:#161616"
format = '[$user ]($style)'

[directory]
style = "bg:#323232"
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
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#FF7EB6"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#4E4E4E"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#4E4E4E"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#161616"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#3DDBD9"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#33B1FF"
format = '[ $time ]($style)'
EOF
cat > "$CONF/starship/themes/yucklys-square.toml" <<'EOF'
format = """
[](#2E3440)\
$python\
$username\
[](bg:#4C566A fg:#2E3440)\
$directory\
[](fg:#4C566A bg:#81A1C1)\
$git_branch\
$git_status\
[](fg:#81A1C1 bg:#8FBCBB)\
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
[](fg:#8FBCBB bg:#B48EAD)\
$docker_context\
[](fg:#B48EAD bg:#2E3440)\
$time\
[ ](fg:#2E3440)\
"""
command_timeout = 5000

[username]
show_always = true
style_user = "bg:#2E3440"
style_root = "bg:#2E3440"
format = '[$user ]($style)'

[directory]
style = "bg:#4C566A"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B48EAD"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#81A1C1"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#81A1C1"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#2E3440"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8FBCBB"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#2E3440"
format = '[ $time ]($style)'
EOF
cat > "$CONF/starship/themes/yucklys-light-square.toml" <<'EOF'
format = """
[](#ECEFF4)\
$python\
$username\
[](bg:#3B4252 fg:#ECEFF4)\
$directory\
[](fg:#3B4252 bg:#81A1C1)\
$git_branch\
$git_status\
[](fg:#81A1C1 bg:#8FBCBB)\
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
[](fg:#8FBCBB bg:#B48EAD)\
$docker_context\
[](fg:#B48EAD bg:#ECEFF4)\
$time\
[ ](fg:#ECEFF4)\
"""
command_timeout = 5000

[username]
show_always = true
style_user = "bg:#ECEFF4 fg:#2E3440"
style_root = "bg:#ECEFF4 fg:#2E3440"
format = '[$user ]($style)'

[directory]
style = "bg:#3B4252 fg:#ECEFF4"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[c]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#B48EAD fg:#2E3440"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#81A1C1 fg:#2E3440"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#81A1C1 fg:#2E3440"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#ECEFF4 fg:#2E3440"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#8FBCBB fg:#2E3440"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#ECEFF4 fg:#2E3440"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/z0mbi3.toml" <<'EOF'
format = """
[](#0D0F18)\
$python\
$username\
[](bg:#2A2C34 fg:#0D0F18)\
$directory\
[](fg:#2A2C34 bg:#47494F)\
$git_branch\
$git_status\
[](fg:#47494F bg:#93CEE9)\
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
[](fg:#93CEE9 bg:#C296EB)\
$docker_context\
[](fg:#C296EB bg:#86AAEC)\
$time\
[ ](fg:#86AAEC)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#0D0F18"
style_root = "bg:#0D0F18"
format = '[$user ]($style)'

[directory]
style = "bg:#2A2C34"
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
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C296EB"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#47494F"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#47494F"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#0D0F18"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#86AAEC"
format = '[ $time ]($style)'
EOF

cat > "$CONF/starship/themes/z0mbi3-square.toml" <<'EOF'
format = """
[](#0D0F18)\
$python\
$username\
[](bg:#2A2C34 fg:#0D0F18)\
$directory\
[](fg:#2A2C34 bg:#47494F)\
$git_branch\
$git_status\
[](fg:#47494F bg:#93CEE9)\
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
[](fg:#93CEE9 bg:#C296EB)\
$docker_context\
[](fg:#C296EB bg:#86AAEC)\
$time\
[ ](fg:#86AAEC)\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:#0D0F18"
style_root = "bg:#0D0F18"
format = '[$user ]($style)'

[directory]
style = "bg:#2A2C34"
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
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#C296EB"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#47494F"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#47494F"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#0D0F18"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#93CEE9"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:#86AAEC"
format = '[ $time ]($style)'
EOF

# mybash's setup.sh leaves ~/.config/starship.toml as a symlink into its
# own installed copy - remove that specifically (not a plain file, which
# a re-run of this script should just overwrite normally) before seeding
# the current theme, so this rice's own copy becomes the one Starship
# actually reads rather than silently writing through the symlink into
# mybash's own directory.
[ -L "$HOME/.config/starship.toml" ] && rm "$HOME/.config/starship.toml"
cp "$CONF/starship/themes/catppuccin-mocha.toml" "$HOME/.config/starship.toml"

# ----------------------------------------------------------------------------
# 9b. flameshot

# ----------------------------------------------------------------------------
# 8b. dunst per-theme configs - reachable from ~/.local/bin/polybar-theme.sh
# ----------------------------------------------------------------------------
# Same palette-per-theme-name approach as rofi/kitty/starship above: each
# file here is a complete standalone dunstrc (not a shared [colors]
# fragment), generated from that theme's own already-resolved kitty ANSI
# colors (background/foreground/color5/color1/color0/color8), reused rather
# than re-parsed from the polybar .ini a second time. Radius 10 for the base
# variant, 0 for -square, matching the rofi/polybar corner-radius precedent.
log "Writing dunst per-theme configs..."
mkdir -p "$CONF/dunst/themes"
cat > "$CONF/dunst/themes/aline-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#2E5D66"
corner_radius = 0
background = "#FAF4ED"
foreground = "#575279"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#F2E9E1"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#FAF4ED"
foreground = "#9893A5"
frame_color = "#F2E9E1"
timeout = 4

[urgency_normal]
background = "#FAF4ED"
foreground = "#575279"
frame_color = "#2E5D66"
timeout = 6

[urgency_critical]
background = "#FAF4ED"
foreground = "#B4637A"
frame_color = "#B4637A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/aline.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#2E5D66"
corner_radius = 10
background = "#FAF4ED"
foreground = "#575279"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#F2E9E1"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#FAF4ED"
foreground = "#9893A5"
frame_color = "#F2E9E1"
timeout = 4

[urgency_normal]
background = "#FAF4ED"
foreground = "#575279"
frame_color = "#2E5D66"
timeout = 6

[urgency_critical]
background = "#FAF4ED"
foreground = "#B4637A"
frame_color = "#B4637A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/alireza-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#BD93F9"
corner_radius = 0
background = "#282A36"
foreground = "#F8F8F2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282A36"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282A36"
foreground = "#6272A4"
frame_color = "#282A36"
timeout = 4

[urgency_normal]
background = "#282A36"
foreground = "#F8F8F2"
frame_color = "#BD93F9"
timeout = 6

[urgency_critical]
background = "#282A36"
foreground = "#FF5E76"
frame_color = "#FF5E76"
timeout = 0
EOF

cat > "$CONF/dunst/themes/archblur-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FE8019"
corner_radius = 0
background = "#282828"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282828"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282828"
foreground = "#A89984"
frame_color = "#282828"
timeout = 4

[urgency_normal]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FE8019"
timeout = 6

[urgency_critical]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 0
EOF

cat > "$CONF/dunst/themes/archcraft-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C678DD"
corner_radius = 0
background = "#1E222A"
foreground = "#C8CCD4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#292E39"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E222A"
foreground = "#727C91"
frame_color = "#292E39"
timeout = 4

[urgency_normal]
background = "#1E222A"
foreground = "#C8CCD4"
frame_color = "#C678DD"
timeout = 6

[urgency_critical]
background = "#1E222A"
foreground = "#E06C75"
frame_color = "#E06C75"
timeout = 0
EOF
cat > "$CONF/dunst/themes/alireza.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#BD93F9"
corner_radius = 10
background = "#282A36"
foreground = "#F8F8F2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282A36"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282A36"
foreground = "#6272A4"
frame_color = "#282A36"
timeout = 4

[urgency_normal]
background = "#282A36"
foreground = "#F8F8F2"
frame_color = "#BD93F9"
timeout = 6

[urgency_critical]
background = "#282A36"
foreground = "#FF5E76"
frame_color = "#FF5E76"
timeout = 0
EOF

cat > "$CONF/dunst/themes/archblur.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FE8019"
corner_radius = 10
background = "#282828"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282828"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282828"
foreground = "#A89984"
frame_color = "#282828"
timeout = 4

[urgency_normal]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FE8019"
timeout = 6

[urgency_critical]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 0
EOF

cat > "$CONF/dunst/themes/archcraft.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C678DD"
corner_radius = 10
background = "#1E222A"
foreground = "#C8CCD4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#292E39"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E222A"
foreground = "#727C91"
frame_color = "#292E39"
timeout = 4

[urgency_normal]
background = "#1E222A"
foreground = "#C8CCD4"
frame_color = "#C678DD"
timeout = 6

[urgency_critical]
background = "#1E222A"
foreground = "#E06C75"
frame_color = "#E06C75"
timeout = 0
EOF
cat > "$CONF/dunst/themes/breddie-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#ACB0D0"
corner_radius = 0
background = "#1A1B26"
foreground = "#E5E9F0"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1A1B26"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1A1B26"
foreground = "#444B61"
frame_color = "#1A1B26"
timeout = 4

[urgency_normal]
background = "#1A1B26"
foreground = "#E5E9F0"
frame_color = "#ACB0D0"
timeout = 6

; Matches the source's own real dunstrc critical style directly (dark red
; background, bright red frame) - one of the only places its otherwise
; near-monochrome setup uses bold, alarming color at all.
[urgency_critical]
background = "#900000"
foreground = "#ffffff"
frame_color = "#ff0000"
timeout = 0
EOF

cat > "$CONF/dunst/themes/brenda-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#D699B6"
corner_radius = 0
background = "#2D353B"
foreground = "#D3C6AA"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3D454B"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#2D353B"
foreground = "#859289"
frame_color = "#3D454B"
timeout = 4

[urgency_normal]
background = "#2D353B"
foreground = "#D3C6AA"
frame_color = "#D699B6"
timeout = 6

[urgency_critical]
background = "#2D353B"
foreground = "#E67E80"
frame_color = "#E67E80"
timeout = 0
EOF
cat > "$CONF/dunst/themes/breddie.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#ACB0D0"
corner_radius = 10
background = "#1A1B26"
foreground = "#E5E9F0"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1A1B26"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1A1B26"
foreground = "#444B61"
frame_color = "#1A1B26"
timeout = 4

[urgency_normal]
background = "#1A1B26"
foreground = "#E5E9F0"
frame_color = "#ACB0D0"
timeout = 6

; Matches the source's own real dunstrc critical style directly (dark red
; background, bright red frame) - one of the only places its otherwise
; near-monochrome setup uses bold, alarming color at all.
[urgency_critical]
background = "#900000"
foreground = "#ffffff"
frame_color = "#ff0000"
timeout = 0
EOF

cat > "$CONF/dunst/themes/brenda.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#D699B6"
corner_radius = 10
background = "#2D353B"
foreground = "#D3C6AA"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3D454B"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#2D353B"
foreground = "#859289"
frame_color = "#3D454B"
timeout = 4

[urgency_normal]
background = "#2D353B"
foreground = "#D3C6AA"
frame_color = "#D699B6"
timeout = 6

[urgency_critical]
background = "#2D353B"
foreground = "#E67E80"
frame_color = "#E67E80"
timeout = 0
EOF
cat > "$CONF/dunst/themes/catppuccin-mocha-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#F5C2E7"
corner_radius = 0
background = "#1E1E2E"
foreground = "#CDD6F4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#45475A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E1E2E"
foreground = "#585B70"
frame_color = "#45475A"
timeout = 4

[urgency_normal]
background = "#1E1E2E"
foreground = "#CDD6F4"
frame_color = "#F5C2E7"
timeout = 6

[urgency_critical]
background = "#1E1E2E"
foreground = "#F38BA8"
frame_color = "#F38BA8"
timeout = 0
EOF
cat > "$CONF/dunst/themes/catppuccin-mocha.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#F5C2E7"
corner_radius = 10
background = "#1E1E2E"
foreground = "#CDD6F4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#45475A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E1E2E"
foreground = "#585B70"
frame_color = "#45475A"
timeout = 4

[urgency_normal]
background = "#1E1E2E"
foreground = "#CDD6F4"
frame_color = "#F5C2E7"
timeout = 6

[urgency_critical]
background = "#1E1E2E"
foreground = "#F38BA8"
frame_color = "#F38BA8"
timeout = 0
EOF
cat > "$CONF/dunst/themes/cherryblocks-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FB4934"
corner_radius = 0
background = "#282828"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282828"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282828"
foreground = "#A89984"
frame_color = "#282828"
timeout = 4

[urgency_normal]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 6

[urgency_critical]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 0
EOF
cat > "$CONF/dunst/themes/classic-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FE8019"
corner_radius = 0
background = "#282828"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282828"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282828"
foreground = "#A89984"
frame_color = "#282828"
timeout = 4

[urgency_normal]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FE8019"
timeout = 6

[urgency_critical]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 0
EOF

cat > "$CONF/dunst/themes/cristina-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C3A5E6"
corner_radius = 0
background = "#232136"
foreground = "#E0DEF4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#232136"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#232136"
foreground = "#908CAA"
frame_color = "#232136"
timeout = 4

[urgency_normal]
background = "#232136"
foreground = "#E0DEF4"
frame_color = "#C3A5E6"
timeout = 6

[urgency_critical]
background = "#232136"
foreground = "#EA6F91"
frame_color = "#EA6F91"
timeout = 0
EOF
cat > "$CONF/dunst/themes/cherryblocks.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FB4934"
corner_radius = 10
background = "#282828"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282828"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282828"
foreground = "#A89984"
frame_color = "#282828"
timeout = 4

[urgency_normal]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 6

[urgency_critical]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 0
EOF
cat > "$CONF/dunst/themes/classic.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FE8019"
corner_radius = 0
background = "#282828"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#282828"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282828"
foreground = "#A89984"
frame_color = "#282828"
timeout = 4

[urgency_normal]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FE8019"
timeout = 6

[urgency_critical]
background = "#282828"
foreground = "#EBDBB2"
frame_color = "#FB4934"
timeout = 0
EOF

cat > "$CONF/dunst/themes/cristina.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C3A5E6"
corner_radius = 10
background = "#232136"
foreground = "#E0DEF4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#232136"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#232136"
foreground = "#908CAA"
frame_color = "#232136"
timeout = 4

[urgency_normal]
background = "#232136"
foreground = "#E0DEF4"
frame_color = "#C3A5E6"
timeout = 6

[urgency_critical]
background = "#232136"
foreground = "#EA6F91"
frame_color = "#EA6F91"
timeout = 0
EOF
cat > "$CONF/dunst/themes/cynthia-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#938AA9"
corner_radius = 0
background = "#181616"
foreground = "#C5C9C5"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#242121"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#181616"
foreground = "#708491"
frame_color = "#242121"
timeout = 4

[urgency_normal]
background = "#181616"
foreground = "#C5C9C5"
frame_color = "#938AA9"
timeout = 6

[urgency_critical]
background = "#181616"
foreground = "#E46876"
frame_color = "#E46876"
timeout = 0
EOF
cat > "$CONF/dunst/themes/cynthia.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#938AA9"
corner_radius = 10
background = "#181616"
foreground = "#C5C9C5"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#242121"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#181616"
foreground = "#708491"
frame_color = "#242121"
timeout = 4

[urgency_normal]
background = "#181616"
foreground = "#C5C9C5"
frame_color = "#938AA9"
timeout = 6

[urgency_critical]
background = "#181616"
foreground = "#E46876"
frame_color = "#E46876"
timeout = 0
EOF
cat > "$CONF/dunst/themes/daniela-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#BB9AF7"
corner_radius = 0
background = "#1A1B26"
foreground = "#C0CAF5"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1A1B26"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1A1B26"
foreground = "#565F89"
frame_color = "#1A1B26"
timeout = 4

[urgency_normal]
background = "#1A1B26"
foreground = "#C0CAF5"
frame_color = "#BB9AF7"
timeout = 6

[urgency_critical]
background = "#1A1B26"
foreground = "#F7768E"
frame_color = "#F7768E"
timeout = 0
EOF
cat > "$CONF/dunst/themes/daniela.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#BB9AF7"
corner_radius = 10
background = "#1A1B26"
foreground = "#C0CAF5"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1A1B26"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1A1B26"
foreground = "#565F89"
frame_color = "#1A1B26"
timeout = 4

[urgency_normal]
background = "#1A1B26"
foreground = "#C0CAF5"
frame_color = "#BB9AF7"
timeout = 6

[urgency_critical]
background = "#1A1B26"
foreground = "#F7768E"
frame_color = "#F7768E"
timeout = 0
EOF
cat > "$CONF/dunst/themes/dracula-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#BD93F9"
corner_radius = 0
background = "#282A36"
foreground = "#F8F8F2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#44475A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282A36"
foreground = "#6272A4"
frame_color = "#44475A"
timeout = 4

[urgency_normal]
background = "#282A36"
foreground = "#F8F8F2"
frame_color = "#BD93F9"
timeout = 6

[urgency_critical]
background = "#282A36"
foreground = "#FF5555"
frame_color = "#FF5555"
timeout = 0
EOF
cat > "$CONF/dunst/themes/dracula.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#BD93F9"
corner_radius = 10
background = "#282A36"
foreground = "#F8F8F2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#44475A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#282A36"
foreground = "#6272A4"
frame_color = "#44475A"
timeout = 4

[urgency_normal]
background = "#282A36"
foreground = "#F8F8F2"
frame_color = "#BD93F9"
timeout = 6

[urgency_critical]
background = "#282A36"
foreground = "#FF5555"
frame_color = "#FF5555"
timeout = 0
EOF
cat > "$CONF/dunst/themes/emilia-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B08BBB"
corner_radius = 0
background = "#1E1A17"
foreground = "#E8DCC8"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#2B241F"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E1A17"
foreground = "#9C8F7D"
frame_color = "#2B241F"
timeout = 4

[urgency_normal]
background = "#1E1A17"
foreground = "#E8DCC8"
frame_color = "#B08BBB"
timeout = 6

[urgency_critical]
background = "#1E1A17"
foreground = "#D9736A"
frame_color = "#D9736A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/emilia.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B08BBB"
corner_radius = 10
background = "#1E1A17"
foreground = "#E8DCC8"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#2B241F"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E1A17"
foreground = "#9C8F7D"
frame_color = "#2B241F"
timeout = 4

[urgency_normal]
background = "#1E1A17"
foreground = "#E8DCC8"
frame_color = "#B08BBB"
timeout = 6

[urgency_critical]
background = "#1E1A17"
foreground = "#D9736A"
frame_color = "#D9736A"
timeout = 0
EOF

cat > "$CONF/dunst/themes/h4ck3r-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#00FA5C"
corner_radius = 0
background = "#0C1018"
foreground = "#00FA5C"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1B2333"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#0C1018"
foreground = "#578A29"
frame_color = "#1B2333"
timeout = 4

[urgency_normal]
background = "#0C1018"
foreground = "#00FA5C"
frame_color = "#00FA5C"
timeout = 6

[urgency_critical]
background = "#0C1018"
foreground = "#6DDE00"
frame_color = "#6DDE00"
timeout = 0
EOF

cat > "$CONF/dunst/themes/h4ck3r.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#00FA5C"
corner_radius = 10
background = "#0C1018"
foreground = "#00FA5C"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1B2333"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#0C1018"
foreground = "#578A29"
frame_color = "#1B2333"
timeout = 4

[urgency_normal]
background = "#0C1018"
foreground = "#00FA5C"
frame_color = "#00FA5C"
timeout = 6

[urgency_critical]
background = "#0C1018"
foreground = "#6DDE00"
frame_color = "#6DDE00"
timeout = 0
EOF
cat > "$CONF/dunst/themes/isabel-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#5FA8C7"
corner_radius = 0
background = "#10181A"
foreground = "#A8C5C0"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#10181A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#10181A"
foreground = "#5C7B76"
frame_color = "#10181A"
timeout = 4

[urgency_normal]
background = "#10181A"
foreground = "#A8C5C0"
frame_color = "#5FA8C7"
timeout = 6

[urgency_critical]
background = "#10181A"
foreground = "#D67F7F"
frame_color = "#D67F7F"
timeout = 0
EOF
cat > "$CONF/dunst/themes/isabel.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#5FA8C7"
corner_radius = 10
background = "#10181A"
foreground = "#A8C5C0"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#10181A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#10181A"
foreground = "#5C7B76"
frame_color = "#10181A"
timeout = 4

[urgency_normal]
background = "#10181A"
foreground = "#A8C5C0"
frame_color = "#5FA8C7"
timeout = 6

[urgency_critical]
background = "#10181A"
foreground = "#D67F7F"
frame_color = "#D67F7F"
timeout = 0
EOF
cat > "$CONF/dunst/themes/jan-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#6800D2"
corner_radius = 0
background = "#212A4C"
foreground = "#27FBFE"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#212A4C"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#212A4C"
foreground = "#6B7BB0"
frame_color = "#212A4C"
timeout = 4

[urgency_normal]
background = "#212A4C"
foreground = "#27FBFE"
frame_color = "#6800D2"
timeout = 6

[urgency_critical]
background = "#212A4C"
foreground = "#FB007A"
frame_color = "#FB007A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/jan.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#6800D2"
corner_radius = 10
background = "#212A4C"
foreground = "#27FBFE"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#212A4C"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#212A4C"
foreground = "#6B7BB0"
frame_color = "#212A4C"
timeout = 4

[urgency_normal]
background = "#212A4C"
foreground = "#27FBFE"
frame_color = "#6800D2"
timeout = 6

[urgency_critical]
background = "#212A4C"
foreground = "#FB007A"
frame_color = "#FB007A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/karla-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#7A44E3"
corner_radius = 0
background = "#0E1113"
foreground = "#AFB1DB"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#0E1113"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#0E1113"
foreground = "#6272A4"
frame_color = "#0E1113"
timeout = 4

[urgency_normal]
background = "#0E1113"
foreground = "#AFB1DB"
frame_color = "#7A44E3"
timeout = 6

[urgency_critical]
background = "#0E1113"
foreground = "#E7034A"
frame_color = "#E7034A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/karla.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#7A44E3"
corner_radius = 10
background = "#0E1113"
foreground = "#AFB1DB"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#0E1113"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#0E1113"
foreground = "#6272A4"
frame_color = "#0E1113"
timeout = 4

[urgency_normal]
background = "#0E1113"
foreground = "#AFB1DB"
frame_color = "#7A44E3"
timeout = 6

[urgency_critical]
background = "#0E1113"
foreground = "#E7034A"
frame_color = "#E7034A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/marisol-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B98FC7"
corner_radius = 0
background = "#241C1C"
foreground = "#F5E6E0"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#332727"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#241C1C"
foreground = "#A8827C"
frame_color = "#332727"
timeout = 4

[urgency_normal]
background = "#241C1C"
foreground = "#F5E6E0"
frame_color = "#B98FC7"
timeout = 6

[urgency_critical]
background = "#241C1C"
foreground = "#E8604C"
frame_color = "#E8604C"
timeout = 0
EOF
cat > "$CONF/dunst/themes/marisol.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B98FC7"
corner_radius = 10
background = "#241C1C"
foreground = "#F5E6E0"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#332727"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#241C1C"
foreground = "#A8827C"
frame_color = "#332727"
timeout = 4

[urgency_normal]
background = "#241C1C"
foreground = "#F5E6E0"
frame_color = "#B98FC7"
timeout = 6

[urgency_critical]
background = "#241C1C"
foreground = "#E8604C"
frame_color = "#E8604C"
timeout = 0
EOF
cat > "$CONF/dunst/themes/nord-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B48EAD"
corner_radius = 0
background = "#2E3440"
foreground = "#ECEFF4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3B4252"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#2E3440"
foreground = "#D8DEE9"
frame_color = "#3B4252"
timeout = 4

[urgency_normal]
background = "#2E3440"
foreground = "#ECEFF4"
frame_color = "#B48EAD"
timeout = 6

[urgency_critical]
background = "#2E3440"
foreground = "#BF616A"
frame_color = "#BF616A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/nord.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B48EAD"
corner_radius = 10
background = "#2E3440"
foreground = "#ECEFF4"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3B4252"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#2E3440"
foreground = "#D8DEE9"
frame_color = "#3B4252"
timeout = 4

[urgency_normal]
background = "#2E3440"
foreground = "#ECEFF4"
frame_color = "#B48EAD"
timeout = 6

[urgency_critical]
background = "#2E3440"
foreground = "#BF616A"
frame_color = "#BF616A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/pamela-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C574DD"
corner_radius = 0
background = "#1D1F28"
foreground = "#FDFDFD"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3D435C"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1D1F28"
foreground = "#8C8C8C"
frame_color = "#3D435C"
timeout = 4

[urgency_normal]
background = "#1D1F28"
foreground = "#FDFDFD"
frame_color = "#C574DD"
timeout = 6

[urgency_critical]
background = "#1D1F28"
foreground = "#F37F97"
frame_color = "#F37F97"
timeout = 0
EOF
cat > "$CONF/dunst/themes/pamela.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C574DD"
corner_radius = 10
background = "#1D1F28"
foreground = "#FDFDFD"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3D435C"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1D1F28"
foreground = "#8C8C8C"
frame_color = "#3D435C"
timeout = 4

[urgency_normal]
background = "#1D1F28"
foreground = "#FDFDFD"
frame_color = "#C574DD"
timeout = 6

[urgency_critical]
background = "#1D1F28"
foreground = "#F37F97"
frame_color = "#F37F97"
timeout = 0
EOF
cat > "$CONF/dunst/themes/silvia-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B16286"
corner_radius = 0
background = "#3C3836"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#504945"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#3C3836"
foreground = "#928374"
frame_color = "#504945"
timeout = 4

[urgency_normal]
background = "#3C3836"
foreground = "#EBDBB2"
frame_color = "#B16286"
timeout = 6

[urgency_critical]
background = "#3C3836"
foreground = "#CC241D"
frame_color = "#CC241D"
timeout = 0
EOF
cat > "$CONF/dunst/themes/silvia.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#B16286"
corner_radius = 10
background = "#3C3836"
foreground = "#EBDBB2"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#504945"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#3C3836"
foreground = "#928374"
frame_color = "#504945"
timeout = 4

[urgency_normal]
background = "#3C3836"
foreground = "#EBDBB2"
frame_color = "#B16286"
timeout = 6

[urgency_critical]
background = "#3C3836"
foreground = "#CC241D"
frame_color = "#CC241D"
timeout = 0
EOF
cat > "$CONF/dunst/themes/tobi-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#62B4F9"
corner_radius = 0
background = "#1E1E2E"
foreground = "#D9E0EE"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1E1E2E"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E1E2E"
foreground = "#6E6C7E"
frame_color = "#96CDFB"
timeout = 4

[urgency_normal]
background = "#1E1E2E"
foreground = "#D9E0EE"
frame_color = "#62B4F9"
timeout = 6

[urgency_critical]
background = "#1E1E2E"
foreground = "#D9E0EE"
frame_color = "#F28FAD"
timeout = 0
EOF

cat > "$CONF/dunst/themes/varinka-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#DC5BBC"
corner_radius = 0
background = "#212529"
foreground = "#F8F9FA"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#343A40"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#212529"
foreground = "#6C757D"
frame_color = "#343A40"
timeout = 4

[urgency_normal]
background = "#212529"
foreground = "#F8F9FA"
frame_color = "#DC5BBC"
timeout = 6

[urgency_critical]
background = "#212529"
foreground = "#DC5BBC"
frame_color = "#DC5BBC"
timeout = 0
EOF
cat > "$CONF/dunst/themes/tobi.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#62B4F9"
corner_radius = 10
background = "#1E1E2E"
foreground = "#D9E0EE"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1E1E2E"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#1E1E2E"
foreground = "#6E6C7E"
frame_color = "#96CDFB"
timeout = 4

[urgency_normal]
background = "#1E1E2E"
foreground = "#D9E0EE"
frame_color = "#62B4F9"
timeout = 6

[urgency_critical]
background = "#1E1E2E"
foreground = "#D9E0EE"
frame_color = "#F28FAD"
timeout = 0
EOF

cat > "$CONF/dunst/themes/varinka.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#DC5BBC"
corner_radius = 10
background = "#212529"
foreground = "#F8F9FA"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#343A40"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#212529"
foreground = "#6C757D"
frame_color = "#343A40"
timeout = 4

[urgency_normal]
background = "#212529"
foreground = "#F8F9FA"
frame_color = "#DC5BBC"
timeout = 6

[urgency_critical]
background = "#212529"
foreground = "#DC5BBC"
frame_color = "#DC5BBC"
timeout = 0
EOF
cat > "$CONF/dunst/themes/yael-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FF7EB6"
corner_radius = 0
background = "#161616"
foreground = "#FFFFFF"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#262626"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#161616"
foreground = "#8C8C8C"
frame_color = "#262626"
timeout = 4

[urgency_normal]
background = "#161616"
foreground = "#FFFFFF"
frame_color = "#FF7EB6"
timeout = 6

[urgency_critical]
background = "#161616"
foreground = "#EE5396"
frame_color = "#EE5396"
timeout = 0
EOF
cat > "$CONF/dunst/themes/yucklys-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#81A1C1"
corner_radius = 0
background = "#2E3440"
foreground = "#D8DEE9"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#4C566A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#2E3440"
foreground = "#4C566A"
frame_color = "#4C566A"
timeout = 4

[urgency_normal]
background = "#2E3440"
foreground = "#D8DEE9"
frame_color = "#81A1C1"
timeout = 6

[urgency_critical]
background = "#2E3440"
foreground = "#BF616A"
frame_color = "#BF616A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/yucklys-light-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#496F95"
corner_radius = 0
background = "#ECEFF4"
foreground = "#2E3440"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3B4252"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#ECEFF4"
foreground = "#3B4252"
frame_color = "#3B4252"
timeout = 4

[urgency_normal]
background = "#ECEFF4"
foreground = "#2E3440"
frame_color = "#496F95"
timeout = 6

[urgency_critical]
background = "#ECEFF4"
foreground = "#B54954"
frame_color = "#B54954"
timeout = 0
EOF
cat > "$CONF/dunst/themes/yael.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#FF7EB6"
corner_radius = 10
background = "#161616"
foreground = "#FFFFFF"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#262626"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#161616"
foreground = "#8C8C8C"
frame_color = "#262626"
timeout = 4

[urgency_normal]
background = "#161616"
foreground = "#FFFFFF"
frame_color = "#FF7EB6"
timeout = 6

[urgency_critical]
background = "#161616"
foreground = "#EE5396"
frame_color = "#EE5396"
timeout = 0
EOF
cat > "$CONF/dunst/themes/yucklys.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#81A1C1"
corner_radius = 10
background = "#2E3440"
foreground = "#D8DEE9"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#4C566A"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#2E3440"
foreground = "#4C566A"
frame_color = "#4C566A"
timeout = 4

[urgency_normal]
background = "#2E3440"
foreground = "#D8DEE9"
frame_color = "#81A1C1"
timeout = 6

[urgency_critical]
background = "#2E3440"
foreground = "#BF616A"
frame_color = "#BF616A"
timeout = 0
EOF
cat > "$CONF/dunst/themes/yucklys-light.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#496F95"
corner_radius = 10
background = "#ECEFF4"
foreground = "#2E3440"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#3B4252"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#ECEFF4"
foreground = "#3B4252"
frame_color = "#3B4252"
timeout = 4

[urgency_normal]
background = "#ECEFF4"
foreground = "#2E3440"
frame_color = "#496F95"
timeout = 6

[urgency_critical]
background = "#ECEFF4"
foreground = "#B54954"
frame_color = "#B54954"
timeout = 0
EOF
cat > "$CONF/dunst/themes/z0mbi3-square.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C296EB"
corner_radius = 0
background = "#0D0F18"
foreground = "#A5B6CF"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1C1E27"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#0D0F18"
foreground = "#6E8DB4"
frame_color = "#1C1E27"
timeout = 4

[urgency_normal]
background = "#0D0F18"
foreground = "#A5B6CF"
frame_color = "#C296EB"
timeout = 6

[urgency_critical]
background = "#0D0F18"
foreground = "#DD6777"
frame_color = "#DD6777"
timeout = 0
EOF
cat > "$CONF/dunst/themes/z0mbi3.dunstrc" <<'EOF'
[global]
font = JetBrainsMono Nerd Font 10
frame_width = 2
frame_color = "#C296EB"
corner_radius = 10
background = "#0D0F18"
foreground = "#A5B6CF"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "#1C1E27"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "#0D0F18"
foreground = "#6E8DB4"
frame_color = "#1C1E27"
timeout = 4

[urgency_normal]
background = "#0D0F18"
foreground = "#A5B6CF"
frame_color = "#C296EB"
timeout = 6

[urgency_critical]
background = "#0D0F18"
foreground = "#DD6777"
frame_color = "#DD6777"
timeout = 0
EOF

# dunst has no config-reload-on-file-change of its own the way starship
# does (it reads dunstrc once at startup, unlike starship which re-reads
# every prompt) - seed the default here same as rofi/kitty/starship above,
# and ~/.local/bin/polybar-theme.sh's own `dunstctl reload` is what makes a
# later theme switch pick up a new dunstrc without restarting the process.
cp "$CONF/dunst/themes/catppuccin-mocha.dunstrc" "$CONF/dunst/dunstrc"

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
# 9c. Colorpicker (Mod+shift+g) - grab any on-screen pixel's color as hex
# ----------------------------------------------------------------------------
log "Writing colorpicker script..."
cat > "$BIN/colorpicker.sh" <<'EOF'
#!/usr/bin/env bash
# slop grabs the click point. `-t 0` (tolerance 0) is required, not
# cosmetic: slop doubles as a window-picker - click-and-release without
# dragging past the tolerance threshold selects the ENTIRE window under
# the cursor instead of a point at the cursor (confirmed live - this
# script originally assumed a plain click always gave a 0x0 selection at
# the exact click position, which silently produced a whole-window/whole-
# screen-sized "selection" instead, sampling its center rather than the
# actually-clicked pixel; -t 0 disables that window-selection path
# entirely so every click is always a real, tiny point-sized rectangle).
# ImageMagick's `import` (already installed above for flameshot's own
# X11-legacy-capture fallback) then re-samples that single root-window
# pixel straight to a 1x1 crop; `txt:-` is the simplest ImageMagick output
# format to pull a plain color out of without a second `convert` process.
# A small solid-color swatch PNG is generated on the fly as the
# notification icon so the popup actually shows the picked color, not
# just its hex text.
set -uo pipefail

# A missing dependency or a slop failure (no DISPLAY, X grab denied, etc.)
# used to fall through to the same silent exit as a plain Escape-cancel -
# indistinguishable from "nothing happens" at the keybinding. Each of
# those now gets its own notification; only an actual user cancel stays
# silent.
for dep in slop import xclip; do
  if ! command -v "$dep" &>/dev/null; then
    notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "'$dep' is not installed"
    exit 1
  fi
done

SLOP_OUT=$(slop -t 0 -f '%x %y %w %h %c' 2>&1)
if [ $? -ne 0 ]; then
  notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "slop failed: $(printf '%s' "$SLOP_OUT" | tail -n1)"
  exit 1
fi
read -r X Y W H CANCELLED <<< "$SLOP_OUT"
if [ "${CANCELLED:-0}" = "1" ]; then
  exit 0
fi
if [ -z "${X:-}" ]; then
  notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "slop returned no coordinates"
  exit 1
fi
# Even a careful click almost never reports back a perfect 0x0 selection -
# a pixel or two of real mouse movement between press and release is
# normal, and %x/%y alone is that selection's TOP-LEFT CORNER, not the
# click point itself. Sampling the corner instead of the center is close
# enough to go unnoticed most of the time, but on a small color swatch it
# can land just outside it in a neighboring color entirely (confirmed:
# reported as picking a color from what looked like "a large area" instead
# of the intended small target). Centering on the actual selection box
# fixes this for any amount of jitter, and is a no-op for a genuine 0x0
# click (X+0/2, Y+0/2 is just X,Y again).
X=$(( X + W / 2 ))
Y=$(( Y + H / 2 ))

# Parsed from the "srgb(R,G,B)" decimal triplet in txt: output, not its
# own "#RRGGBB"-looking hex field - on a Q16 (16-bit-per-channel) build of
# ImageMagick (confirmed live: this is the default on some distros' own
# packages) that hex field is actually 4 digits per channel
# (e.g. "#313134343535"), and a plain 6-hex-digit grep against it silently
# grabs the wrong substring instead of failing. The srgb(...) triplet is
# always plain 0-255 regardless of quantum depth, so building the hex
# ourselves from that is depth-independent.
RGB=$(import -window root -crop 1x1+"$X"+"$Y" +repage txt:- 2>/dev/null | tail -n1 | grep -oP '(?<=srgb\()[0-9]+,[0-9]+,[0-9]+(?=\))')
if [ -z "$RGB" ]; then
  notify-send -h string:x-dunst-stack-tag:colorpicker "Colorpicker" "Could not read pixel color at $X,$Y"
  exit 1
fi
IFS=',' read -r R G B <<< "$RGB"
HEX=$(printf '#%02X%02X%02X' "$R" "$G" "$B")
printf '%s' "$HEX" | xclip -selection clipboard

SWATCH="$(mktemp --suffix=.png)"
convert -size 64x64 "xc:$HEX" "$SWATCH" 2>/dev/null
notify-send -h string:x-dunst-stack-tag:colorpicker -i "$SWATCH" "Colorpicker" "$HEX copied to clipboard"
( sleep 5; rm -f "$SWATCH" ) & disown
EOF
chmod +x "$BIN/colorpicker.sh"

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
# 10c. DPMS-wake-after-resume fix - a systemd-sleep hook, not a user script.
#      lock.sh (above) forces DPMS off right after starting i3lock so the
#      screen doesn't stay lit until the idle timer would otherwise catch
#      up; on some hardware/drivers that DPMS-off state isn't reliably
#      cleared by resume alone, leaving the monitor stuck black even though
#      the system is genuinely awake (keyboard backlight on, etc.) until
#      something explicitly asserts DPMS back on. systemd-logind runs every
#      script in /etc/systemd/system-sleep/ with two arguments (pre/post,
#      then the sleep action) both right before AND right after suspend -
#      this only acts on "post". Installed to /etc rather than
#      /usr/lib/systemd/system-sleep/ (where the OS's own packaged hooks
#      live, e.g. nvidia/displaylink) since /etc is the correct local-admin
#      override location, mirroring the same /etc-vs-/usr split systemd
#      unit files themselves use.
# ----------------------------------------------------------------------------
log "Installing DPMS-wake-after-resume systemd-sleep hook (needs sudo)..."
sudo tee /etc/systemd/system-sleep/i3-dpms-wake > /dev/null <<'HOOKEOF'
#!/bin/sh
# systemd-sleep hook: forces the display back on after resume. On some
# hardware/drivers, DPMS state set before suspend - lock.sh's own `xset
# dpms force off`, run right after starting i3lock so the screen doesn't
# stay lit until the idle timer would otherwise catch up - isn't reliably
# cleared by resume alone, leaving the monitor stuck showing nothing even
# though the system is genuinely awake (keyboard backlight on, etc.) until
# something explicitly asserts DPMS back on. systemd-logind runs every
# script in this directory with two arguments ($1=pre/post, $2=the sleep
# action) both right before AND right after suspend/hibernate - this only
# acts on "post" (after resume), not "pre".
#
# Runs as root (that's how systemd-sleep hooks work), so it has to reach
# into each logged-in graphical user's own session explicitly rather than
# just running `xset` directly - DISPLAY/XAUTHORITY aren't inherited from
# anywhere at this point. XAUTHORITY's location varies by display manager
# (GDM keeps it under /run/user/<uid>/gdm/, other setups use ~/.Xauthority
# directly) - found dynamically per user rather than hardcoded to one
# convention, since a setup script installing this shouldn't only work
# under this one machine's specific display manager.
case "$1" in
  post)
    for user in $(who | awk '{print $1}' | sort -u); do
      uid="$(id -u "$user" 2>/dev/null)" || continue
      xauth="$(find "/run/user/$uid" -maxdepth 3 -iname "Xauthority" 2>/dev/null | head -1)"
      [ -z "$xauth" ] && xauth="/home/$user/.Xauthority"
      [ -f "$xauth" ] || continue
      su "$user" -c "DISPLAY=:0 XAUTHORITY=$xauth xset dpms force on" >/dev/null 2>&1
    done
    ;;
esac
HOOKEOF
sudo chmod +x /etc/systemd/system-sleep/i3-dpms-wake

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
# 11c2. Wi-Fi picker (rofi) - reachable by left-clicking the polybar
#       wireless widget.
# ----------------------------------------------------------------------------
log "Writing Wi-Fi picker script..."
cat > "$BIN/wifi-menu.sh" <<'EOF'
#!/usr/bin/env bash
# Rofi-based wifi picker - scans nearby networks and connects, unlike
# nm-connection-editor (which only edits already-saved connection
# profiles, and has no "browse nearby networks" view at all). Reuses
# current.rasi, the same rofi theme ~/.local/bin/polybar-theme.sh already
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
cat > "$BIN/polybar-theme.sh" <<'EOF'
#!/usr/bin/env bash
# Lists available themes (~/.config/polybar/themes/*.ini) via rofi and, on
# selection, applies matching polybar + rofi + kitty + starship + dunst +
# i3 border-color themes together, so one pick retints the whole desktop
# instead of just the bar. Each is its own COMPLETE, standalone config (a
# polybar config.ini, a rofi .rasi pair, a kitty color .conf, a starship
# prompt .toml, a dunst dunstrc, an i3 client.* border-color fragment)
# generated from the same underlying palette per theme name - not a shared
# [colors] fragment different tools each interpret slightly differently -
# applied with a plain file copy, no splicing to keep in sync.
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
STARSHIP_THEMES_DIR="$HOME/.config/starship/themes"
STARSHIP_CURRENT="$HOME/.config/starship.toml"
DUNST_THEMES_DIR="$HOME/.config/dunst/themes"
DUNST_CURRENT="$HOME/.config/dunst/dunstrc"
I3_THEMES_DIR="$HOME/.config/i3/themes"
I3_CURRENT="$HOME/.config/i3/current-borders.conf"

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
STARSHIP_FILE="$STARSHIP_THEMES_DIR/$CHOSEN.toml"
DUNST_FILE="$DUNST_THEMES_DIR/$CHOSEN.dunstrc"
# No "-square" variant of a border-color scheme exists (same reasoning as
# GTK_BASE below - it's a corner-rounding distinction, not a color one), so
# strip the suffix the same way before looking up the i3 theme file.
I3_FILE="$I3_THEMES_DIR/${CHOSEN%-square}.conf"

if [ ! -f "$POLY_FILE" ]; then
  notify-send "Desktop Theme" "No such theme: $CHOSEN"
  exit 1
fi

# GTK3/GTK4 theme (generate-gtk-themes.py) - "-square" variants share their
# base rice's palette 1:1 (no GTK theme equivalent of polybar/rofi corner
# rounding), so a real GTK theme only ever exists as Rice-<base-name>, never
# Rice-<name>-square. Require gtk-3.0 specifically, not just the top-level
# Rice-<name> dir: a Rice-<name> with only gtk-4.0 (no GTK3 coverage) set
# as the global theme would silently fall back to bare Adwaita for every
# plain GTK3 app (nm-connection-editor, etc) - the exact regression this
# guards against.
#
# Must happen BEFORE polybar-launch.sh below, and via `export` rather than
# just gsettings/settings.ini/environment.d: polybar (and i3, its parent)
# already has a GTK_THEME baked into its own process environment from
# session start, which always wins over gsettings/settings.ini for any app
# polybar itself forks (nm-connection-editor via the network module's
# click action, in particular) - environment.d and `systemctl --user
# set-environment` only affect *future* logins/processes, not this already-
# running session. Exporting it here, before relaunching polybar, means
# the freshly-spawned polybar process (and everything IT forks afterward)
# inherits the correct value immediately instead of the stale one - no
# logout required.
GTK_BASE="${CHOSEN%-square}"
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

if [ -f "$STARSHIP_FILE" ]; then
  cp "$STARSHIP_FILE" "$STARSHIP_CURRENT"
  # No live-retint step needed here unlike kitty above - starship re-reads
  # its config fresh on every single prompt draw (it's just a program the
  # shell re-invokes each time), so the very next prompt in any already-
  # open shell already picks this up with no socket/signal of its own.
else
  notify-send "Desktop Theme" "No starship theme for $CHOSEN, keeping previous"
fi

if [ -f "$DUNST_FILE" ]; then
  cp "$DUNST_FILE" "$DUNST_CURRENT"
  dunstctl reload >/dev/null 2>&1 || true
else
  notify-send "Desktop Theme" "No dunst theme for $CHOSEN, keeping previous"
fi

if [ -f "$I3_FILE" ]; then
  cp "$I3_FILE" "$I3_CURRENT"
  # Unlike kitty, i3 has no remote-control command to recolor client.* on
  # already-open windows - `reload` re-reads the whole config (including
  # the `include current-borders.conf` line) without touching the current
  # layout/open windows, unlike `restart` which would also relaunch bars
  # and drop in-flight scratchpad state (Cliamp/the AI window).
  i3-msg reload >/dev/null 2>&1 || true
else
  notify-send "Desktop Theme" "No i3 border theme for $CHOSEN, keeping previous"
fi

notify-send "Desktop Theme" "Switched to $CHOSEN"
EOF
chmod +x "$BIN/polybar-theme.sh"

# ----------------------------------------------------------------------------
# 11c2. Cursor theme switcher (Mod+alt+space -> Cursor Theme) - switches
#       between the 6 Qogir variants installed above.
# ----------------------------------------------------------------------------
log "Writing cursor-theme.sh..."
cat > "$BIN/cursor-theme.sh" <<'EOF'
#!/usr/bin/env bash
# Switches the X11/GTK mouse cursor theme between the 6 real Qogir variants
# installed during setup (see the Qogir cursor theme step) - the -Light
# suffix variants aren't offered since they're cursor-identical aliases of
# their non-Light counterpart. Applies live via the same mechanisms that
# made polybar/GTK actually pick up a cursor theme in the first place
# (Xresources via xrdb, gtk-cursor-theme-name), not just next login.
#
# i3 itself needs a real restart (not just polybar) - confirmed live: i3
# is its own xcb/cursor-library client, same as polybar, and loads its
# cursor (used for window borders/decorations) once rather than
# re-checking it live, so a theme switch alone left i3's own borders
# showing the previous theme even after Xresources/gtk-cursor-theme-name
# were already updated and GTK apps had already picked up the new one.
# `i3-msg restart` preserves the running session/layout (unlike `exit`)
# and re-runs i3's own `exec` lines, which also relaunches polybar - so a
# separate polybar-launch.sh call isn't needed on top of this.
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

cat > "$HOME/.Xresources" <<RES
Xcursor.theme: $CHOSEN
Xcursor.size: 24
RES
xrdb -merge "$HOME/.Xresources"

for gtk_settings in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  [ -f "$gtk_settings" ] && sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CHOSEN/" "$gtk_settings"
done
gsettings set org.gnome.desktop.interface cursor-theme "$CHOSEN" 2>/dev/null || true

XCURSOR_THEME="$CHOSEN" xsetroot -cursor_name left_ptr
i3-msg restart >/dev/null

notify-send "Cursor Theme" "Switched to $CHOSEN"
EOF
chmod +x "$BIN/cursor-theme.sh"

# ----------------------------------------------------------------------------
# 11d2. Keybinding cheat sheet (Mod+alt+space -> Keybinding Help) - printed in
#       a floating kitty window, dismissed on any keypress.
# ----------------------------------------------------------------------------
log "Writing keybinding cheat sheet script..."
cat > "$BIN/keybindings-help.sh" <<'EOF'
#!/usr/bin/env bash
# Prints this rice's keybinding cheat sheet (same content as the README's
# "Keybinding Cheat Sheet" table) in a floating kitty window, Catppuccin
# Mocha-colored. Dismisses on any keypress. Reachable from the app menu
# (Mod+alt+space -> Keybinding Help) and standalone.
MAUVE=$'\033[38;2;203;166;247m'
TEXT=$'\033[38;2;205;214;244m'
SUBTEXT=$'\033[38;2;166;173;200m'
RESET=$'\033[0m'

# binding|action - same rows as the README cheat sheet table, kept in sync
# by hand (this is a small, curated display list, not something parsed out
# of i3/config, same shape as app-menu.sh's own LABELS/COMMANDS). Sorted
# alphabetically by key; where a key has more than one binding, the plain
# Mod+<key> form comes before any Mod+<modifier>+<key> form, and
# multi-modifier forms come after single-modifier ones - same rule the
# README table's rows follow.
ROWS=(
  "Mod+1..9|Switch to workspace 1-9"
  "Mod+shift+1..9|Move window to workspace 1-9"
  "Mod+a|AI window (Mistral Vibe CLI), toggle show/hide"
  "Mod+b|Split horizontal (for next window)"
  "Mod+c|Toggle caffeine (inhibit screen-lock/sleep)"
  "Mod+shift+c|Reload i3"
  "Mod+e|File manager (pcmanfm)"
  "Mod+shift+e|Exit i3 (with confirm)"
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
  "Mod+n|Toggle Do Not Disturb"
  "Mod+p|Printer setup"
  "Mod+shift+p|Power menu"
  "Print|Screenshot (flameshot)"
  "Mod+r|Resize mode (h/j/k/l, Return/Escape to exit)"
  "Mod+shift+r|Restart i3"
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
  "Mod+shift+w|Wallpaper picker (nitrogen)"
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
# window - see the AppMenuTask for_window rule in i3/config - matching how
# copyq/cliamp already float; everything else just runs directly.
LABELS=(
  $'  Desktop Theme'
  $'  Cursor Theme'
  $'  Set Screensaver Text/Image'
  $'  Preview Screensaver'
  $'  Set AI Window Folder'
  $'  Toggle Caffeine'
  $'  Toggle Do Not Disturb'
  $'  Music Player'
  $'  Clipboard History'
  $'  Colorpicker'
  $'  Lock Screen'
  $'  Power Menu'
  $'  Reload i3'
  $'  Restart i3'
  $'  Keybinding Help'
)
COMMANDS=(
  "~/.local/bin/polybar-theme.sh"
  "~/.local/bin/cursor-theme.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/set-screensaver-text.sh"
  "kitty --class Screensaver -e ~/.local/bin/screensaver.sh"
  "kitty --class AppMenuTask -e ~/.local/bin/set-ai-window-folder.sh"
  "~/.local/bin/caffeine-toggle.sh"
  "~/.local/bin/dnd-toggle.sh"
  "~/.local/bin/cliamp-toggle.sh"
  "copyq toggle"
  "~/.local/bin/colorpicker.sh"
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

log "Writing cliamp-toggle.sh..."
cat > "$BIN/cliamp-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Toggles the floating Cliamp window via i3's scratchpad instead of leaving
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
# (confirmed: i3-msg reports success:false, does nothing). So the first
# hide request for a freshly-launched window falls back to `move
# scratchpad`; every request after that is a real, working toggle.
#
# i3's own remembered scratchpad geometry isn't reliable here - confirmed
# directly: after being hidden and shown again, the window reappeared at
# rect (-350, -250), well off a 1920x1200 screen, instead of the centered
# position it had before. Reassert size/position explicitly every time
# rather than trusting `scratchpad show` to restore it correctly.
# Harmless when the window ends up hidden instead of shown (confirmed:
# repositioning a scratchpad-hidden window doesn't un-hide it).
if pgrep -x cliamp >/dev/null; then
  i3-msg '[con_mark="cliamp-scratch"] scratchpad show' | grep -q '"success":true' \
    || i3-msg '[con_mark="cliamp-scratch"] move scratchpad' >/dev/null
  i3-msg '[con_mark="cliamp-scratch"] resize set 700 500, move position center' >/dev/null
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
# Toggles a floating "AI window" running Mistral Vibe CLI (`vibe`) via i3's
# scratchpad - same show/hide-without-killing pattern as cliamp-toggle.sh,
# so an in-progress Vibe conversation/session isn't lost by just tucking
# the window away.
#
# Doesn't copy cliamp-toggle.sh's "try `scratchpad show`, fall back to
# `move scratchpad` on failure" approach - confirmed live that it's
# unreliable here: `scratchpad show` on this window reported success:true
# while actually leaving it shoved off-screen (negative coordinates) on its
# *current* workspace, still counted visible/focused, instead of actually
# parking it in i3's hidden __i3_scratch workspace. Asking i3 directly
# which workspace the marked container is on right now and picking the one
# correct action for that state sidesteps the ambiguous return value
# entirely: no mark found -> launch fresh; already in __i3_scratch -> show
# it; anywhere else (i.e. currently visible) -> hide it. Also sidesteps
# tracking `vibe` by process name, which wouldn't work anyway - it's a
# Python console_scripts entry point, so under `ps`/`pgrep -x` it reports
# as "python3", never "vibe".
mark=ai-window-scratch

current_ws=$(i3-msg -t get_tree | python3 -c "
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
  i3-msg "[con_mark=\"$mark\"] scratchpad show" >/dev/null
  i3-msg "[con_mark=\"$mark\"] resize set 900 650, move position center" >/dev/null
else
  i3-msg "[con_mark=\"$mark\"] move scratchpad" >/dev/null
fi
EOF
chmod +x "$BIN/ai-window-toggle.sh"

log "Writing claude-desktop-toggle.sh..."
cat > "$BIN/claude-desktop-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# Toggles Claude Desktop via i3's scratchpad - same show/hide-without-
# killing pattern as ai-window-toggle.sh/cliamp-toggle.sh, so an
# in-progress conversation isn't lost by just tucking the window away.
# Same direct "ask i3 which workspace the marked container is on right
# now" approach as ai-window-toggle.sh, for the same reason: `scratchpad
# show`'s own success:true return doesn't reliably mean the window is
# actually visible.
mark=claude-desktop-scratch

current_ws=$(i3-msg -t get_tree | python3 -c "
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
  i3-msg "[con_mark=\"$mark\"] scratchpad show" >/dev/null
  i3-msg "[con_mark=\"$mark\"] resize set 1200 850, move position center" >/dev/null
else
  i3-msg "[con_mark=\"$mark\"] move scratchpad" >/dev/null
fi
EOF
chmod +x "$BIN/claude-desktop-toggle.sh"

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

# Qogir cursor theme (all 6 real variants - the upstream -Light suffix
# variants are skipped, since they're just aliases with identical cursor
# art to their non-Light counterpart, differing only in icon-theme colors
# this cursor-only install never uses). i3 itself has no cursor-theme
# concept of its own - it's a bare window manager that never sets one, so
# without this the pointer just falls back to X11's stock default
# everywhere (GTK apps too: gtk-cursor-theme-size was already being set
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
   Mod+shift+g       colorpicker (click a pixel, hex copied to clipboard)
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