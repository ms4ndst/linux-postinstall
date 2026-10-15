#!/usr/bin/env python3
"""Port fedora-sway-setup.sh -> openmandriva-sway-setup.sh.

The overwhelming majority of the source - every heredoc config, the HANCORE
theme pipeline, all helper scripts - is distro-independent and is carried
over byte-for-byte. Only the package-manager surface changes, following the
same methodology as this repo's i3 OpenMandriva port:

  - OpenMandriva repository preamble: detect the repo tree (rock / rolling /
    cooker / release) and enable extra/restricted/non-free, dnf --refresh
    makecache
  - dnf install with --setopt=strict=0 (skip missing names instead of
    aborting) + a warn fallback, because several Fedora names aren't
    packaged on OpenMandriva at all
  - Package renames verified against OpenMandriva's actual repository
    metadata (rock x86_64 main/release + extra + restricted + non-free,
    fetched from abf-downloads.openmandriva.org):
      rofi-wayland     -> (source build; OM's rofi 1.7.8 is X11-only - its
                          requires list has no libwayland-client)
      network-manager-applet -> networkmanager-applet
      ImageMagick      -> imagemagick
      pipewire-pulseaudio -> pipewire-pulse
      jetbrains-mono-fonts -> fonts-ttf-nerd-jetbrains-mono (the Nerd-patched
                          font itself, so the section-2 download is skipped)
      dex-autostart    -> (dropped; systemd's xdg-autostart-generator)
      pasystray        -> (dropped; never autostarted anyway)
      solaar-udev      -> (dropped; solaar ships its own udev rules)
      pipx             -> python-pipx (Rolling only on OM; Rock gets pipx
                          from the upstream pipx.pyz for the source builds)
      gammastep / udiskie / swappy: not on Rock (gammastep/udiskie are
                          built or pipx-installed here; swappy is skipped -
                          screenshot.sh already falls back to save+clipboard)
      swaylock-effects build deps: wayland-devel -> lib64wayland-devel,
                          cairo-devel -> lib64cairo-devel,
                          pam-devel -> lib64pam-devel,
                          gdk-pixbuf2-devel -> lib64gdk_pixbuf2.0-devel,
                          ninja-build -> ninja
  - OM's packaged dunst is 1.6.1 (2021) - too old for this rice's themes:
    the current dunst is built from source with Wayland enabled
  - The screensaver/set-logo default artwork uses OpenMandriva's distro
    logo instead of fedora-logos, and fastfetch's OpenMandriva logo
  - znver1 added to the update-count arch regexes (OpenMandriva's
    optimized x86 arch)

Every step is anchored on unique strings - never line numbers. WARN on a
stale anchor so drift gets noticed.

Usage: python3 -I port_openmandriva.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "fedora-sway-setup.sh"
DST = HERE.parent / "openmandriva-sway-setup.sh"

OM_PREAMBLE = r'''
# --- OpenMandriva repository setup (from this repo's i3 OM port) ----------
OM_ARCH="$(uname -m)"
[ "$OM_ARCH" = "i386" ] || [ "$OM_ARCH" = "i586" ] && OM_ARCH="i686"

om_probe_enabled() {
  local repoid="$1"
  if dnf --dump-repo-config "$repoid" &>/dev/null; then
    dnf --dump-repo-config "$repoid" 2>/dev/null | grep -Eq '^enabled *= *(1|true|on)'
    return
  fi
  local f
  for f in /etc/yum.repos.d/openmandriva-*.repo; do
    [ -f "$f" ] || continue
    if awk -v id="[$repoid]" '
      BEGIN { found = 0; enabled = 0 }
      /^\[/ { inrepo = ($0 == id); if (inrepo) found = 1; next }
      inrepo && /^enabled[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, "")
        enabled = ($0 ~ /^(1|true|on)$/) ? 1 : 0
        exit
      }
      END { exit (found && enabled) ? 0 : 1 }
    ' "$f"; then
      return 0
    fi
  done
  return 1
}

detect_repo_tree() {
  OM_REPO_TREE=""
  local tree
  for tree in cooker rolling rock release "${VERSION_ID:-}"; do
    [ -n "$tree" ] || continue
    if om_probe_enabled "${tree}-${OM_ARCH}"; then
      OM_REPO_TREE="$tree"; return 0
    fi
  done
  if grep -qi "rolling" /etc/os-release 2>/dev/null; then
    OM_REPO_TREE="rolling"
  elif grep -qi "cooker" /etc/os-release 2>/dev/null; then
    OM_REPO_TREE="cooker"
  elif grep -qi "rock" /etc/os-release 2>/dev/null; then
    OM_REPO_TREE="rock"
  else
    OM_REPO_TREE="release"
  fi
  return 0
}

enable_om_repo() {
  local sub="$1"
  [ -z "${OM_REPO_TREE:-}" ] && detect_repo_tree
  local repoid="${OM_REPO_TREE}-${OM_ARCH}-${sub}"
  om_probe_enabled "$repoid" && return 0
  if sudo dnf config-manager setopt "$repoid.enabled=1" &>/dev/null; then
    return 0
  fi
  if sudo dnf config-manager --enable "$repoid" &>/dev/null; then
    return 0
  fi
  local f
  for f in /etc/yum.repos.d/openmandriva-*.repo; do
    [ -f "$f" ] || continue
    if grep -q "^\[$repoid\]" "$f" 2>/dev/null; then
      local tmp
      tmp=$(mktemp)
      if awk -v id="[$repoid]" '
        /^\[/ { inrepo = ($0 == id); print; next }
        inrepo && /^enabled[[:space:]]*=/ { print "enabled=1"; next }
        { print }
      ' "$f" > "$tmp" && sudo cp "$tmp" "$f"; then
        rm -f "$tmp"
        return 0
      fi
      rm -f "$tmp"
    fi
  done
  warn "Could not enable '$repoid' - check /etc/yum.repos.d/openmandriva-*.repo"
  return 1
}

detect_repo_tree
# OpenMandriva's optional repos are extra, restricted and non-free; "extra"
# carries the community packages (copyq, solaar, fonts-ttf-nerd-jetbrains-*
# and more that this install pulls in).
log "Enabling OpenMandriva extra/restricted/non-free repositories (tree: $OM_REPO_TREE, arch: $OM_ARCH)..."
enable_om_repo "extra"
enable_om_repo "restricted"
enable_om_repo "non-free"
sudo dnf --refresh makecache 2>/dev/null || true

'''

OM_SOURCE_BUILDS = r'''
# ----------------------------------------------------------------------------
# 1a. Tools this rice needs that OpenMandriva doesn't package (or packages
#     too old) - built or pipx-installed, each best-effort with warn fallback
# ----------------------------------------------------------------------------
om_build_deps() {
  sudo dnf install -y --setopt=strict=0 "$@" >/dev/null 2>&1 || true
}
om_local_lib_path() {
  [ -f /etc/ld.so.conf.d/usr-local.conf ] \
    || printf '/usr/local/lib\n/usr/local/lib64\n' | sudo tee /etc/ld.so.conf.d/usr-local.conf >/dev/null
  sudo ldconfig 2>/dev/null || true
}
om_fetch_tarball() {  # <url> <dest dir> - downloads and unpacks, prints the top-level dir
  local url="$1" dest="$2"
  curl -fsSL --retry 3 -o "$dest/src.tar.gz" "$url" 2>/dev/null || return 1
  tar -xzf "$dest/src.tar.gz" -C "$dest" || return 1
  find "$dest" -mindepth 1 -maxdepth 1 -type d | head -1
}

# rofi - OpenMandriva ships rofi 1.7.8 built X11-ONLY (its requires list has
# no libwayland-client, verified against the repo metadata), so the bar's
# launchers/menus would all fail on sway. Build upstream rofi (which has
# Wayland support compiled into the same binary since 1.7.5) into
# /usr/local - it shadows the packaged X11-only build via PATH order.
# Gate: OpenMandriva's packaged rofi 1.7.x (Rock) is X11-only, but rofi 2.0
# (Rolling/ROME) merged the Wayland support upstream (libwayland-client is in
# its requires, verified against the rolling repo metadata) - so the source
# build is ONLY needed when the packaged rofi is missing or older than 2.0.
om_rofi_ver() { rofi -v 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }
if [ ! -x /usr/local/bin/rofi ] \
    && { ! command -v rofi >/dev/null 2>&1 \
         || [ "$(printf '%s\n2.0\n' "$(om_rofi_ver)" | sort -V | head -1)" != "2.0" ]; }; then
  log "Building rofi-wayland from source (the packaged rofi is X11-only)..."
  # NOT upstream davatorium/rofi 1.7.x - that is X11-only (its meson has no
  # wayland option at all). Wayland rofi is the lbonn/rofi fork that Fedora
  # packages as "rofi-wayland". Build it Wayland-ONLY (-Dxcb=disabled skips
  # the entire xcb stack: xcb-cursor, cairo-xcb, startup-notification etc.
  # that Rock doesn't all carry). Deps are OM's real package names (verified
  # against the rock repo metadata; on Rolling this block never runs).
  om_build_deps meson ninja gcc glibc-devel pkgconf \
    lib64glib2.0-devel lib64cairo-devel lib64pango1.0-devel lib64pangocairo1.0-devel \
    libxkbcommon-devel lib64gdk_pixbuf2.0-devel lib64wayland-devel wayland-protocols-devel
  OMT="$(mktemp -d)"
  if d="$(om_fetch_tarball https://github.com/lbonn/rofi/archive/refs/tags/1.7.9%2Bwayland1.tar.gz "$OMT")" \
      && meson setup "$OMT/build" "$d" --buildtype release --prefix /usr/local \
           -Dwayland=enabled -Dxcb=disabled >/dev/null 2>&1 \
      && ninja -C "$OMT/build" >/dev/null 2>&1 \
      && sudo ninja -C "$OMT/build" install >/dev/null 2>&1 \
      && [ -x /usr/local/bin/rofi ]; then
    log "rofi-wayland 1.7.9 installed to /usr/local/bin - it shadows the X11-only packaged one."
  else
    warn "rofi-wayland build failed - launchers/menus won't work; check the build deps above."
  fi
  rm -rf "$OMT"
fi

# gammastep (night light) - packaged on Rolling, not on Rock: build the
# official release there (gitlab.com/chinstrap/gammastep, autotools), with
# Wayland enabled this time (this is the sway rice).
if ! command -v gammastep >/dev/null 2>&1 && [ ! -x /usr/local/bin/gammastep ]; then
  log "Building gammastep from source (not packaged for this OpenMandriva release)..."
  om_build_deps make gcc glibc-devel pkgconf autoconf automake libtool gettext intltool \
    'pkgconfig(x11)' 'pkgconfig(xcb)' 'pkgconfig(xcb-randr)' 'pkgconfig(xxf86vm)' 'pkgconfig(libdrm)' \
    'pkgconfig(glib-2.0)' 'pkgconfig(gio-2.0)' 'pkgconfig(wayland-client)'
  OMT="$(mktemp -d)"
  if d="$(om_fetch_tarball https://gitlab.com/chinstrap/gammastep/-/archive/v2.0.11/gammastep-v2.0.11.tar.gz "$OMT")" \
      && (cd "$d" && ./bootstrap >/dev/null 2>&1 \
          && ./configure --prefix=/usr/local --disable-gui --enable-wayland --disable-geoclue2 \
               --with-systemduserunitdir=no >/dev/null 2>&1 \
          && make -j"$(nproc)" >/dev/null 2>&1) \
      && sudo make -C "$d" install >/dev/null 2>&1 \
      && [ -x /usr/local/bin/gammastep ]; then
    log "gammastep installed to /usr/local/bin."
  else
    warn "gammastep build failed - no night-light colour shift."
  fi
  rm -rf "$OMT"
fi

# dunst - OpenMandriva packages dunst 1.6.1 (2021), which predates the
# placement keys and dunstctl commands this rice's generated themes rely on.
# Build the current release with Wayland enabled (sway), install to
# /usr/local, and remove the packaged 1.6.1 with plain `rpm -e` (not dnf,
# which would also autoremove libraries the new build links against).
om_dunst_ver() { dunst --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1; }
if [ "$(printf '%s\n1.7\n' "$(om_dunst_ver)" | sort -V | head -1)" != "1.7" ]; then
  log "Building dunst from source (OpenMandriva's dunst $(om_dunst_ver) is too old for this rice)..."
  om_build_deps make gcc glibc-devel pkgconf \
    'pkgconfig(dbus-1)' 'pkgconfig(wayland-client)' 'pkgconfig(wayland-cursor)' \
    'pkgconfig(glib-2.0)' 'pkgconfig(gio-2.0)' 'pkgconfig(pangocairo)' 'pkgconfig(cairo)'
  DUNST_TAG=$(curl -fsSL https://api.github.com/repos/dunst-project/dunst/releases/latest 2>/dev/null \
    | grep -oE '"tag_name":[[:space:]]*"v[0-9.]+"' | grep -oE 'v[0-9.]+')
  [ -z "$DUNST_TAG" ] && DUNST_TAG=v1.12.1
  OMT="$(mktemp -d)"
  if d="$(om_fetch_tarball "https://github.com/dunst-project/dunst/archive/refs/tags/$DUNST_TAG.tar.gz" "$OMT")" \
      && make -C "$d" CC=gcc WAYLAND=1 SYSTEMD=0 PREFIX=/usr/local -j"$(nproc)" >/dev/null 2>&1 \
      && sudo make -C "$d" WAYLAND=1 SYSTEMD=0 PREFIX=/usr/local install >/dev/null 2>&1 \
      && [ -x /usr/local/bin/dunst ]; then
    rpm -q dunst >/dev/null 2>&1 && sudo rpm -e --nodeps dunst 2>/dev/null
    log "dunst installed to /usr/local/bin (the packaged 1.6.1 was removed)."
  else
    warn "dunst build failed - notifications will use the old packaged version (placement may look off)."
  fi
  rm -rf "$OMT"
fi

# udiskie (USB automount + tray) - Python, from PyPI via pipx, with access to
# the system's PyGObject/GTK bindings (--system-site-packages).
if ! command -v udiskie >/dev/null 2>&1 && [ ! -x /usr/local/bin/udiskie ]; then
  log "Installing udiskie (pipx - not packaged for OpenMandriva)..."
  om_build_deps python python-ensurepip udisks python-gi \
    'typelib(Gtk) = 3.0' 'typelib(Notify)' ntfs-3g exfatprogs dosfstools
  OM_PIPX=""
  if command -v pipx >/dev/null 2>&1; then
    OM_PIPX="$(command -v pipx)"
  elif sudo curl -fsSL --retry 3 -o /usr/local/bin/pipx https://github.com/pypa/pipx/releases/latest/download/pipx.pyz 2>/dev/null \
      && sudo chmod 755 /usr/local/bin/pipx; then
    OM_PIPX=/usr/local/bin/pipx
  fi
  if [ -n "$OM_PIPX" ] \
      && sudo env PATH="/usr/local/bin:$PATH" "$OM_PIPX" install --global --system-site-packages udiskie >/dev/null 2>&1 \
      && [ -x /usr/local/bin/udiskie ]; then
    log "udiskie installed to /usr/local/bin."
  else
    warn "udiskie install failed - USB drives won't be automounted."
  fi
fi

'''

DEX_REPLACEMENT = r'''# OpenMandriva doesn't ship dex-autostart, so use systemd's built-in
# systemd-xdg-autostart-generator instead (parses ~/.config/autostart and
# /etc/xdg/autostart .desktop files, respecting OnlyShowIn/NotShowIn).
exec sh -c 'systemctl --user set-environment XDG_CURRENT_DESKTOP=sway; systemctl --user daemon-reload; systemctl --user start xdg-desktop-autostart.target'
'''

HEADER = '''#!/usr/bin/env bash
# ============================================================================
# Sway "hackerbox" post-install script - OpenMandriva Linux (HANCORE waybar themes)
# Theme collection: HANCORE-linux/waybar-themes (github.com/HANCORE-linux/
#           waybar-themes, MIT), fetched at install time, adapted from
#           their Omarchy/Hyprland home to plain Sway, and wired
#           into this rice's theme switcher so one pick retints waybar,
#           rofi, kitty, dunst, starship, sway borders, GTK, Neovim and
#           VS Code together - the same mechanism the old embedded
#           Catppuccin collection used.
#
# Ported from this repo's fedora-sway-setup.sh. Almost all of this file -
# every heredoc config, the HANCORE theme pipeline, all helper scripts - is
# distro-independent and carried over byte-for-byte. Only the package-manager
# surface changes: OpenMandriva repo-tree detection + extra/restricted/
# non-free enabling, --setopt=strict=0 installs, verified package renames,
# and source builds for what OpenMandriva doesn't package (Wayland rofi,
# gammastep on Rock, current dunst, udiskie). swaylock-effects is built from
# source on both distros (as in the Fedora script).
#
# Installs: sway, swaybg, swayidle, swaylock(-effects, source), waybar,
#           kanshi, rofi (Wayland, source), dunst (source), kitty, swappy
#           (when packaged; screenshot.sh falls back to save+clipboard),
#           imagemagick, brightnessctl, playerctl, fastfetch, Nerd Font
#           (fonts-ttf-nerd-jetbrains-mono), tray helpers, GTK/icon/cursor
#           themes, rofi power menu, copyq clipboard history, udiskie USB
#           automount (pipx), pcmanfm file manager, gammastep night light,
#           volume/brightness OSD popups, cava + btop for the HANCORE
#           themes' audio/system widgets, CLIamp terminal music player
#           (Mod+m), an Omarchy-style app menu (Mod+alt+space) for this
#           rice's own utility scripts (including a floating on-screen
#           keybinding cheat sheet), + always-visible window borders and
#           tightened gaps.
# Idempotent-ish: safe to re-run, but back up existing configs first if you
# have your own dotfiles - this OVERWRITES the files listed below.
# ===============================================================================
'''


def main():
    src = SRC.read_text(encoding="utf-8")
    out = src
    misses = []

    def sub(old, new, count=1, why=""):
        nonlocal out
        n = out.count(old)
        if n < count:
            misses.append("%s (%d/%d found)%s" % (old[:60], n, count, ": " + why if why else ""))
            return
        out = out.replace(old, new, count)

    # ---- header ----------------------------------------------------------
    hdr_end = src.index("# ===============================================================================\nset -euo pipefail")
    out = out.replace(src[:hdr_end + len("# ===============================================================================\n")], HEADER, 1)

    # ---- dnf gate --------------------------------------------------------
    sub('  echo "This script targets Fedora (dnf not found). Aborting." >&2',
        '  echo "This script targets OpenMandriva Linux (dnf not found). Aborting." >&2')

    # ---- OM repo preamble: insert right before the stale-i3-cleanup block
    anchor = "# Remove stale i3-only bar scripts from a previous i3-rice install so the"
    sub(anchor, OM_PREAMBLE + anchor)

    # ---- snapper wording -------------------------------------------------
    sub("# Needs Btrfs + an existing \"root\" snapper config (Fedora's Btrfs-by-default",
        "# Needs Btrfs + an existing \"root\" snapper config (OpenMandriva with Btrfs\n"
        "# can create this via `snapper -c root create-config /` if not already present)")
    sub('--description "before fedora-sway-setup.sh"',
        '--description "before openmandriva-sway-setup.sh"')

    # ---- the main dnf install block -------------------------------------
    sub('''log "Installing Wayland stack + Sway + rice toolkit via dnf..."
sudo dnf install -y \\
  sway swaybg swayidle swaylock waybar kanshi \\
  cava btop \\
  grim slurp swappy wl-clipboard \\
  rofi-wayland dunst kitty \\
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \\
  network-manager-applet pasystray blueman lxqt-policykit pipewire-pulseaudio \\
  copyq udiskie pcmanfm gammastep libnotify gnome-calendar \\
  azote \\
  system-config-printer hplip \\
  lxappearance papirus-icon-theme \\
  fastfetch git curl unzip jq ImageMagick fortune-mod \\
  brightnessctl playerctl dex-autostart \\
  dnf-utils \\
  solaar solaar-udev \\
  pipx \\
  jetbrains-mono-fonts \\
  plymouth-plugin-script''',
        '''log "Installing Wayland stack + Sway + rice toolkit via dnf (--setopt=strict=0: names OpenMandriva doesn't carry are skipped, then built or substituted below)..."
# Package-name deltas verified against OpenMandriva's repository metadata:
#   rofi-wayland dropped (OM's rofi is X11-only; Wayland rofi is built from
#     source in section 1a), dex-autostart dropped (systemd's
#     xdg-autostart-generator takes over in the sway config), pasystray
#     dropped (never autostarted anyway), solaar-udev dropped (solaar ships
#     its own udev rules), network-manager-applet -> networkmanager-applet,
#     ImageMagick -> imagemagick, pipewire-pulseaudio -> pipewire-pulse,
#     jetbrains-mono-fonts -> fonts-ttf-nerd-jetbrains-mono (the Nerd-patched
#     font itself), pipx -> python-pipx (Rolling; Rock gets pipx from the
#     upstream pipx.pyz in section 1a). swappy/gammastep/udiskie aren't on
#     Rock - strict=0 skips them there and section 1a / screenshot.sh's
#     fallback cover them.
sudo dnf install -y --setopt=strict=0 \\
  sway swaybg swayidle swaylock waybar kanshi \\
  cava btop \\
  grim slurp swappy wl-clipboard \\
  dunst kitty \\
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \\
  networkmanager-applet blueman lxqt-policykit pipewire-pulse \\
  copyq udiskie pcmanfm gammastep libnotify gnome-calendar \\
  azote \\
  system-config-printer hplip \\
  lxappearance papirus-icon-theme \\
  fastfetch git curl unzip jq imagemagick fortune-mod \\
  brightnessctl playerctl \\
  dnf-utils \\
  solaar \\
  python-pipx \\
  fonts-ttf-nerd-jetbrains-mono \\
  plymouth-plugin-script \\
  || warn "The base package install reported errors - check the dnf output above."''')

    # ---- power-profiles-daemon: no tuned-ppd on OpenMandriva --------------
    sub('''# power-profiles-daemon backs the waybar power-profiles-daemon module in
# the HANCORE themes - but tuned-ppd (Fedora's tuned-based power-profiles
# provider, a common default) conflicts with it, so this is best-effort:
# with tuned-ppd installed the module is simply inert.
if ! sudo dnf install -y power-profiles-daemon >/dev/null 2>&1; then
  warn "power-profiles-daemon not installable (tuned-ppd conflict?) - the bar's power-profile widget will be inert; swap tuned-ppd out for power-profiles-daemon manually if you want it."
fi''',
        '''# power-profiles-daemon backs the waybar power-profiles-daemon module in
# the HANCORE themes. OpenMandriva carries it in its own repos (and has no
# Fedora-style tuned-ppd conflicting with it), so a plain install works.
if ! sudo dnf install -y power-profiles-daemon >/dev/null 2>&1; then
  warn "power-profiles-daemon not installable - the bar's power-profile widget will be inert."
fi''')

    # ---- section 1a: source builds, inserted before section 2's marker ----
    # The i3-cleanup + section-1 flow ends where section 2 (Nerd Font) starts.
    anchor2 = "# ----------------------------------------------------------------------------\n# 2. Nerd Font"
    sub(anchor2, OM_SOURCE_BUILDS + anchor2)

    # ---- swaylock-effects build deps: OM names ---------------------------
    sub('''    if sudo dnf install -y meson ninja-build wayland-devel wayland-protocols-devel \\
         libxkbcommon-devel cairo-devel gdk-pixbuf2-devel pam-devel scdoc \\
         >/dev/null 2>&1; then''',
        '''    if sudo dnf install -y --setopt=strict=0 meson ninja lib64wayland-devel wayland-protocols-devel \\
         libxkbcommon-devel lib64cairo-devel lib64gdk_pixbuf2.0-devel lib64pam-devel scdoc \\
         >/dev/null 2>&1; then''')

    # ---- sway config: dex -> systemd generator ---------------------------
    sub("exec dex-autostart -a -e sway\n", DEX_REPLACEMENT)

    # ---- screensaver logo: OpenMandriva artwork --------------------------
    sub('FEDORA_SVG="/usr/share/fedora-logos/fedora_logo.svg"',
        'OPENMANDRIVA_SVG="/usr/share/icons/hicolor/scalable/apps/openmandriva.svg"\n'
        '[ -f "$OPENMANDRIVA_SVG" ] || OPENMANDRIVA_SVG="/usr/share/icons/openmandriva.svg"\n'
        '[ -f "$OPENMANDRIVA_SVG" ] || OPENMANDRIVA_SVG="/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg"',
        count=2)
    out = out.replace('[ -f "$FEDORA_SVG" ]', '[ -f "$OPENMANDRIVA_SVG" ]')
    out = out.replace('magick -background none "$FEDORA_SVG" -auto-orient',
                      'magick -background none "$OPENMANDRIVA_SVG" -auto-orient', 2)
    out = out.replace('# Fall back to the old typed-letter banner if ImageMagick or the Fedora',
                      '# Fall back to the old typed-letter banner if ImageMagick or the distro')
    sub("  [ -s \"$LOGO\" ] || fastfetch --logo Fedora -s none > \"$LOGO\"",
        "  [ -s \"$LOGO\" ] || fastfetch --logo OpenMandriva -s none > \"$LOGO\"")
    sub('command -v fastfetch >/dev/null 2>&1 && fastfetch --logo Fedora -s none >"$LOGO"',
        'command -v fastfetch >/dev/null 2>&1 && fastfetch --logo OpenMandriva -s none >"$LOGO"')
    sub("  echo \"  Fedora:        sudo dnf install ImageMagick\" >&2",
        "  echo \"  OpenMandriva:  sudo dnf install imagemagick\" >&2")
    sub("for the Fedora default: \" INPUT", "for the distro default: \" INPUT")
    sub("# half-block art (█▀▄) the Fedora logo uses in screensaver.sh. Matches",
        "# half-block art (█▀▄) the distro logo uses in screensaver.sh. Matches")
    sub("# screensaver.sh's own lazy Fedora-logo generation, which only writes if",
        "# screensaver.sh's own lazy distro-logo generation, which only writes if")

    # ---- znver1 arch in the update-count regexes --------------------------
    sub(r"grep -cE '^\S+\.(x86_64|noarch|i686|aarch64|s390x|ppc64le)[[:space:]]'",
        r"grep -cE '^\S+\.(x86_64|noarch|i686|aarch64|znver1|s390x|ppc64le)[[:space:]]'",
        count=2)

    # ---- remaining prose --------------------------------------------------
# (that sentence lives in the header, already rewritten above)
    sub("# from source in section 11 - no usable Fedora package or COPR exists;",
        "# from source in section 11 - no usable Fedora package or COPR exists;", count=0)
    out = out.replace("# from source in section 11 - no usable Fedora package or COPR exists;",
                      "# from source in section 11 - no usable package or COPR exists on either distro;")
    sub("# 2. Nerd Font (JetBrainsMono) — official Fedora repos don't ship patched fonts",
        "# 2. Nerd Font (JetBrainsMono) — OpenMandriva ships the patched font\n"
        "#    (fonts-ttf-nerd-jetbrains-mono), so this section usually skips itself")

    # ---- Strata runtime deps: OpenMandriva package names ------------------
    sub('''  sudo dnf install -y \\
    gtk4 gtksourceview5 poppler-glib bubblewrap gvfs \\
    gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugin-libav \\
    ffmpeg ffmpegthumbnailer LibRaw \\
    >/dev/null 2>&1 || warn "Strata runtime deps reported errors - continuing anyway."''',
        '''  sudo dnf install -y --setopt=strict=0 \\
    gtk4.0 gtksourceview5 lib64poppler-glib bubblewrap gvfs \\
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav \\
    ffmpeg ffmpegthumbs lib64raw \\
    >/dev/null 2>&1 || warn "Strata runtime deps reported errors - continuing anyway."''')
    out = out.replace(
        "  # runtime deps per the upstream README (package names verified against\n"
        "  # the Fedora 44 repos); failures are non-fatal - the bar keeps pcmanfm.",
        "  # runtime deps per the upstream README (package names verified against\n"
        "  # OpenMandriva Rolling's repos); failures are non-fatal - the bar keeps pcmanfm.")
    out = out.replace("# plain Sway on Fedora:", "# plain Sway:")
    out = out.replace('"""Adapt HANCORE-linux/waybar-themes to this rice\'s Sway/Fedora setup.',
                      '"""Adapt HANCORE-linux/waybar-themes to this rice\'s Sway setup.')
    out = out.replace('"custom/gpu-usage",                     # gpu-usage-waybar not on Fedora',
                      '"custom/gpu-usage",                     # gpu-usage-waybar not packaged')
    out = out.replace('# "Caffeine" toggle - no packaged equivalent exists for Fedora (neither dnf',
                      '# "Caffeine" toggle - no packaged equivalent exists for this distro (neither dnf')
    out = out.replace("# naive line count. Relies on Fedora's own dnf-makecache.timer (enabled by",
                      "# naive line count. Relies on the distro's own dnf-makecache.timer (enabled by")
    out = out.replace("# Not packaged for Fedora. Builds cleanly from source with the vala/",
                      "# Not packaged. Builds cleanly from source with the vala/")
    out = out.replace("for Fedora. This implements the subset of its CLI the HANCORE configs use",
                      "for Fedora but also absent on OpenMandriva. This implements the subset of its CLI the HANCORE configs use")

    # ---- final summary mentions -------------------------------------------
    out = out.replace("Sway session", "Sway session")  # no-op guard


    # ---- remaining Fedora prose in the ported output ---------------------
    out = out.replace("# has no usable Fedora package: the only COPR carries an fc35-era build that",
                      "# has no usable distro package: the only COPR carries an fc35-era Fedora build that")
    out = out.replace("# Fedora binary without touching its package. Best-effort: plain swaylock",
                      "# distro's packaged swaylock without touching its package. Best-effort: plain swaylock")
    out = out.replace("# conversion screensaver.sh runs on the Fedora logo SVG.",
                      "# conversion screensaver.sh runs on the distro logo SVG.")
    out = out.replace("# Reset mode - regenerates the exact same Fedora block-art logo",
                      "# Reset mode - regenerates the exact same distro block-art logo")
    out = out.replace("# pipeline against the real Fedora SVG, reusing this script's own",
                      "# pipeline against the real distro SVG, reusing this script's own")
    out = out.replace("# Same fallback screensaver.sh itself uses if the Fedora SVG isn't",
                      "# Same fallback screensaver.sh itself uses if the distro SVG isn't")
    out = out.replace("# installed (non-Fedora system) or the pipeline above produced nothing.",
                      "# installed or the pipeline above produced nothing.")
    out = out.replace("# correctly the same way the Fedora SVG is in screensaver.sh. Otherwise",
                      "# correctly the same way the distro SVG is in screensaver.sh. Otherwise")
    out = out.replace("# visual scale as the block Fedora logo (which targets an 80-column",
                      "# visual scale as the block distro logo (which targets an 80-column")
    out = out.replace("# Not packaged for Fedora - vendor curl|sh installer fetches a prebuilt",
                      "# Not packaged - vendor curl|sh installer fetches a prebuilt")
    out = out.replace("for Fedora but also absent on OpenMandriva. This implements the subset",
                      "not packaged here either. This implements the subset")

    if misses:
        print("WARN: %d stale anchors:" % len(misses))
        for m in misses:
            print("  -", m)
    DST.write_text(out, encoding="utf-8")
    print("wrote %s (%d lines)" % (DST, out.count("\n") + 1))
    return 1 if misses else 0


if __name__ == "__main__":
    sys.exit(main())
