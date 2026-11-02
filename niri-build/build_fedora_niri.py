#!/usr/bin/env python3
"""Refresh the embedded niri-build sources inside fedora-niri-setup.sh.

fedora-niri-setup.sh is the single, standalone installer artifact: every source
below is embedded into it as a heredoc, and this script re-syncs those embeds.
Edit a source, then re-run this.

Embeds refreshed (each anchored on its unique heredoc opener, never a line
number):
  niri-build/config/niri.kdl          -> the NIRI_KDL_EOF heredoc (niri config)
  niri-build/bin/*.sh                 -> cat > "$BIN/<name>" <<'RICE_EOF' blocks
  sway-build/hancore-theme-gen.py     -> the HANCOREGEN_EOF heredoc  (SHARED)
  sway-build/hancore-shims/*          -> the four HANCORESHIM_EOF heredocs (SHARED)

The HANCORE theme generator and its shims are shared verbatim with the Sway
rice (they are compositor-agnostic: they emit waybar/rofi/kitty/dunst/starship
plus a palette fragment). The niri installer rewrites the generated waybar
module names to niri's and converts the border fragment to a focus-ring KDL
fragment at install time - see section 6 of fedora-niri-setup.sh.

Everything else in fedora-niri-setup.sh (package list, the small app configs,
NiriMod install, prose) is edited directly in that file.

Usage: python3 -I build_fedora_niri.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
DST = ROOT / "fedora-niri-setup.sh"
SWAY = ROOT / "sway-build"

BIN_SCRIPTS = (
    # core
    "waybar-launch.sh", "swaybg-restore.sh", "wallpaper-picker.sh",
    "lock.sh", "screenshot.sh", "screenshot-tool.sh", "colorpicker.sh",
    "swayidle-launch.sh", "waybar-theme.sh", "niri-mod.sh",
    "osd-volume.sh", "osd-brightness.sh", "app-theme-sync.sh",
    # scratchpad + app toggles
    "niri-scratch.sh", "cliamp-toggle.sh", "cliamp-setup.sh",
    "ai-window-toggle.sh", "claude-desktop-toggle.sh", "mistral-vibe-toggle.sh",
    # toggles / widgets backends
    "caffeine-toggle.sh", "caffeine-state.sh", "dnd-toggle.sh", "dnd-indicator.sh",
    "wifi-toggle.sh", "wifi-menu.sh", "software-update.sh", "notification-center.sh",
    "blueman-applet-guard.sh", "fix-mx-scroll.sh", "battwatch.sh", "weather-float.sh",
    # screensaver / power / theme switchers / menus
    "screensaver.sh", "set-screensaver-text.sh", "set-ai-window-folder.sh",
    "icon-theme.sh", "cursor-theme.sh", "powermenu.sh", "app-menu.sh",
    "keybindings-help.sh", "arrange-displays.sh",
    # daemons
    "calendar-reminder-daemon-launch.sh",
)
SHIMS = ("wttrbar", "hancore-battery-status", "hancore-update-check",
         "vscode-theme-sync")


def readf(p):
    return p.read_text(encoding="utf-8").rstrip("\n")


def refresh_heredoc(lines, opener_prefix, body):
    """Replace the body of the heredoc opened by a line starting with
    `opener_prefix` with `body` lines. The heredoc marker is taken from the
    opener line itself."""
    hits = [i for i, ln in enumerate(lines) if ln.strip().startswith(opener_prefix)]
    if len(hits) != 1:
        sys.exit("anchor %r: %d hits" % (opener_prefix, len(hits)))
    start = hits[0]
    opener = lines[start]
    marker = opener.split("<<", 1)[1].strip().strip("'")
    end = start + 1
    while end < len(lines) and lines[end].rstrip() != marker:
        end += 1
    if end >= len(lines):
        sys.exit("unterminated heredoc at line %d" % (start + 1))
    return lines[:start + 1] + body + lines[end:]


def main():
    lines = readf(DST).split("\n")

    body = readf(HERE / "config" / "niri.kdl").split("\n")
    lines = refresh_heredoc(lines, 'cat > "$CONF/niri/config.kdl" <<', body)

    for name in BIN_SCRIPTS:
        body = readf(HERE / "bin" / name).split("\n")
        lines = refresh_heredoc(lines, 'cat > "$BIN/%s" <<' % name, body)

    body = readf(HERE / "bin" / "calendar-reminder-daemon.py").split("\n")
    lines = refresh_heredoc(
        lines, 'cat > "$BIN/calendar-reminder-daemon.py" <<', body)

    body = readf(SWAY / "hancore-theme-gen.py").split("\n")
    lines = refresh_heredoc(
        lines, 'cat > "$HANCORE_TMP/hancore-theme-gen.py" <<', body)

    for shim in SHIMS:
        body = readf(SWAY / "hancore-shims" / shim).split("\n")
        lines = refresh_heredoc(lines, 'cat > "$BIN/%s" <<' % shim, body)

    body = readf(SWAY / "rice-gen-driver.py").split("\n")
    lines = refresh_heredoc(
        lines, 'cat > "$RICEGEN_TMP/rice-gen-driver.py" <<', body)

    DST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("refreshed %s (%d lines)" % (DST, len(lines)))


if __name__ == "__main__":
    main()
