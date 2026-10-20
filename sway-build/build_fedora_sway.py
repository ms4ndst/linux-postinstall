#!/usr/bin/env python3
"""Refresh the embedded sway-build sources inside fedora-sway-setup.sh.

fedora-sway-setup.sh is the single, standalone installer artifact: every
sway-build source below is embedded into it as a heredoc, and this script
re-syncs those embeds. Edit a source in sway-build/, then re-run this.

Embeds refreshed (each anchored on its unique heredoc opener, never a line
number):
  sway-build/bin/*.sh              -> cat > "$BIN/<name>" <<'EOF' blocks
  sway-build/hancore-theme-gen.py  -> the HANCOREGEN_EOF heredoc
  sway-build/hancore-shims/*       -> the four HANCORESHIM_EOF heredocs
  sway-build/rice-gen-driver.py    -> the RICEGENEOF heredoc

Everything else in fedora-sway-setup.sh (sway config, helper scripts,
prose) is edited directly in that file - there is no intermediate
installer to transform anymore.

Usage: python3 -I build_fedora_sway.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
DST = HERE.parent / "fedora-sway-setup.sh"

BIN_SCRIPTS = (
    "caffeine-state.sh",
    "colorpicker.sh",
    "cursor-theme.sh",
    "icon-theme.sh",
    "lock.sh",
    "screenshot.sh",
    "swaybg-restore.sh",
    "swayidle-launch.sh",
    "wallpaper-picker.sh",
    "waybar-launch.sh",
    "waybar-theme.sh",
    "weather-float.sh",
)
SHIMS = ("wttrbar", "hancore-battery-status", "hancore-update-check",
         "vscode-theme-sync")


def readf(p):
    return p.read_text(encoding="utf-8").rstrip("\n")


def refresh_heredoc(lines, opener_prefix, body):
    """Replace the body of the heredoc opened by a line starting with
    `opener_prefix` with `body` lines. The heredoc marker (EOF, RICE_EOF,
    ...) is taken from the opener line itself."""
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

    for name in BIN_SCRIPTS:
        body = readf(HERE / "bin" / name).split("\n")
        lines = refresh_heredoc(lines, 'cat > "$BIN/%s" <<' % name, body)

    body = readf(HERE / "hancore-theme-gen.py").split("\n")
    lines = refresh_heredoc(
        lines, 'cat > "$HANCORE_TMP/hancore-theme-gen.py" <<', body)

    for shim in SHIMS:
        body = readf(HERE / "hancore-shims" / shim).split("\n")
        lines = refresh_heredoc(lines, 'cat > "$BIN/%s" <<' % shim, body)

    body = readf(HERE / "rice-gen-driver.py").split("\n")
    lines = refresh_heredoc(
        lines, 'cat > "$RICEGEN_TMP/rice-gen-driver.py" <<', body)

    DST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("refreshed %s (%d lines)" % (DST, len(lines)))


if __name__ == "__main__":
    main()
