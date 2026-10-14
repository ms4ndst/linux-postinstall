#!/usr/bin/env python3
"""Emit a shell block that writes all compiled waybar theme dirs
(~/.config/waybar/themes/<name>/{config.jsonc,style.css}) as heredocs, plus
seeds the default (catppuccin-mocha) as the live config. Embedded into the
sway installer. Reads the compiled out/ dir produced by polybar2waybar.py.

Usage: python3 -I gen_theme_writer.py <compiled-out-dir> <output.sh>
"""
import sys, pathlib

out_dir = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
themes = sorted(p.name for p in out_dir.iterdir() if p.is_dir())

# Pick a heredoc marker guaranteed not to collide with JSONC/CSS content.
MARK = "WB_EOF"

def emit_file(buf, path, content):
    # content must not contain a line equal to MARK; verify.
    for ln in content.splitlines():
        if ln.strip() == MARK:
            raise SystemExit(f"marker collision in {path}")
    buf.append(f'cat > "{path}" <<\'{MARK}\'')
    buf.append(content.rstrip("\n"))
    buf.append(MARK)

buf = []
buf.append('# --- waybar themes (compiled 1:1 from the i3 rice\'s polybar themes) ---')
buf.append('log "Writing waybar themes..."')
buf.append('mkdir -p "$CONF/waybar/themes"')
for t in themes:
    cfg = (out_dir / t / "config.jsonc").read_text(encoding="utf-8")
    css = (out_dir / t / "style.css").read_text(encoding="utf-8")
    buf.append(f'mkdir -p "$CONF/waybar/themes/{t}"')
    emit_file(buf, f'$CONF/waybar/themes/{t}/config.jsonc', cfg)
    emit_file(buf, f'$CONF/waybar/themes/{t}/style.css', css)
buf.append('')
buf.append('# Seed the live config with the default theme (catppuccin-mocha).')
buf.append('cp "$CONF/waybar/themes/catppuccin-mocha/config.jsonc" "$CONF/waybar/config.jsonc"')
buf.append('cp "$CONF/waybar/themes/catppuccin-mocha/style.css" "$CONF/waybar/style.css"')
buf.append('echo "catppuccin-mocha" > "$CONF/waybar/current-theme-name"')

dest.write_text("\n".join(buf) + "\n", encoding="utf-8")
print(f"wrote theme-writer for {len(themes)} themes -> {dest} ({dest.stat().st_size} bytes)")
