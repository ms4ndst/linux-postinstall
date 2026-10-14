#!/usr/bin/env python3
"""Transform fedroa-setup-i3-cattpuccin.sh -> sway-setup-cattpuccin.sh.

Strategy: a linear pass over the installer. Most heredocs (GTK/nvim/kitty/rofi/
dunst themes, screensaver, battwatch, calendar daemon, toggles, etc.) are reused
verbatim; the i3/polybar/X11 ones are replaced, ported, or dropped by their
target path. Non-heredoc regions (the dnf package block, the i3lock COPR block,
the snixembed source build, the flameshot X11 config) get targeted edits.

Usage: python3 -I build_sway_installer.py <i3-script> <scratchpad/sway> <out.sh>
"""
import re, sys, pathlib

i3_path = pathlib.Path(sys.argv[1])
sway_dir = pathlib.Path(sys.argv[2])
out_path = pathlib.Path(sys.argv[3])

text = i3_path.read_text(encoding="utf-8")
lines = text.splitlines()

def readf(rel):
    return (sway_dir / rel).read_text(encoding="utf-8").rstrip("\n")

sway_config   = readf("config/sway.config")
theme_writer  = readf("theme-writer.sh")
bin_scripts   = {p.stem: p.read_text(encoding="utf-8").rstrip("\n")
                 for p in (sway_dir / "bin").glob("*.sh")}

HEREDOC = re.compile(r'''^cat > "([^"]+)" <<'?([A-Za-z0-9_]+)'?\s*$''')

def heredoc_block(i):
    """If lines[i] opens a heredoc, return (path, marker, body_lines, j) where
    j is the index of the closing marker line. Else None."""
    m = HEREDOC.match(lines[i].strip())
    if not m:
        return None
    path, marker = m.group(1), m.group(2)
    body = []
    j = i + 1
    while j < len(lines) and lines[j].rstrip() != marker:
        body.append(lines[j]); j += 1
    return path, marker, body, j

# --- body porters ----------------------------------------------------------
def port_caffeine(body):
    out = []
    for ln in body:
        if ln.strip() == "xset s $IDLE_RESTORE":
            out.append("  # restart swayidle to restore idle lock/DPMS timers")
            out.append('  "$HOME/.local/bin/swayidle-launch.sh" >/dev/null 2>&1 &')
            out.append("  disown 2>/dev/null || true")
        elif ln.strip() == "xset s off -dpms":
            out.append("  # stop swayidle entirely so nothing blanks/locks while caffeinated")
            out.append("  pkill -x swayidle 2>/dev/null || true")
        else:
            out.append(ln)
    return out

def port_media(body):
    # strip inline %{A...:}...%{A} click zones -> icon only (clicks move to the
    # waybar module's on-click; the compiler injects them for the media module).
    out = []
    for ln in body:
        if ln.startswith("printf '%%{A1:playerctl"):
            out.append("printf ' %s ' \"$icon\"")
        else:
            out.append(ln)
    return out

def port_fspan(body):
    # %{F#hex}X%{F-}  ->  <span color="#hex">X</span>  (waybar pango markup);
    # %{F${VAR}}X%{F-} -> <span color="${VAR}">X</span>
    out = []
    for ln in body:
        ln = re.sub(r"%\{F(#[0-9A-Fa-f]{6})\}", r'<span color="\1">', ln)
        ln = re.sub(r"%\{F\$\{([^}]+)\}\}", r'<span color="${\1}">', ln)
        ln = re.sub(r"%\{F\$([A-Za-z_][A-Za-z0-9_]*)\}", r'<span color="$\1">', ln)
        ln = ln.replace("%{F-}", "</span>")
        out.append(ln)
    return out

def port_layout(body):
    return [ln.replace("i3-msg -t get_tree", "swaymsg -t get_tree") for ln in body]

# target path -> (action, payload). action: drop | replace_sway_config |
# replace_script(name) | port(fn) | rename_only(newpath)
def classify(path):
    # polybar theme wrappers + the main config.ini are replaced by the compiled
    # waybar themes. The gh0stzk/ rice includes are KEPT: the compiled gh0stzk
    # waybar themes reference the $GZ_BIN backend scripts that section sets up,
    # and its polybar config files are then just unused (harmless) - far safer
    # than half-dropping an intertwined subsystem we can't live-test here.
    if re.search(r"/polybar/themes/", path):
        return ("drop_theme", None)
    if path.endswith("/polybar/config.ini"):
        return ("drop_theme", None)
    if path == "$CONF/i3/config":
        return ("sway_config", None)
    if path == "$CONF/picom/picom.conf":
        return ("drop", None)
    if path == "$CONF/autorandr/postswitch":
        return ("drop", None)
    base = path.rsplit("/", 1)[-1]
    repl = {
        "polybar-launch.sh": "waybar-launch",
        "polybar-theme.sh": "waybar-theme",
        "lock.sh": "lock",
        "colorpicker.sh": "colorpicker",
    }
    if base in repl:
        return ("replace_script", repl[base])
    if base == "caffeine-toggle.sh":
        return ("port", port_caffeine)
    if base in ("polybar-media.sh", "polybar-media-boxed.sh"):
        return ("port", port_media)
    if base in ("polybar-wifi.sh", "polybar-backlight.sh"):
        return ("port", port_fspan)
    if base == "polybar-layout.sh":
        return ("port", port_layout)
    return ("keep", None)

