#!/usr/bin/env python3
"""Port fedora-niri-setup.sh -> openmandriva-niri-setup.sh.

Mirrors sway-build/port_openmandriva.py (the Sway OM port): the overwhelming
majority of the source - the niri config, every heredoc config, the HANCORE
theme pipeline, all helper scripts - is distro-independent and carried over
byte-for-byte. Only the package-manager surface changes.

To avoid two copies of the OpenMandriva infrastructure drifting apart, the
repo-setup preamble and the source-build section are IMPORTED from the Sway
port and reused verbatim (same rofi/dunst/gammastep/udiskie builds). This port
then layers on what is niri-specific:

  - niri itself is PACKAGED on OpenMandriva Rolling (ROME) and Cooker (verified
    via repology / the OpenMandrivaAssociation/niri package), so the Fedora
    yalter/niri COPR block is dropped entirely - niri comes straight from the
    dnf install. An older edition (Rock) without the package is caught by the
    existing mandatory-niri check, which bails with a clear message.
  - the niri config's `spawn-sh-at-startup ... dex-autostart` becomes a systemd
    xdg-autostart-generator spawn (OpenMandriva ships no dex-autostart), the
    niri analogue of the Sway port's dex replacement.
  - the Sway-only wdisplays source build is removed; niri uses nwg-displays,
    which is pipx-installed here when OpenMandriva doesn't package it.
  - satty is installed from its upstream GitHub release binary (not packaged on
    OpenMandriva); screenshot.sh falls back to a plain save+copy if that fails.
  - package renames shared with the Sway port (network-manager-applet ->
    networkmanager-applet, ImageMagick -> imagemagick, pipewire-pulseaudio ->
    pipewire-pulse, pipx -> python-pipx, jetbrains-mono-fonts ->
    fonts-ttf-nerd-jetbrains-mono, solaar-udev / dex-autostart dropped) plus
    the niri-only python3-gobject -> python-gobject3, python3-cairo ->
    python-cairo, gtk4 -> gtk4.0. --setopt=strict=0 skips any name OpenMandriva
    doesn't carry instead of aborting.

Every step is anchored on unique strings - never line numbers. WARN on a stale
anchor so drift gets noticed. Run the Fedora build first, then this.

Usage: python3 -I port_openmandriva_niri.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
SRC = ROOT / "fedora-niri-setup.sh"
DST = ROOT / "openmandriva-niri-setup.sh"

# Reuse the Sway port's OpenMandriva infrastructure verbatim (DRY - the repo
# treats the OM port as byte-for-byte parity; one source of truth for the repo
# preamble and the rofi/dunst/gammastep/udiskie builds).
sys.path.insert(0, str(ROOT / "sway-build"))
import port_openmandriva as sp  # noqa: E402

OM_PREAMBLE = sp.OM_PREAMBLE

# Niri source-build section = the Sway one MINUS the wdisplays block (niri uses
# nwg-displays) PLUS an nwg-displays pipx install.
NWG_DISPLAYS_BLOCK = r'''# nwg-displays (the niri/sway display-layout GUI wired to the app menu's
# "Display Settings") - OpenMandriva may not package it, so install it from PyPI
# via pipx when missing, with access to the system GTK/PyGObject bindings
# (--system-site-packages). It calls wlr-randr/niri at runtime. wlr-randr (CLI)
# and ~/.local/bin/arrange-displays.sh (Mod+Shift+o) manage monitors without it,
# so this is best-effort like the rest of section 1a.
if ! command -v nwg-displays >/dev/null 2>&1; then
  log "Installing nwg-displays (pipx - not packaged for OpenMandriva)..."
  om_build_deps python python-ensurepip python-gi wlr-randr \
    'typelib(Gtk) = 3.0' 'typelib(GtkLayerShell)' gtk-layer-shell
  OM_PIPX=""
  if command -v pipx >/dev/null 2>&1; then
    OM_PIPX="$(command -v pipx)"
  elif sudo curl -fsSL --retry 3 -o /usr/local/bin/pipx https://github.com/pypa/pipx/releases/latest/download/pipx.pyz 2>/dev/null \
      && sudo chmod 755 /usr/local/bin/pipx; then
    OM_PIPX=/usr/local/bin/pipx
  fi
  if [ -n "$OM_PIPX" ] \
      && sudo env PATH="/usr/local/bin:$PATH" "$OM_PIPX" install --global --system-site-packages nwg-displays >/dev/null 2>&1 \
      && command -v nwg-displays >/dev/null 2>&1; then
    log "nwg-displays installed."
  else
    warn "nwg-displays install failed - use Mod+Shift+o (arrange-displays) or wlr-randr (CLI) for monitor management."
  fi
fi

'''

_sb = sp.OM_SOURCE_BUILDS
_wd = "# wdisplays (the Wayland/wlroots display GUI"
if _wd in _sb:
    _sb = _sb[:_sb.index(_wd)]
else:
    print("WARN: wdisplays marker not found in the Sway source-builds - carrying it over as-is")
OM_SOURCE_BUILDS_NIRI = _sb.rstrip("\n") + "\n\n" + NWG_DISPLAYS_BLOCK.rstrip("\n") + "\n\n"

# niri comes from OpenMandriva's own repos - the OM repo preamble replaces the
# Fedora COPR enable, so the repos are live before the dnf install below.
OM_NIRI_SOURCE = OM_PREAMBLE + '''# niri is PACKAGED in OpenMandriva's own repositories (Rolling/ROME and Cooker,
# verified against the repo metadata) - no COPR is needed, unlike Fedora. It is
# pulled in by the dnf install below. On an older edition (e.g. Rock) that
# predates the niri package, switch to ROME/Cooker: the mandatory check further
# down bails with a clear message rather than configuring an absent compositor.
'''

# satty: GitHub release binary (assets are satty-<arch>-unknown-linux-gnu.tar.gz,
# unversioned filename under the vX.Y.Z tag).
OM_SATTY = r'''# satty (screenshot annotator) - not packaged on OpenMandriva; install the
# upstream GitHub release binary into /usr/local/bin. screenshot.sh falls back
# to a plain save+copy if this fails.
if ! command -v satty >/dev/null 2>&1; then
  log "Installing satty from its GitHub release (not packaged for OpenMandriva)..."
  case "$(uname -m)" in
    x86_64)  __satty_arch="x86_64" ;;
    aarch64) __satty_arch="aarch64" ;;
    *)       __satty_arch="" ;;
  esac
  if [ -n "$__satty_arch" ]; then
    __satty_tag=$(curl -fsSL https://api.github.com/repos/gabm/Satty/releases/latest 2>/dev/null \
      | grep -oE '"tag_name":[[:space:]]*"v[0-9.]+"' | grep -oE 'v[0-9.]+')
    [ -z "$__satty_tag" ] && __satty_tag=v0.22.0
    __satty_tmp="$(mktemp -d)"
    if curl -fsSL --retry 3 --max-time 120 -o "$__satty_tmp/satty.tar.gz" \
         "https://github.com/gabm/Satty/releases/download/${__satty_tag}/satty-${__satty_arch}-unknown-linux-gnu.tar.gz" 2>/dev/null \
       && tar -xzf "$__satty_tmp/satty.tar.gz" -C "$__satty_tmp" 2>/dev/null \
       && __satty_bin="$(find "$__satty_tmp" -type f -name satty | head -1)" \
       && [ -n "$__satty_bin" ] \
       && sudo install -m755 "$__satty_bin" /usr/local/bin/satty; then
      log "satty installed to /usr/local/bin."
    else
      warn "satty install failed - screenshots fall back to a plain save+copy. Install satty later (github.com/gabm/Satty)."
    fi
    rm -rf "$__satty_tmp"
  fi
fi
'''

DEX_REPLACEMENT_NIRI = (
    'spawn-sh-at-startup "systemctl --user set-environment XDG_CURRENT_DESKTOP=niri; '
    'systemctl --user daemon-reload; systemctl --user start xdg-desktop-autostart.target"'
)

HEADER = '''#!/usr/bin/env bash
# ============================================================================
# Niri "hackerbox" post-install script - OpenMandriva Linux (HANCORE waybar themes)
#
# A scrolling-tiling Wayland rice built on niri (github.com/YaLTeR/niri), the
# sibling of this repo's Sway rice. It reuses the SAME theme collection and
# switcher: HANCORE-linux/waybar-themes, fetched and adapted at install time, so
# one pick retints waybar, rofi, kitty, dunst, starship, the niri focus-ring,
# GTK, Neovim and VS Code together.
#
# Ported from this repo's fedora-niri-setup.sh. Almost all of this file - the
# niri config, every heredoc config, the HANCORE theme pipeline, all helper
# scripts - is distro-independent and carried over byte-for-byte. Only the
# package-manager surface changes: OpenMandriva repo-tree detection +
# extra/restricted/non-free enabling, --setopt=strict=0 installs, verified
# package renames, and source/pip/binary installs for what OpenMandriva doesn't
# package (Wayland rofi, current dunst, gammastep on Rock, udiskie, nwg-displays,
# satty). niri itself is PACKAGED on OpenMandriva Rolling (ROME) and Cooker - no
# COPR is needed (unlike Fedora); an older edition without the niri package is
# caught by the mandatory check below.
#
# Installs: niri (OpenMandriva repos), waybar, swaybg, swayidle, swaylock, rofi
#           (Wayland, source), dunst (source), kitty, grim/slurp/satty (GitHub
#           release binary; screenshot.sh falls back to save+copy if absent),
#           imagemagick, brightnessctl, playerctl, fastfetch, Nerd Font
#           (fonts-ttf-nerd-jetbrains-mono), tray helpers, GTK/icon themes,
#           copyq, udiskie (pipx), gammastep, azote, nwg-displays (pipx),
#           volume/brightness OSD popups, and NiriMod (github.com/srinivasr/
#           NiriMod) - a GTK4 settings editor for niri, bound to Mod+Shift+S.
#
# Idempotent-ish: safe to re-run, but back up existing configs first if you
# have your own dotfiles - this OVERWRITES the files listed above.
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

    def soft(old, new):
        """Prose replacement that is fine to be absent (no miss warning)."""
        nonlocal out
        out = out.replace(old, new)

    # ---- header ----------------------------------------------------------
    marker = "# ===============================================================================\n"
    hdr_end = src.index("# ===============================================================================\nset -euo pipefail")
    out = out.replace(src[:hdr_end + len(marker)], HEADER, 1)

    # ---- dnf gate --------------------------------------------------------
    sub('  echo "This script targets Fedora (dnf not found). Aborting." >&2',
        '  echo "This script targets OpenMandriva Linux (dnf not found). Aborting." >&2')

    # ---- snapper description ---------------------------------------------
    sub('--description "before fedora-niri-setup.sh"',
        '--description "before openmandriva-niri-setup.sh"')

    # ---- COPR enable block -> OM repo preamble + "niri from OM repos" note -
    sub('''# niri is not in Fedora's repos; the upstream author maintains the yalter/niri
# COPR (stable). dnf5's copr plugin ships with dnf-plugins-core.
log "Enabling the yalter/niri COPR (upstream niri builds for Fedora)..."
sudo dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
if ! sudo dnf copr enable -y yalter/niri 2>/dev/null; then
  warn "Could not enable the yalter/niri COPR automatically. If niri fails to install below, enable it manually: sudo dnf copr enable yalter/niri"
fi''',
        OM_NIRI_SOURCE.rstrip("\n"))

    # ---- main dnf install block ------------------------------------------
    sub('''log "Installing niri + the Wayland rice toolkit via dnf..."
sudo dnf install -y \\
  niri \\
  waybar swaybg swayidle swaylock \\
  cava btop \\
  grim slurp wl-clipboard \\
  rofi-wayland dunst kitty \\
  xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \\
  network-manager-applet blueman lxqt-policykit pipewire-pulseaudio wireplumber \\
  copyq udiskie gammastep libnotify gnome-calendar \\
  azote \\
  system-config-printer \\
  lxappearance papirus-icon-theme adwaita-cursor-theme \\
  fastfetch git curl unzip jq ImageMagick fortune-mod xdotool \\
  brightnessctl playerctl pipx dex-autostart dnf-utils nwg-displays \\
  solaar solaar-udev evolution-data-server \\
  gtk4 libadwaita python3-gobject python3-cairo \\
  jetbrains-mono-fonts \\
  || warn "Some packages failed to install - check the dnf output above; the rice still works without the optional ones."''',
        '''log "Installing niri + the Wayland rice toolkit via dnf (--setopt=strict=0: names OpenMandriva doesn't carry are skipped, then built or substituted below)..."
# Package-name deltas verified against OpenMandriva's repository metadata:
#   rofi-wayland dropped (OM's rofi is X11-only; Wayland rofi is built from
#     source in section 1a), dex-autostart dropped (systemd's
#     xdg-autostart-generator takes over in the niri config), solaar-udev
#     dropped (solaar ships its own udev rules), network-manager-applet ->
#     networkmanager-applet, ImageMagick -> imagemagick, pipewire-pulseaudio ->
#     pipewire-pulse, pipx -> python-pipx (Rolling; Rock gets pipx from the
#     upstream pipx.pyz in section 1a), jetbrains-mono-fonts ->
#     fonts-ttf-nerd-jetbrains-mono, gtk4 -> gtk4.0, python3-gobject ->
#     python-gobject3, python3-cairo -> python-cairo. gammastep/udiskie aren't
#     on Rock - strict=0 skips them and section 1a covers them. satty and
#     nwg-displays are installed further down (GitHub release binary / pipx)
#     when dnf doesn't carry them.
sudo dnf install -y --setopt=strict=0 \\
  niri \\
  waybar swaybg swayidle swaylock \\
  cava btop \\
  grim slurp wl-clipboard \\
  dunst kitty \\
  xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \\
  networkmanager-applet blueman lxqt-policykit pipewire-pulse wireplumber \\
  copyq udiskie gammastep libnotify gnome-calendar \\
  azote \\
  system-config-printer \\
  lxappearance papirus-icon-theme adwaita-cursor-theme \\
  fastfetch git curl unzip jq imagemagick fortune-mod xdotool \\
  brightnessctl playerctl python-pipx dnf-utils nwg-displays \\
  solaar evolution-data-server \\
  gtk4.0 libadwaita python-gobject3 python-cairo \\
  fonts-ttf-nerd-jetbrains-mono \\
  || warn "Some packages failed to install - check the dnf output above; the rice still works without the optional ones."''')

    # ---- mandatory-niri check: drop the COPR mention from the comment ----
    sub("# niri itself is mandatory - bail early with a clear message if the COPR step\n"
        "# did not land it, rather than writing configs for a compositor that is absent.",
        "# niri itself is mandatory - bail early with a clear message if the dnf install\n"
        "# did not land it, rather than writing configs for a compositor that is absent.")

    # ---- mandatory-niri bail message: no COPR on OpenMandriva ------------
    sub('''  warn "niri is not installed. Enable the COPR and install it, then re-run:"
  warn "  sudo dnf copr enable yalter/niri && sudo dnf install niri"''',
        '''  warn "niri is not installed. OpenMandriva packages niri in its Rolling (ROME)"
  warn "and Cooker repositories - switch to one of those editions, then re-run:"
  warn "  sudo dnf install niri"''')

    # ---- satty: GitHub release binary ------------------------------------
    sub('''# satty (screenshot annotator) - not always packaged; best-effort.
if ! command -v satty >/dev/null 2>&1; then
  sudo dnf install -y satty >/dev/null 2>&1 \\
    || warn "satty not available via dnf - screenshots fall back to a plain save+copy. Install satty later for annotation (github.com/gabm/Satty)."
fi''',
        OM_SATTY.rstrip("\n"))

    # ---- section 1a source builds, inserted before section 2 -------------
    anchor2 = "# ----------------------------------------------------------------------------\n# 2. Nerd Font"
    sub(anchor2, OM_SOURCE_BUILDS_NIRI + anchor2)

    # ---- section-2 heading: OM ships the patched font --------------------
    sub("# 2. Nerd Font (JetBrainsMono) — official Fedora repos don't ship patched fonts",
        "# 2. Nerd Font (JetBrainsMono) — OpenMandriva ships the patched font\n"
        "#    (fonts-ttf-nerd-jetbrains-mono), so this section usually skips itself")

    # ---- niri config: dex spawn -> systemd xdg-autostart generator -------
    sub('spawn-sh-at-startup "command -v dex-autostart >/dev/null && dex-autostart -a -e niri"',
        DEX_REPLACEMENT_NIRI)

    # ---- screensaver / set-logo artwork: Fedora -> OpenMandriva ----------
    sub('FEDORA_SVG="/usr/share/fedora-logos/fedora_logo.svg"',
        'OPENMANDRIVA_SVG="/usr/share/icons/hicolor/scalable/apps/openmandriva.svg"\n'
        '[ -f "$OPENMANDRIVA_SVG" ] || OPENMANDRIVA_SVG="/usr/share/icons/openmandriva.svg"\n'
        '[ -f "$OPENMANDRIVA_SVG" ] || OPENMANDRIVA_SVG="/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg"',
        count=2)
    out = out.replace('[ -f "$FEDORA_SVG" ]', '[ -f "$OPENMANDRIVA_SVG" ]')
    out = out.replace('magick -background none "$FEDORA_SVG" -auto-orient',
                      'magick -background none "$OPENMANDRIVA_SVG" -auto-orient', 2)
    sub('  [ -s "$LOGO" ] || fastfetch --logo Fedora -s none > "$LOGO"',
        '  [ -s "$LOGO" ] || fastfetch --logo OpenMandriva -s none > "$LOGO"')
    sub('    command -v fastfetch >/dev/null 2>&1 && fastfetch --logo Fedora -s none >"$LOGO"',
        '    command -v fastfetch >/dev/null 2>&1 && fastfetch --logo OpenMandriva -s none >"$LOGO"')
    soft("# Fall back to the old typed-letter banner if ImageMagick or the Fedora",
         "# Fall back to the old typed-letter banner if ImageMagick or the distro")
    soft('  echo "  Fedora:        sudo dnf install ImageMagick" >&2',
         '  echo "  OpenMandriva:  sudo dnf install imagemagick" >&2')

    # ---- znver1 arch in the update-count regex ---------------------------
    sub(r"grep -cE '^\S+\.(x86_64|noarch|i686|aarch64|s390x|ppc64le)[[:space:]]'",
        r"grep -cE '^\S+\.(x86_64|noarch|i686|aarch64|znver1|s390x|ppc64le)[[:space:]]'",
        count=1)

    # ---- Strata runtime deps: OpenMandriva package names -----------------
    sub('''  sudo dnf install -y \\
    gtk4 gtksourceview5 poppler-glib bubblewrap gvfs \\
    gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugin-libav \\
    ffmpeg-free ffmpegthumbnailer LibRaw \\
    >/dev/null 2>&1 || warn "Strata runtime deps reported errors - continuing anyway."''',
        '''  sudo dnf install -y --setopt=strict=0 \\
    gtk4.0 gtksourceview5 lib64poppler-glib bubblewrap gvfs \\
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav \\
    ffmpeg ffmpegthumbs lib64raw \\
    >/dev/null 2>&1 || warn "Strata runtime deps reported errors - continuing anyway."''')

    # ---- remaining Fedora prose -> distro (soft; fine if absent) ---------
    soft("# Not packaged for Fedora", "# Not packaged for OpenMandriva")
    soft("no usable Fedora package or COPR exists", "no usable package exists on either distro")
    # generated niri config's own header line
    soft("// Niri rice config - Fedora. Written by fedora-niri-setup.sh.",
         "// Niri rice config - OpenMandriva. Written by openmandriva-niri-setup.sh.")
    # user-visible screensaver prompt + its surrounding helper-script comments
    soft("for the Fedora default: \" INPUT", "for the distro default: \" INPUT")
    soft("# half-block art (█▀▄) the Fedora logo uses in screensaver.sh. Matches",
         "# half-block art (█▀▄) the distro logo uses in screensaver.sh. Matches")
    soft("# screensaver.sh's own lazy Fedora-logo generation, which only writes if",
         "# screensaver.sh's own lazy distro-logo generation, which only writes if")
    soft("# conversion screensaver.sh runs on the Fedora logo SVG.",
         "# conversion screensaver.sh runs on the distro logo SVG.")
    soft("# Reset mode - regenerates the exact same Fedora block-art logo",
         "# Reset mode - regenerates the exact same distro block-art logo")
    soft("# pipeline against the real Fedora SVG, reusing this script's own",
         "# pipeline against the real distro SVG, reusing this script's own")
    soft("# Same fallback screensaver.sh itself uses if the Fedora SVG isn't",
         "# Same fallback screensaver.sh itself uses if the distro SVG isn't")
    soft("# installed (non-Fedora system) or the pipeline above produced nothing.",
         "# installed (non-standard install) or the pipeline above produced nothing.")
    soft("# correctly the same way the Fedora SVG is in screensaver.sh. Otherwise",
         "# correctly the same way the distro SVG is in screensaver.sh. Otherwise")
    soft("# visual scale as the block Fedora logo (which targets an 80-column",
         "# visual scale as the block distro logo (which targets an 80-column")
    soft("# \"Caffeine\" toggle - no packaged equivalent exists for Fedora (neither dnf",
         "# \"Caffeine\" toggle - no packaged equivalent exists for this distro (neither dnf")
    soft('"custom/gpu-usage",                     # gpu-usage-waybar not on Fedora',
         '"custom/gpu-usage",                     # gpu-usage-waybar not packaged')
    soft("this rice's Sway/Fedora setup.", "this rice's Sway setup.")
    soft("The real wttrbar (github.com/bjesus/wttrbar) is a Go binary not packaged for\nFedora. This implements the subset",
         "The real wttrbar (github.com/bjesus/wttrbar) is a Go binary not packaged for\nFedora or OpenMandriva. This implements the subset")

    if misses:
        print("WARN: %d stale anchors:" % len(misses))
        for m in misses:
            print("  -", m)
    DST.write_text(out, encoding="utf-8")
    print("wrote %s (%d lines)" % (DST, out.count("\n") + 1))
    return 1 if misses else 0


if __name__ == "__main__":
    sys.exit(main())
