#!/usr/bin/env python3
"""Extract every polybar theme config.ini from the i3 setup script into clean,
SELF-CONTAINED .ini files (resolving polybar `include-file` at extract time, so
gh0stzk two-file themes become single files the waybar compiler can read).

Usage: python3 -I extract_themes.py <setup-script.sh> <outdir>
"""
import re, sys, pathlib, posixpath

src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
lines = src.splitlines()

# Pass 1: collect EVERY `cat > "<path>" <<'MARKER' ... MARKER` heredoc body,
# keyed by its target path with $CONF and $HOME normalised to ~/.config.
heredoc = re.compile(r'''^cat > "([^"]+\.ini)" <<'?([A-Za-z0-9_]+)'?\s*$''')
blocks = {}   # normalised path -> body text
def norm(p):
    p = p.replace("$CONF", "~/.config").replace("${CONF}", "~/.config")
    p = p.replace("$HOME/.config", "~/.config").replace("${HOME}/.config", "~/.config")
    return p
i = 0
while i < len(lines):
    m = heredoc.match(lines[i].strip())
    if m:
        path, marker = norm(m.group(1)), m.group(2)
        body = []; i += 1
        while i < len(lines) and lines[i].rstrip() != marker:
            body.append(lines[i]); i += 1
        blocks[path] = "\n".join(body)
    i += 1

def resolve_rel(inc, base_dir):
    """Resolve an include path (absolute ~/... or relative to base_dir)."""
    inc = inc.strip()
    if inc.startswith("~") or inc.startswith("$") or inc.startswith("/"):
        return norm(inc)
    # relative to the including file's directory, collapsing ../
    joined = posixpath.normpath(posixpath.join(base_dir, inc))
    return joined

def resolve_includes(text, base_dir="~/.config/polybar", depth=0):
    if depth > 8:
        return text
    outl = []
    for line in text.splitlines():
        m = re.match(r'^\s*include-file\s*=\s*(\S+)', line)
        if m:
            inc = resolve_rel(m.group(1), base_dir)
            if inc in blocks:
                outl.append(f"; <<< inlined include: {inc}")
                outl.append(resolve_includes(blocks[inc], posixpath.dirname(inc), depth + 1))
                outl.append(f"; >>> end include: {inc}")
                continue
            outl.append(f"; (unresolved include: {inc})")
            continue
        outl.append(line)
    return "\n".join(outl)

# Pass 2: write out the theme files (themes/<name>.ini + the main config.ini as
# catppuccin-mocha), with includes resolved. Skip the gh0stzk rice includes
# themselves (they are not standalone themes; they get inlined above).
names = []
for path, body in blocks.items():
    m = re.search(r'/polybar/(?:themes/)?([A-Za-z0-9._-]+)\.ini$', path)
    if not m:
        continue
    if "/gh0stzk/rices/" in path:
        continue                      # included module defs, not a theme
    name = m.group(1)
    if name == "config":              # the master bar = catppuccin-mocha
        name = "catppuccin-mocha"
    (out / f"{name}.ini").write_text(resolve_includes(body) + "\n", encoding="utf-8")
    names.append(name)

names.sort()
print(f"extracted {len(names)} self-contained theme INIs "
      f"({sum('/gh0stzk/rices/' in p for p in blocks)} gh0stzk includes inlined)")