# The replacement scripts keep the SAME bin path the config references, except
# polybar-launch/polybar-theme which become waybar-launch/waybar-theme.
SCRIPT_TARGET = {
    "waybar-launch": "$BIN/waybar-launch.sh",
    "waybar-theme": "$BIN/waybar-theme.sh",
    "lock": "$BIN/lock.sh",
    "colorpicker": "$BIN/colorpicker.sh",
}

out = []
i = 0
theme_writer_inserted = False
# track consuming trailing `chmod`/`sed -i` lines tied to a dropped heredoc
def consume_trailers(j):
    """Return index past any chmod/sed-i lines that operate on the just-handled
    file (they immediately follow the closing marker)."""
    k = j + 1
    while k < len(lines) and re.match(r'^\s*(chmod \+x|sed -i)\b', lines[k]):
        k += 1
    return k

while i < len(lines):
    blk = heredoc_block(i)
    if blk is None:
        out.append(lines[i]); i += 1
        continue
    path, marker, body, j = blk
    action, payload = classify(path)

    if action == "drop_theme":
        if not theme_writer_inserted:
            out.append("# " + "-" * 76)
            out.append("# Waybar themes (compiled 1:1 from the i3 rice's polybar themes)")
            out.append("# " + "-" * 76)
            out.append(theme_writer)
            theme_writer_inserted = True
        i = consume_trailers(j)
        continue
    if action == "drop":
        i = consume_trailers(j)
        continue
    if action == "sway_config":
        # Fill the cursor placeholders with a safe, always-present default
        # (the user can edit the one `seat ... xcursor_theme` line afterward).
        cfg = (sway_config.replace("@@CURSOR_THEME@@", "Adwaita")
                          .replace("@@CURSOR_SIZE@@", "24"))
        out.append('mkdir -p "$CONF/sway"')
        out.append('cat > "$CONF/sway/config" <<\'SWAY_EOF\'')
        out.append(cfg)
        out.append("SWAY_EOF")
        i = consume_trailers(j)
        continue
    if action == "replace_script":
        def emit_script(name, tgt):
            out.append(f'cat > "{tgt}" <<\'RICE_EOF\'')
            out.append(bin_scripts[name])
            out.append("RICE_EOF")
            out.append(f'chmod +x "{tgt}"')
        emit_script(payload, SCRIPT_TARGET[payload])
        # The Sway rice adds runtime scripts the i3 installer never had; write
        # them alongside the first replaced script (waybar-launch) so every
        # path the sway config references actually exists.
        if payload == "waybar-launch":
            for extra in ("swaybg-restore", "swayidle-launch", "screenshot",
                          "wallpaper-picker"):
                emit_script(extra, f"$BIN/{extra}.sh")
        i = consume_trailers(j)
        continue
    if action == "port":
        out.append(lines[i])
        out.extend(payload(body))
        out.append(marker)
        i = j + 1
        continue
    # keep verbatim
    out.extend(lines[i:j + 1])
    i = j + 1

result = "\n".join(out) + "\n"

