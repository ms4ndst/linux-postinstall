#!/usr/bin/env python3
"""Transform sway-setup-cattpuccin.sh -> fedora-sway-setup.sh.

Replaces the embedded Catppuccin/polybar-port theme collection with
HANCORE-linux/waybar-themes installed at run time:

  - cuts the old per-theme heredocs (waybar/rofi/kitty/dunst/starship/
    sway-border), the polybar/gh0stzk/sedo/murz-hidrot theme machinery,
    the Catppuccin Plymouth theme and the Catppuccin GTK download
  - inserts an up-front question (wipe existing themes first?) and a new
    section 6 that clones the HANCORE repo, adapts it (Sway modules,
    rice command rewrites), generates all the matching per-app themes,
    and seeds the first theme
  - installs the wttrbar/battery/update helper shims the adapted themes exec
  - re-points section 15 at sway-build/rice-gen-driver.py so the repo's
    GTK/Neovim/VS Code generators cover the new themes
  - refreshes waybar-theme.sh/waybar-launch.sh from sway-build/bin/ (the
    palette import copy + PATH export the new themes need)

Anchored entirely on unique section-header strings - never line numbers.

Usage: python3 -I build_fedora_sway.py
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "sway-setup-cattpuccin.sh"
DST = HERE.parent / "fedora-sway-setup.sh"

HEREDOC_RE = re.compile(r'''^cat > "([^"]+)" <<'?([A-Za-z0-9_]+)'?\s*$''')

# heredoc target paths that belong to the old theme collection
SWEEP_PATHS = [
    re.compile(r"^\$CONF/waybar/themes/"),
    re.compile(r"^\$CONF/rofi/themes/"),
    re.compile(r"^\$CONF/rofi/catppuccin-mocha\.rasi$"),
    re.compile(r"^\$CONF/kitty/themes/"),
    re.compile(r"^\$CONF/dunst/themes/"),
    re.compile(r"^\$CONF/starship/themes/"),
    re.compile(r"^\$CONF/i3/themes/"),
    re.compile(r"^\$CONF/polybar/"),
    re.compile(r"^\$GZ_BIN/"),
]
MKDIR_SWEEP = re.compile(
    r'^mkdir -p "\$CONF/(waybar|rofi|kitty|dunst|starship|polybar)/themes(/[^"]*)?"\s*$')
SEED_SWEEP = re.compile(
    r'^cp "\$CONF/(rofi|kitty)/themes/catppuccin-mocha[^"]*" "\$CONF/[^"]*"\s*$')


def readf(p):
    return p.read_text(encoding="utf-8").rstrip("\n")


def find_idx(lines, anchor, what):
    hits = [i for i, ln in enumerate(lines) if ln.startswith(anchor)]
    if len(hits) != 1:
        sys.exit("anchor %r (%s): %d hits" % (anchor, what, len(hits)))
    return hits[0]


def heredoc_end(lines, start):
    marker = HEREDOC_RE.match(lines[start].strip()).group(2)
    j = start + 1
    while j < len(lines) and lines[j].rstrip() != marker:
        j += 1
    if j >= len(lines):
        sys.exit("unterminated heredoc at line %d" % (start + 1))
    return j


def sweep_heredocs(lines):
    """Drop heredoc blocks whose target path belongs to the old themes."""
    out, i = [], 0
    while i < len(lines):
        m = HEREDOC_RE.match(lines[i].strip())
        if m and any(p.match(m.group(1)) for p in SWEEP_PATHS):
            i = heredoc_end(lines, i) + 1
            continue
        out.append(lines[i])
        i += 1
    return out


def main():
    lines = SRC.read_text(encoding="utf-8").split("\n")

    # ---- header comment block -------------------------------------------
    # (first hit: the main script's - the heredoc scripts below embed their own)
    set_euo = next(i for i, ln in enumerate(lines)
                   if ln.startswith("set -euo pipefail"))
    header = """# ============================================================================