# --- post-pass: remove orphaned non-heredoc polybar glue ------------------
def post_clean(s):
    removed = []
    # A. the `sed -i -e ... "$CONF/polybar/config.ini"` templating block
    #    (multi-line, backslash-continued). The ICO_*/BATTERY_NAME var defs
    #    above it are kept - the widget scripts still substitute them.
    patA = re.compile(r'^sed -i \\\n(?:[ \t]*-e .*\\\n)+[ \t]*"\$CONF/polybar/config\.ini"\n',
                      re.M)
    s, n = patA.subn('# (polybar config.ini templating removed - waybar themes are precompiled)\n', s)
    removed.append(("config.ini sed-templating", n))
    # B. seeding the default polybar theme from config.ini
    patB = re.compile(r'^mkdir -p "\$CONF/polybar/themes"\n'
                      r'cp "\$CONF/polybar/config\.ini" "\$CONF/polybar/themes/catppuccin-mocha\.ini"\n',
                      re.M)
    s, n = patB.subn('', s)
    removed.append(("config.ini->themes cp", n))
    # C. forest-numbered generation: the original sed-derives forest-numbered*
    #    from forest*.ini (now absent -> would abort under set -e). Replace it
    #    with a copy of the compiled waybar forest theme so forest-numbered
    #    still exists (visually = forest; the %index%-vs-dot workspace label
    #    distinction is the one thing not carried here). Line-anchored (no
    #    DOTALL) so it matches linearly on the 1.4MB file.
    patC = re.compile(r'^[ \t]*sed -e [^\n]*\n(?:[ \t]+-e [^\n]*\n)*'
                      r'[ \t]+"\$CONF/polybar/themes/forest\$v\.ini" > '
                      r'"\$CONF/polybar/themes/forest-numbered\$v\.ini"\n', re.M)
    replC = ('  mkdir -p "$CONF/waybar/themes/forest-numbered$v"\n'
             '  cp "$CONF/waybar/themes/forest$v/config.jsonc" "$CONF/waybar/themes/forest-numbered$v/config.jsonc"\n'
             '  cp "$CONF/waybar/themes/forest$v/style.css" "$CONF/waybar/themes/forest-numbered$v/style.css"\n')
    s, n = patC.subn(replC, s)
    removed.append(("forest-numbered gen->waybar copy", n))
    # D. the leftover `polybar -c ... config.ini` fallback launch (polybar is no
    #    longer installed) - neutralise so it can't error if ever reached.
    s = s.replace('polybar -c ~/.config/polybar/config.ini top-primary',
                  ':  # (polybar removed; waybar is launched via waybar-launch.sh)')

    # E. PACKAGE LIST: swap the X11/i3 stack for the Wayland/Sway stack.
    new_pkgs = (
        'log "Installing Wayland stack + Sway + rice toolkit via dnf..."\n'
        'sudo dnf install -y \\\n'
        '  sway swaybg swayidle swaylock waybar kanshi \\\n'
        '  grim slurp wl-clipboard \\\n'
        '  rofi-wayland dunst kitty \\\n'
        '  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \\\n'
        '  network-manager-applet pasystray blueman lxqt-policykit pipewire-pulseaudio \\\n'
        '  copyq udiskie pcmanfm gammastep libnotify gnome-calendar \\\n'
        '  system-config-printer hplip \\\n'
        '  lxappearance papirus-icon-theme \\\n'
        '  fastfetch git curl unzip jq ImageMagick \\\n'
        '  brightnessctl playerctl dex-autostart \\\n'
        '  dnf-utils \\\n'
        '  solaar solaar-udev \\\n'
        '  pipx \\\n'
        '  jetbrains-mono-fonts \\\n'
        '  plymouth-plugin-script\n'
    )
    patE = re.compile(r'^log "Installing base X11 stack \+ i3 \+ rice toolkit via dnf\.\.\."\n'
                      r'sudo dnf install -y \\\n(?:[^\n]*\\\n)*[^\n]*plymouth-plugin-script\n',
                      re.M)
    s, n = patE.subn(new_pkgs, s)
    removed.append(("package list X11->Wayland", n))

    # F. i3lock-color COPR block -> swaylock note (swaylock is in the dnf list;
    #    swaylock-effects is optional and lock.sh falls back automatically).
    note = ('# Lock screen: swaylock is installed above. swaylock-effects (blur/\n'
            '# vignette, used by lock.sh when present) is not in Fedora\'s repos -\n'
            '# install it from a COPR or source for the blurred lock; lock.sh falls\n'
            '# back to plain swaylock automatically otherwise.\n')
    patF = re.compile(r'^log "Enabling COPR for i3lock-color[^\n]*\n(?:[^\n]*\n)*?^fi\n', re.M)
    s, n = patF.subn(note, s)
    removed.append(("i3lock COPR block", n))

    # G. polybar-launch.sh / polybar-theme.sh were renamed to waybar-*; update
    #    every remaining reference (app-menu.sh, gh0stzk RiceSelector, comments).
    #    The widget scripts keep their polybar-* names (referenced consistently
    #    by the compiled waybar module exec paths), so only these two rename.
    before = s
    s = s.replace("polybar-launch.sh", "waybar-launch.sh")
    s = s.replace("polybar-theme.sh", "waybar-theme.sh")
    removed.append(("ref rename polybar-launch/theme->waybar", 1 if s != before else 0))

    # H. cosmetic: make the script read as a first-class Sway installer at the
    #    top. Deliberately surgical - functional `i3` references (the
    #    ~/.config/i3/wallpaper.png fallback path, i3lock comments) are left
    #    alone; only the title, compositor note, log prefix, and self-name change.
    s = s.replace('# i3 "hackerbox" post-install script',
                  '# Sway "hackerbox" post-install script')
    s = s.replace('# Theme: Catppuccin Mocha | Layout: gapped + picom blur/shadows',
                  '# Theme: Catppuccin Mocha | Layout: gapped (Sway native compositing)')
    s = s.replace('[i3-setup]', '[sway-setup]')
    s = s.replace('before fedroa-setup-i3-cattpuccin.sh', 'before sway-setup-cattpuccin.sh')
    return s, removed

result, removed = post_clean(result)
out_path.write_text(result, encoding="utf-8")
for name, n in removed:
    print(f"  post-clean: {name} x{n}")
print(f"wrote {out_path} ({result.count(chr(10))} lines); theme_writer_inserted={theme_writer_inserted}")