# Sway "hackerbox" post-install script - Fedora 44 (HANCORE waybar themes)
# Theme collection: HANCORE-linux/waybar-themes (github.com/HANCORE-linux/
#           waybar-themes, MIT), fetched at install time, adapted from
#           their Omarchy/Hyprland home to plain Sway on Fedora, and wired
#           into this rice's theme switcher so one pick retints waybar,
#           rofi, kitty, dunst, starship, sway borders, GTK, Neovim and
#           VS Code together - the same mechanism the old embedded
#           Catppuccin collection used.
# Installs: sway, swaybg, swayidle, swaylock, waybar, kanshi, rofi, dunst,
#           kitty, flameshot, ImageMagick, brightnessctl, playerctl,
#           fastfetch, Nerd Font, tray helpers, GTK/icon/cursor themes,
#           rofi power menu, copyq clipboard history, udiskie USB
#           automount, pcmanfm file manager, gammastep night light,
#           volume/brightness OSD popups, cava + btop for the HANCORE
#           themes' audio/system widgets, CLIamp terminal music player
#           (Mod+m), an Omarchy-style app menu (Mod+alt+space) for this
#           rice's own utility scripts (including a floating on-screen
#           keybinding cheat sheet), + always-visible window borders and
#           tightened gaps.
# Idempotent-ish: safe to re-run, but back up existing configs first if you
# have your own dotfiles - this OVERWRITES the files listed below.
# ===============================================================================""".split("\n")
    # fix the last ruler length to match the file's own style
    header[-1] = header[-1].replace("=" * 80, "=" * 76)
    lines = lines[:1] + header + lines[set_euo:]

    # ---- the theme-wipe question -----------------------------------------
    mkdir_conf = find_idx(lines, 'mkdir -p "$CONF" "$BIN" "$FONTS"', "conf mkdir")
    question = '''
# Theme replacement: this script installs the HANCORE-linux/waybar-themes
# collection in place of this rice's old embedded theme collection. Answer
# y here to wipe every existing desktop theme first (waybar/rofi/kitty/
# dunst/starship/sway-border themes, rice-* Neovim colors, Rice-* GTK
# themes); answer n to keep them and just add the new ones alongside.
CLEAN_THEMES=0
printf '\\nThis script will install the HANCORE waybar theme collection.\\n'
read -r -p 'Clean out ALL existing desktop themes first, then install the new ones? [y/N] ' reply || true
case "$reply" in
  [yY]|[yY][eE][sS]) CLEAN_THEMES=1 ;;
esac
unset reply
'''.rstrip("\n").split("\n")
    lines = lines[:mkdir_conf + 1] + question + lines[mkdir_conf + 1:]

    # ---- extra packages for the HANCORE themes' widgets ------------------
    pkg = find_idx(lines, "  sway swaybg swayidle swaylock waybar kanshi \\".rstrip(), "dnf list")
    lines.insert(pkg + 1, "  cava btop \\")

    # ---- section cuts (bottom-up so indices stay valid) -------------------
    flameshot = find_idx(lines, "# Flameshot >=14 defaults", "flameshot hdr")
    cut_6f_end = flameshot - 1          # the '# ---' line above the header
    six_f = find_idx(lines, "# 6f. i3 border-color theming", "6f")
    cut_6f_start = six_f - 1            # the '# ---' line above 6f
    lines = lines[:cut_6f_start] + lines[cut_6f_end:]

    kitty_sec = find_idx(lines, "# 9. kitty", "9 kitty")
    cut_dunst_end = kitty_sec - 1
    dunst_sec = find_idx(lines, "# 8. dunst", "8 dunst")
    cut_dunst_start = dunst_sec - 1
    lines = lines[:cut_dunst_start] + lines[cut_dunst_end:]

    # old section 6 (polybar config + waybar themes + 6a2 polybar themes)
    # -> the new HANCORE section
    six_b = find_idx(lines, "# 6b. Multi-monitor helper", "6b")
    cut_6_end = six_b - 1
    six = find_idx(lines, "# 6. polybar", "6 polybar")
    cut_6_start = six - 1
    new_section = new_hancore_section()
    lines = lines[:cut_6_start] + new_section + lines[cut_6_end:]

    # Plymouth Catppuccin theme + the Mocha palette comment block
    sec4 = find_idx(lines, "# 4. i3 config", "4 i3")
    cut_plym_end = sec4 - 1
    plym = find_idx(lines, "# 2b. Plymouth boot theme", "2b plymouth")
    cut_plym_start = plym - 1
    lines = lines[:cut_plym_start] + lines[cut_plym_end:]

    # ---- heredoc / mkdir / seed sweeps ------------------------------------
    lines = sweep_heredocs(lines)
    lines = [ln for ln in lines if not MKDIR_SWEEP.match(ln) and not SEED_SWEEP.match(ln)]
    # collapse the blank runs the sweeps leave behind
    collapsed = []
    for ln in lines:
        if ln == "" and collapsed[-2:] == ["", ""]:
            continue
        collapsed.append(ln)
    lines = collapsed

    # ---- section 13: base GTK theme = the seeded Rice-* theme -------------
    gtk_name = find_idx(lines, 'GTK_THEME_NAME="catppuccin-mocha-mauve-standard+default"', "gtk name")
    c = find_idx(lines, "# Not packaged for Fedora. The official catppuccin/gtk", "gtk comment") - 1  # the '# ---' above
    gtk_end = find_idx(lines, '  log "Catppuccin GTK theme already present, skipping download."', "gtk else") + 1
    assert lines[gtk_end].strip() == "fi", lines[gtk_end]
    gtk_block = '''# The active desktop theme's own GTK theme (Rice-<name>, generated by the
# repo's generate-gtk-themes.py in section 15 from the [colors] block
# hancore-theme-gen.py wrote for it) - waybar-theme.sh switches it on every
# theme pick, same as the old collection. The current theme name file is
# seeded by section 6; fall back to the first HANCORE theme if it's missing.
GTK_THEME_NAME="Rice-$(cat "$HOME/.config/waybar/current-theme-name" 2>/dev/null || echo v1)"'''.split("\n")
    lines = lines[:c + 1] + gtk_block + lines[gtk_end + 1:]

    # ---- section 15: repo generators via the driver -----------------------
    sec15 = find_idx(lines, "# 15. GTK / Neovim / VS Code themes matching every polybar theme", "15")
    repo_dir = find_idx(lines, 'REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"', "REPO_DIR")
    cut15_start = sec15 - 1
    # the `done` of the generator for-loop
    done_idx = None
    for j in range(repo_dir, repo_dir + 40):
        if lines[j].strip() == "done":
            done_idx = j
            break
    if done_idx is None:
        sys.exit("section 15 for-loop end not found")
    driver_src = readf(HERE / "rice-gen-driver.py")
    sec15_text = '''# ----------------------------------------------------------------------------
# 15. GTK / Neovim / VS Code themes matching every installed bar theme
# ----------------------------------------------------------------------------
# The HANCORE themes (and any of the old collection the user kept) are
# fed to the repo's own generate-gtk/nvim/vscode-themes.py as [colors]
# blocks in ~/.config/polybar/themes/<name>.ini - the same input format
# the old rice's own themes used - via rice-gen-driver.py, which patches
# the generators' hardcoded THEMES list to every installed theme before
# running them. Best-effort, like the old section: a missing repo dir
# only warns.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RICEGEN_TMP="$(mktemp -d)"
cat > "$RICEGEN_TMP/rice-gen-driver.py" <<'RICEGENEOF'
''' + driver_src + '''
RICEGENEOF
if python3 -I "$RICEGEN_TMP/rice-gen-driver.py" "$REPO_DIR" >/dev/null; then
  log "Matching GTK (Rice-*), Neovim (rice-*) and VS Code themes generated."
else
  warn "GTK/Neovim/VS Code theme generation failed (repo dir: $REPO_DIR) - run it by hand: python3 sway-build/rice-gen-driver.py \\"$REPO_DIR\\""
fi
rm -rf "$RICEGEN_TMP"'''
    sec15_block = sec15_text.split("\n")
    lines = lines[:cut15_start] + sec15_block + lines[done_idx + 1:]

    # ---- refresh the sway-build/bin/ scripts embedded in the output ----
    # (these were authored as sway-build sources for sway-setup-cattpuccin.sh;
    #  re-embed the current file contents so edits there propagate here too)
    for name, path in (("waybar-launch.sh", "waybar-launch"),
                       ("waybar-theme.sh", "waybar-theme"),
                       ("lock.sh", "lock"),
                       ("swayidle-launch.sh", "swayidle-launch"),
                       ("swaybg-restore.sh", "swaybg-restore"),
                       ("screenshot.sh", "screenshot"),
                       ("wallpaper-picker.sh", "wallpaper-picker"),
                       ("colorpicker.sh", "colorpicker")):
        hstart = find_idx(lines, 'cat > "$BIN/%s" <<' % name, name)
        hend = heredoc_end(lines, hstart)
        body = readf(HERE / "bin" / name).split("\n")
        lines = lines[:hstart + 1] + body + lines[hend:]

    # ---- final summary block touch-ups ------------------------------------
    summary_fixes = [
        ('    password field and select "i3" (it\'s a plain Xorg session —',
         '    password field and select "Sway" (a native Wayland session —'),
        (' 3. First login will look mostly bare until picom/polybar spawn\n'
         '    (a couple seconds). If polybar doesn\'t appear, run:\n'
         '        :  # (polybar removed; waybar is launched via waybar-launch.sh)\n'
         '    from a kitty terminal (Mod+Return) to see errors directly.',
         ' 3. First login will look mostly bare until waybar spawns (a couple\n'
         '    seconds). If it doesn\'t appear, run\n'
         '        ~/.local/bin/waybar-launch.sh\n'
         '    from a kitty terminal (Mod+Return) to see errors directly.'),
        ('    hotplug from then on, and its postswitch hook re-launches polybar\n'
         '    (one bar per output, tray/battery/bluetooth only on whichever is\n'
         '    primary) and re-restores the wallpaper. By default i3 leaves\n'
         '    workspaces wherever they were first created, which feels like a\n'
         '    separate desktop per monitor - edit the `workspace <n> output <name>`\n'
         '    block near the top of the "workspaces" section in ~/.config/i3/config\n'
         '    (commented out) to pin workspace ranges to specific outputs instead.',
         '    hotplug from then on, and its postswitch hook re-launches waybar\n'
         '    and re-restores the wallpaper. By default sway leaves\n'
         '    workspaces wherever they were first created, which feels like a\n'
         '    separate desktop per monitor - edit the `workspace <n> output <name>`\n'
         '    block near the top of the "workspaces" section in ~/.config/sway/config\n'
         '    (commented out) to pin workspace ranges to specific outputs instead.'),
        ('    password field and select "Sway" (a native Wayland session —\n'
         '    installing the i3 package registers it automatically).',
         '    password field and select "Sway" (a native Wayland session —\n'
         '    the sway package registers it automatically).'),
        ('   Mod+shift+r       restart i3',
         '   Mod+shift+r       restart Sway'),
        ('   Mod+shift+e       exit i3 (with confirm)',
         '   Mod+shift+e       exit Sway (with confirm)'),
        ('   Mod+shift+w       wallpaper picker (nitrogen)',
         '   Mod+shift+w       wallpaper picker (azote)'),
        (' 8. GTK apps are themed Catppuccin Mocha (GTK2, GTK3, and GTK4 settings\n'
         '    are all written directly); re-run `lxappearance` yourself any time to\n'
         '    change the theme/icons/font/cursor interactively instead.',
         ' 8. Desktop theming comes from the HANCORE waybar collection - pick a\n'
         '    theme with the app menu (Mod+alt+space -> Desktop Theme) or\n'
         '    `waybar-theme.sh <name>`; one pick retints waybar, rofi, kitty,\n'
         '    dunst, starship, sway borders, GTK, Neovim and VS Code together.'),
    ]
    text = "\n".join(lines)
    for old, new in (
        ('fi\n# Keep sudo warm for the whole run',
         """fi
# Run as your own user, never under sudo/root: the script calls sudo where
# needed and installs into $HOME - under sudo, $HOME is root's and every
# config would land in the wrong place.
if [ "$(id -u)" = "0" ]; then
  echo 'Do not run this with sudo - run it as your own user; it calls sudo itself and installs into $HOME.' >&2
  exit 1
fi
# Keep sudo warm for the whole run"""),
        ('  plymouth-plugin-script\n\n# network-manager-applet',
         """  plymouth-plugin-script

# power-profiles-daemon backs the waybar power-profiles-daemon module in
# the HANCORE themes - but tuned-ppd (Fedora's tuned-based power-profiles
# provider, a common default) conflicts with it, so this is best-effort:
# with tuned-ppd installed the module is simply inert.
if ! sudo dnf install -y power-profiles-daemon >/dev/null 2>&1; then
  warn "power-profiles-daemon not installable (tuned-ppd conflict?) - the bar's power-profile widget will be inert; swap tuned-ppd out for power-profiles-daemon manually if you want it."
fi

# network-manager-applet"""),

        ('log "Writing rofi config + Catppuccin theme..."',
         'log "Writing rofi config..."'),
        ("# 13. Catppuccin GTK3/4 theme (best-effort \u2014 cosmetic only, won't fail the script)",
         "# 13. Base GTK theme - follows the active desktop theme (best-effort, cosmetic only)"),
        ('--description "before sway-setup-cattpuccin.sh"',
         '--description "before fedora-sway-setup.sh"'),
    ):
        if old not in text:
            print("WARN: stale line not found: %r" % old[:60])
        text = text.replace(old, new)
    for old, new in (
        # sway binds: launch GUI apps/launchers through fresh-env so they
        # carry the CURRENT GTK_THEME instead of sway's login-time
        # snapshot (a stale theme name makes GTK fall back to Adwaita)
        # sway config: mark activation on other workspaces urgent (link
        # opening a new tab on another desktop flags it on the bar)
        ("""for_window [app_id="UpdatesTask"] floating enable, resize set 1000 550, move position center""",
         """for_window [app_id="UpdatesTask"] floating enable, resize set 1000 550, move position center

# A window opened via an xdg-activation token (clicking a link that opens
# a new tab/window on ANOTHER workspace, chat notifications, etc.) flags
# that workspace URGENT instead of stealing focus - waybar's
# sway/workspaces module then highlights the workspace number on the bar
# (red pill, via the installer-appended workspace-state CSS), and the
# window border takes the client.urgent color above.
focus_on_window_activation urgent"""),
        ("bindsym $mod+space exec rofi -show drun",
         "bindsym $mod+space exec ~/.local/bin/fresh-env rofi -show drun"),
        ("bindsym $mod+shift+space exec rofi -show run",
         "bindsym $mod+shift+space exec ~/.local/bin/fresh-env rofi -show run"),
        ("bindsym $mod+e exec pcmanfm",
         "bindsym $mod+e exec ~/.local/bin/fresh-env pcmanfm"),
        ("bindsym $mod+shift+w exec ~/.local/bin/wallpaper-picker.sh",
         "bindsym $mod+shift+w exec ~/.local/bin/fresh-env ~/.local/bin/wallpaper-picker.sh"),
        ("bindsym $mod+p exec system-config-printer",
         "bindsym $mod+p exec ~/.local/bin/fresh-env system-config-printer"),
        # cliamp toggle: sway's scratchpad-show JSON prints "success": true
        # (with a space); the i3-inherited no-space grep never matched, so
        # every successful show ran the hide fallback right after it -
        # the window "blinking past" on Mod+m
        ("""swaymsg '[con_mark="cliamp-scratch"] scratchpad show' | grep -q '"success":true'""",
         """swaymsg '[con_mark="cliamp-scratch"] scratchpad show' | grep -q '"success": *true'"""),
        ("bindsym $mod+shift+p exec ~/.local/bin/powermenu.sh",
         "bindsym $mod+shift+p exec ~/.local/bin/fresh-env ~/.local/bin/powermenu.sh"),
    ):
        if old not in text:
            print("WARN: sway bind not found: %r" % old[:50])
        text = text.replace(old, new, 1)

    fresh_env_block = (
        'chmod +x "$BIN/waybar-launch.sh"\n\n'
        "# fresh-env: exec wrapper for the sway binds above - re-reads the CURRENT\n"
        "# GTK_THEME from environment.d (waybar-theme.sh keeps it in step with the\n"
        "# active desktop theme). Sway's own environment is a login-time snapshot,\n"
        "# so apps launched from its binds would otherwise carry a stale theme\n"
        "# name - and a GTK app whose inherited GTK_THEME no longer exists falls\n"
        "# all the way back to stock Adwaita, ignoring the correct gsettings value.\n"
        "cat > \"$BIN/fresh-env\" <<'EOF'\n"
        "#!/usr/bin/env bash\n"
        "set -u\n"
        "gt=\"$(sed -n 's/^GTK_THEME=//p' \"$HOME/.config/environment.d/gtk-theme.conf\" 2>/dev/null || true)\"\n"
        "[ -n \"$gt\" ] && export GTK_THEME=\"$gt\"\n"
        "exec \"$@\"\n"
        "EOF\n"
        'chmod +x "$BIN/fresh-env"\n'
    )
    old_launch = 'chmod +x "$BIN/waybar-launch.sh"'
    assert old_launch in text, "waybar-launch chmod anchor missing"
    text = text.replace(old_launch, fresh_env_block, 1)

    vscode_block = '''  set_toml_key "$HOME/.vibe/config.toml" theme "$vibe_theme"
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
systemctl --user try-restart xdg-desktop-portal-manual.service \
  xdg-desktop-portal-gtk-manual.service xdg-desktop-portal-wlr-manual.service 2>/dev/null || true

# libadwaita apps (gnome-calendar and every GNOME 47+ app) deliberately
# block theme CSS - the only levers GNOME allows are the color-scheme
# (already prefer-dark via gsettings) and the PRESET accent colors. Map
# the active theme's accent hue to the closest preset so highlights,
# selected-day and buttons follow the rice's hue as closely as GNOME
# permits.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$I3_CURRENT" <<'ACCENTEOF'
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
EOF'''
    old_sync = '''  set_toml_key "$HOME/.vibe/config.toml" theme "$vibe_theme"
fi
exit 0
EOF'''
    assert old_sync in text, "app-theme-sync tail anchor missing"
    text = text.replace(old_sync, vscode_block, 1)

    for old, new in summary_fixes:
        if old not in text:
            print("WARN: summary line not found: %r" % old[:60])
        text = text.replace(old, new)
    # polybar widget click notes -> waybar
    text = re.sub(
        r"\n Polybar widgets are clickable where it makes sense:\n"
        r"(?: .*\n)+",
        "\n Waybar widgets are clickable where it makes sense:\n"
        "   left/right-click the network, bluetooth, battery, clock or tray\n"
        "   widgets - see each theme's own config.jsonc for specifics.\n",
        text)

    DST.write_text(text, encoding="utf-8")
    print("wrote %s (%d lines)" % (DST, text.count("\n") + 1))


def new_hancore_section():
    generator = readf(HERE / "hancore-theme-gen.py")
    shims = [readf(HERE / "hancore-shims" / f)
             for f in ("wttrbar", "hancore-battery-status",
                       "hancore-update-check", "vscode-theme-sync")]
    shim_heredocs = []
    for fname, body in zip(("wttrbar", "hancore-battery-status",
                            "hancore-update-check", "vscode-theme-sync"), shims):
        shim_heredocs.append('cat > "$BIN/%s" <<\'HANCORESHIM_EOF\'' % fname)
        shim_heredocs.extend(body.split("\n"))
        shim_heredocs.append("HANCORESHIM_EOF")
    section = '''# ----------------------------------------------------------------------------
# 6. Desktop theme collection - HANCORE-linux/waybar-themes
# ----------------------------------------------------------------------------
# This replaces the old embedded Catppuccin/polybar-port collection: the
# bar themes now come from github.com/HANCORE-linux/waybar-themes (MIT),
# fetched at install time and adapted from their Omarchy/Hyprland home to
# plain Sway on Fedora:
#   - hyprland/workspaces + hyprland/window -> sway/*; modules with no
#     equivalent here (omarchy logo, voxtype voice typing, the
#     $OMARCHY_PATH indicators, pacman update checker, gpu-usage) drop out
#   - omarchy-*/hyprctl/hyprpicker/alacritty/ghostty/wttrbar commands are
#     rewritten to this rice's own tools (app-menu, powermenu, wifi-menu,
#     colorpicker, osd-volume, caffeine/dnd toggles, software-update,
#     kitty, swaymsg) plus three shims written below (~/.local/bin)
#   - 85 of the styles @import ../omarchy/current/theme/waybar.css for
#     @background/@foreground/@transparent - hancore-theme-gen.py derives
#     a palette from each theme's own CSS and writes both that import
#     target and everything else the rice's switcher applies per theme:
#     rofi (.rasi + powermenu), kitty, dunst, starship and sway border
#     fragments, at the same paths the old collection used, so
#     ~/.local/bin/waybar-theme.sh switches the whole desktop per pick
#     exactly as before
#   - a [colors] ini per theme feeds the repo's GTK/Neovim/VS Code
#     generators (section 15); the clock module gets the old rice's
#     matching-GTK gnome-calendar click back
# The first theme (sorted) is seeded as active everywhere.
if [ "$CLEAN_THEMES" = "1" ]; then
  log "Cleaning out existing desktop themes (waybar/rofi/kitty/dunst/starship/borders/nvim/GTK)..."
  rm -rf "$CONF/waybar/themes" "$CONF/rofi/themes" "$CONF/kitty/themes" \\
         "$CONF/dunst/themes" "$CONF/starship/themes" "$CONF/i3/themes" \\
         "$CONF/polybar/themes"
  rm -f "$CONF/rofi/current.rasi" "$CONF/rofi/current-powermenu.rasi" \\
         "$CONF/kitty/current.conf" "$CONF/dunst/dunstrc" \\
         "$CONF/sway/current-borders.conf" "$CONF/starship.toml" \\
         "$CONF/waybar/current-theme-name"
  if [ -d "$HOME/.themes" ]; then
    find "$HOME/.themes" -mindepth 1 -maxdepth 1 -type d -name 'Rice-*' -exec rm -rf {} + 2>/dev/null || true
  fi
  if [ -d "$CONF/nvim/colors" ]; then
    find "$CONF/nvim/colors" -maxdepth 1 -name 'rice-*.lua' -delete 2>/dev/null || true
  fi
  log "Old themes removed."
fi

log "Fetching HANCORE waybar themes (github.com/HANCORE-linux/waybar-themes)..."
HANCORE_TMP="$(mktemp -d)"
if git clone --depth 1 -q https://github.com/HANCORE-linux/waybar-themes.git "$HANCORE_TMP"; then
  log "Adapting themes for Sway + generating matching rofi/kitty/dunst/starship/border themes..."
  cat > "$HANCORE_TMP/hancore-theme-gen.py" <<'HANCOREGEN_EOF'
''' + generator + '''
HANCOREGEN_EOF
  HANCORE_OUT="$(python3 -I "$HANCORE_TMP/hancore-theme-gen.py" "$HANCORE_TMP" "$HOME" 2>&1)" \\
    || warn "Theme adaptation reported failures:$(printf '%s\\n' "$HANCORE_OUT" | tail -5)"
  log "$(printf '%s\\n' "$HANCORE_OUT" | tail -2 | head -1)"
  unset HANCORE_OUT
else
  warn "git clone of HANCORE-linux/waybar-themes failed (network issue?) - no bar themes installed; re-run this script later."
fi
rm -rf "$HANCORE_TMP"

# Helper shims the adapted themes' modules exec by name - installed into
# ~/.local/bin, which waybar-launch.sh puts on the bar's PATH.
log "Writing theme helper shims (wttrbar, battery status, update check)..."
''' + "\n".join(shim_heredocs) + '''
chmod +x "$BIN/wttrbar" "$BIN/hancore-battery-status" "$BIN/hancore-update-check" "$BIN/vscode-theme-sync"

# Nerd Font widget glyphs for the helper scripts the sections below sed
# into $BIN (polybar-bluetooth/caffeine/dnd/layout). These were defined
# by the old theme-collection section that's gone now; carried over
# verbatim so the literal Private-Use-Area glyphs stay byte-exact.
'''
    src_lines = SRC.read_text(encoding="utf-8").split("\n")
    ico_defs = [ln for ln in src_lines
                if re.match(r"^ICO_(BT|COFFEE|BELL|BELL_OFF|SPLIT_H|SPLIT_V|STACKING|TABBED)=", ln)]
    if len(ico_defs) != 8:
        sys.exit("expected 8 ICO_* glyph definitions in the source, found %d" % len(ico_defs))
    section += "\n".join(ico_defs) + "\n"
    return section.split("\n")


if __name__ == "__main__":
    main()
