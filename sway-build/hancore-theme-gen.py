#!/usr/bin/env python3
"""Adapt HANCORE-linux/waybar-themes to this rice's Sway/Fedora setup.

For each theme dir in the clone's config/ (excluding "test"):
  1. Parse config.jsonc (JSONC: //- and /**/-comments, trailing commas,
     BOM/NUL bytes, multi-line escaped strings).
  2. Adapt it: hyprland/* modules -> sway/*, drop modules with no
     equivalent here (omarchy logo, voxtype, the $OMARCHY_PATH
     indicators, pacman updates, gpu-usage), rewrite omarchy-*/hyprctl/
     alacritty/ghostty/wttrbar/hyprpicker commands to this rice's own
     tools (shims live in ~/.local/bin), repoint bundled-script exec
     paths at the theme's own install dir, and give the clock a matching
     GTK gnome-calendar click like the old rice's bars had.
  3. Extract a role palette from style.css (+ locally-imported css like
     rose-pine.css + the config's calendar spans) by classifying every
     color against the 26 canonical Catppuccin Mocha roles in HLS space
     (same algorithm as the repo's generate-gtk-themes.py), falling back
     to canonical Mocha for roles a theme doesn't define.
  4. Write, into $DEST (an install root - normally $HOME):
       .config/waybar/themes/<n>/{config.jsonc,style.css,palette.css,+bundled scripts}
       .config/rofi/themes/<n>.rasi + <n>-powermenu.rasi
       .config/kitty/themes/<n>.conf
       .config/dunst/themes/<n>.dunstrc
       .config/starship/themes/<n>.toml
       .config/sway/themes/<n>.conf           (sway client.* borders)
       .config/polybar/themes/<n>.ini       ([colors] block - feeds the
         repo's generate-gtk/nvim/vscode-themes.py, exactly like the old
         rice's own themes)
     and seed the first theme (sorted) as the active one everywhere the
     switcher (~/.local/bin/waybar-theme.sh) looks for "current" files,
     including the Omarchy-format palette import at
     .config/omarchy/current/theme/waybar.css that 85 of the styles
     @import for @background/@foreground/@transparent.

Never aborts the whole run on one bad theme: each theme is wrapped, a
parse/rewrite failure just logs a skip line.

Usage: hancore-theme-gen.py <hancore-clone-dir> <dest-home>
"""
import colorsys
import json
import os
import pathlib
import re
import shutil
import sys

CLONE = pathlib.Path(sys.argv[1]).resolve()
DEST = pathlib.Path(sys.argv[2]).resolve()
CONF = DEST / ".config"

# ---------------------------------------------------------------- palette --
CANONICAL_MOCHA = {
    "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7", "mauve": "#cba6f7",
    "red": "#f38ba8", "maroon": "#eba0ac", "peach": "#fab387", "yellow": "#f9e2af",
    "green": "#a6e3a1", "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
    "blue": "#89b4fa", "lavender": "#b4befe", "text": "#cdd6f4", "subtext1": "#bac2de",
    "subtext0": "#a6adc8", "overlay2": "#9399b2", "overlay1": "#7f849c", "overlay0": "#6c7086",
    "surface2": "#585b70", "surface1": "#45475a", "surface0": "#313244", "base": "#1e1e2e",
    "mantle": "#181825", "crust": "#11111b",
}
NEUTRAL_ROLES = {
    "text", "subtext1", "subtext0", "overlay2", "overlay1", "overlay0",
    "surface2", "surface1", "surface0", "base", "mantle", "crust",
}


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hex_to_hls(h):
    r, g, b = (c / 255.0 for c in hex_to_rgb(h))
    return colorsys.rgb_to_hls(r, g, b)


def hue_dist(h1, h2):
    d = abs(h1 - h2) % 1.0
    return min(d, 1.0 - d)


_CANON = {role: hex_to_hls(v) for role, v in CANONICAL_MOCHA.items()}
_REVC = {v.lower(): k for k, v in CANONICAL_MOCHA.items()}


def classify(hexval):
    """Closest canonical Mocha role for a color (hue for chromatic,
    lightness-only among the neutral ramp for near-gray)."""
    hexval = hexval.lower()
    if hexval in _REVC:
        return _REVC[hexval]
    h, l, s = hex_to_hls(hexval)
    achromatic = s < 0.15
    best = None
    for role, (ch, cl, cs) in _CANON.items():
        if achromatic and role not in NEUTRAL_ROLES:
            continue
        dist = (abs(l - cl) if achromatic else
                hue_dist(h, ch) * 4.0 + abs(l - cl) + abs(s - cs) * 0.8)
        if best is None or dist < best[0]:
            best = (dist, role)
    return best[1]


def luminance(hexval):
    r, g, b = (c / 255.0 for c in hex_to_rgb(hexval))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def collect_colors(text, weight, acc):
    """Accumulate #hex/#rrggbbaa/rgb()/rgba() colors with a weight."""
    for m in re.findall(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", text):
        acc[m[:7].lower()] = acc.get(m[:7].lower(), 0) + weight
    for r, g, b in re.findall(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", text):
        h = "#{:02x}{:02x}{:02x}".format(int(r), int(g), int(b))
        acc[h] = acc.get(h, 0) + weight


def extract_palette(css_text, imported_texts, config_text):
    """Role -> resolved color for one theme."""
    acc = {}
    # @define-color values matter more (they're the theme's own vocabulary)
    defines = re.findall(r"@define-color\s+[\w-]+\s+(#[0-9a-fA-F]{6})", css_text)
    for d in defines:
        acc[d.lower()] = acc.get(d.lower(), 0) + 5
    collect_colors(css_text, 1, acc)
    for t in imported_texts:
        collect_colors(t, 4, acc)  # rose-pine.css etc. ARE the palette
    collect_colors(config_text, 1, acc)

    by_role = {}
    for hexval, w in acc.items():
        by_role.setdefault(classify(hexval), []).append((w, hexval))

    def pick(role, prefer_saturated=True):
        cands = by_role.get(role)
        if not cands:
            return CANONICAL_MOCHA[role]
        key = (lambda wh: (wh[0], hex_to_hls(wh[1])[2] if prefer_saturated else -hex_to_hls(wh[1])[2]))
        return max(cands, key=key)[1]

    # Neutrals: prefer the most prominent (frequent) representative.
    base = pick("base", prefer_saturated=False)
    mantle = pick("mantle", prefer_saturated=False)
    # Sensible ordering: mantle should be at least as dark as base.
    if luminance(mantle) > luminance(base):
        base, mantle = mantle, base
    text = pick("text", prefer_saturated=False)
    subtext = pick("subtext0", prefer_saturated=False)

    dark = luminance(base) < 0.5
    if dark:
        # Defensive contrast floor: some themes' CSS yields no light
        # neutral at all, and a dark-on-dark palette.css makes every
        # @fg-drawn label invisible except on hover (hover styles
        # invert colors). Guarantee readable text no matter what.
        if luminance(text) < luminance(base) + 0.3:
            lights = [h for h, w in acc.items()
                      if luminance(h) > luminance(base) + 0.3]
            text = max(lights, key=lambda h: acc[h]) if lights else CANONICAL_MOCHA["text"]
        if luminance(subtext) > luminance(text):
            subtext = text
    else:
        if luminance(text) > luminance(base) - 0.3:
            darks = [h for h, w in acc.items()
                     if luminance(h) < luminance(base) - 0.3]
            text = max(darks, key=lambda h: acc[h]) if darks else CANONICAL_MOCHA["crust"]
        if luminance(subtext) < luminance(text):
            subtext = text

    palette = {
        "base": base,
        "mantle": mantle,
        "surface0": pick("surface0", prefer_saturated=False),
        "surface1": pick("surface1", prefer_saturated=False),
        "surface2": pick("surface2", prefer_saturated=False),
        "text": text,
        "subtext": subtext,
        "red": pick("red"),
        "green": pick("green"),
        "yellow": pick("yellow"),
        "blue": pick("blue"),
        "cyan": pick("teal"),
        "teal": pick("teal"),
        "orange": pick("peach"),
        "pink": pick("pink"),
        "lavender": pick("lavender"),
    }
    # accent = the theme's own most prominent saturated color (frequency-
    # weighted), so rofi/kitty/dunst/borders/GTK all follow the accent the
    # bar actually shows - NOT a hardcoded mauve. Colors too close to the
    # base/foreground neutrals are skipped; themes that define no colors
    # of their own keep the canonical Mocha accent (their whole palette
    # IS Mocha then).
    best = None
    for hexval, w in acc.items():
        h, l, s = hex_to_hls(hexval)
        if s < 0.25:
            continue  # neutral ramp, not an accent
        if abs(luminance(hexval) - luminance(base)) < 0.12:
            continue  # too close to the background to read as an accent
        if abs(luminance(hexval) - luminance(text)) < 0.12:
            continue
        key = (w, s)
        if best is None or key > best[0]:
            best = (key, hexval)
    palette["accent"] = best[1] if best else CANONICAL_MOCHA["mauve"]
    return palette, dark, by_role


# ------------------------------------------------------------------ jsonc --
def strip_jsonc(text):
    """Remove //- and /**/-comments (string-aware) and trailing commas,
    plus any BOM/NUL garbage, so json.loads can parse config.jsonc."""
    text = text.replace("\x00", "").lstrip("﻿")
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            out.append(text[i:j + 1])
            i = j + 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    cleaned = "".join(out)
    # trailing commas before ] or }
    cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
    return cleaned


# ----------------------------------------------------------- config adapt --
DROP_MODULES = {
    "custom/omarchy",                       # omarchy logo font glyph + menu
    "custom/voxtype",                       # voice typing (no equivalent)
    "custom/idle-indicator",                # $OMARCHY_PATH indicator script
    "custom/notification-silencing-indicator",
    "custom/screenrecording-indicator",
    "custom/updatespacman",                 # Arch-only pacman checker
    "custom/gpu-usage",                     # gpu-usage-waybar not on Fedora
}

RENAME_MODULES = {
    "hyprland/workspaces": "sway/workspaces",
    "hyprland/window": "sway/window",
}

CMD_REWRITES = [
    (re.compile(r"^omarchy-menu power$"), "~/.local/bin/powermenu.sh"),
    (re.compile(r"^omarchy-menu( system)?$"), "~/.local/bin/app-menu.sh"),
    (re.compile(r"^omarchy-launch-or-focus-tui (\S+)$"), r"kitty -e \1"),
    (re.compile(r"^omarchy-launch-floating-terminal-with-presentation omarchy-update$"),
     "~/.local/bin/software-update.sh"),
    (re.compile(r"^omarchy-launch-floating-terminal-with-presentation .*$"), "true"),
    (re.compile(r"^omarchy-launch-wifi$"), "~/.local/bin/wifi-menu.sh"),
    (re.compile(r"^omarchy-launch-bluetooth$"), "blueman-manager"),
    (re.compile(r"^omarchy-launch-audio$"), "~/.local/bin/osd-volume.sh"),
    (re.compile(r"^omarchy-toggle-idle$"), "~/.local/bin/caffeine-toggle.sh"),
    (re.compile(r"^omarchy-toggle-notification-silencing$"), "~/.local/bin/dnd-toggle.sh"),
    (re.compile(r"^omarchy-update-available$"), "~/.local/bin/hancore-update-check"),
    (re.compile(r"^omarchy-theme-current$"), "cat ~/.config/waybar/current-theme-name"),
    (re.compile(r"^omarchy-theme-set( \S+)?$"), "~/.local/bin/waybar-theme.sh"),
    (re.compile(r"^omarchy-battery-status$"), "~/.local/bin/hancore-battery-status"),
    (re.compile(r'^notify-send -u low "\$\(omarchy-battery-status\)"$'),
     'notify-send -u low "$(~/.local/bin/hancore-battery-status)"'),
    (re.compile(r"^omarchy-capture-screenrecording$"), "~/.local/bin/screenshot.sh"),
    (re.compile(r"^omarchy-cmd-screenrecord$"), "~/.local/bin/screenshot.sh"),
    (re.compile(r"^omarchy-cmd-tzupdate$"), "true"),
    (re.compile(r"^hyprctl dispatch workspace e\+1$"), "swaymsg workspace next_on_output"),
    (re.compile(r"^hyprctl dispatch workspace e-1$"), "swaymsg workspace prev_on_output"),
    (re.compile(r"^hyprpicker$"), "~/.local/bin/colorpicker.sh"),
    (re.compile(r"^alacritty --class=Impala -e impala$"), "~/.local/bin/wifi-menu.sh"),
    (re.compile(r"^alacritty --class=Wiremix -e wiremix$"), "~/.local/bin/osd-volume.sh"),
    (re.compile(r"^wiremix$"), "~/.local/bin/osd-volume.sh"),
    (re.compile(r"^xdg-terminal-exec$"), "kitty"),
    (re.compile(r"^ghostty -e nvtop$"), "kitty -e btop"),
]

# bundled per-theme scripts referenced by ~/.config/waybar/<file> paths
BUNDLED_SCRIPTS = ("window_pill.py", "cava.sh", "scrolling-mpris.py")

LAYOUT_KEYS = ("modules-left", "modules-center", "modules-right")


def rewrite_cmd(cmd, name):
    """One command string, adapted. Order: bundled-script paths first
    (substring, they appear mid-command too), then exact rewrites."""
    for script in BUNDLED_SCRIPTS:
        cmd = cmd.replace(
            "~/.config/waybar/" + script,
            "~/.config/waybar/themes/%s/%s" % (name, script))
    for pat, repl in CMD_REWRITES:
        if pat.match(cmd):
            return pat.sub(repl, cmd)
    return cmd


def rewrite_value(v, name):
    if isinstance(v, str):
        return rewrite_cmd(v, name)
    if isinstance(v, dict):
        return {k: rewrite_value(x, name) for k, x in v.items()}
    if isinstance(v, list):
        return [rewrite_value(x, name) for x in v]
    return v


def unresolvable(block):
    """A module block that still references Omarchy/Hyprland machinery
    after rewriting has no equivalent here - drop the module."""
    return "omarchy" in block or "$OMARCHY_PATH" in block or "hyprctl" in block


def adapt_config(cfg, name):
    """Restructure one parsed waybar config for this rice. Drops are
    reported, never fatal."""
    dropped = []

    # 1. Rename hyprland/* module blocks to their sway/* equivalents.
    for old, new in RENAME_MODULES.items():
        if old in cfg:
            cfg[new] = cfg.pop(old)

    def fixlist(arr):
        return [RENAME_MODULES.get(m, m) for m in arr]

    for lk in LAYOUT_KEYS:
        if isinstance(cfg.get(lk), list):
            cfg[lk] = fixlist(cfg[lk])
    for block in cfg.values():
        if isinstance(block, dict) and isinstance(block.get("modules"), list):
            block["modules"] = fixlist(block["modules"])

    # 2. Rewrite every command string in every module block.
    for key in list(cfg):
        block = cfg[key]
        if isinstance(block, dict):
            cfg[key] = rewrite_value(block, name)

    # 3b. clock clicks, universal for every theme: left click keeps
    #     waybar's built-in format-alt toggle - defining a module-level
    #     on-click command would make waybar run it AND the toggle, which
    #     is exactly the "format changes AND the calendar opens" bug - so
    #     the clock gets NO on-click command at all. Right click opens
    #     the floating, theme-matched gnome-calendar instead.
    for ck in ("clock", "custom/clock"):
        block = cfg.get(ck)
        if isinstance(block, dict):
            block.pop("on-click", None)
            block.pop("actions", None)
            cal = block.get("calendar")
            if isinstance(cal, dict):
                cal.pop("on-click", None)
                cal.pop("on-click-right", None)
            block["on-click-right"] = "GTK_THEME=Rice-%s gnome-calendar" % name

    # 3b. custom/update: restore the old rice's update widget exactly -
    #     a visible pending-update COUNT (polybar-updates.sh style, incl.
    #     0) and a click that opens software-update.sh in a floating
    #     kitty (the sway config already has the UpdatesTask floating
    #     rule). The upstream module only shows a static omarchy glyph.
    upd = cfg.get("custom/update")
    if isinstance(upd, dict):
        cfg["custom/update"] = {
            "exec": "~/.local/bin/hancore-update-check",
            "format": "{}",
            "tooltip": False,
            "on-click": "kitty --class UpdatesTask -e ~/.local/bin/software-update.sh",
        }

    # 3c. idle_inhibitor -> custom/caffeine: the native module is an
    #     independent Wayland inhibitor that never reflected the rice's
    #     Mod+C caffeine toggle (two mechanisms, no shared state).
    #     Replace it everywhere with a widget backed by
    #     ~/.local/bin/caffeine-state.sh, so one mechanism (caffeine)
    #     drives both the keybind and the bar, and the icon always shows
    #     the real state. Clicking the widget runs the same toggle.
    for lk in ("modules-left", "modules-center", "modules-right"):
        arr = cfg.get(lk)
        if isinstance(arr, list):
            cfg[lk] = ["custom/caffeine" if m == "idle_inhibitor" else m
                       for m in arr]
    for key, block in list(cfg.items()):
        if isinstance(block, dict) and isinstance(block.get("modules"), list):
            block["modules"] = ["custom/caffeine" if m == "idle_inhibitor" else m
                                for m in block["modules"]]
    cfg.pop("idle_inhibitor", None)
    cfg["custom/caffeine"] = {
        "exec": "~/.local/bin/caffeine-state.sh",
        "return-type": "json",
        "interval": 2,
        "on-click": "~/.local/bin/caffeine-toggle.sh",
        "tooltip": True,
    }

    # 4. Drop module blocks with no equivalent: the known set, plus any
    #    block that still references omarchy/$OMARCHY_PATH/hyprctl.
    module_keys = [k for k, v in cfg.items()
                   if isinstance(v, dict) and k not in LAYOUT_KEYS]
    drop = set()
    for key in module_keys:
        block = cfg[key]
        if key in DROP_MODULES or unresolvable(json.dumps(block)):
            drop.add(key)
            dropped.append(key)
    for key in drop:
        cfg.pop(key, None)

    # 5. Drop them from the layouts, and drop groups whose children all
    #    went away (an empty group renders nothing but may still draw a
    #    background pill in some styles).
    def prune(arr):
        return [m for m in arr if m not in drop]

    for lk in LAYOUT_KEYS:
        if isinstance(cfg.get(lk), list):
            cfg[lk] = prune(cfg[lk])
    for key in list(cfg):
        block = cfg[key]
        if isinstance(block, dict) and isinstance(block.get("modules"), list):
            block["modules"] = prune(block["modules"])
            if not block["modules"] and not (key in DROP_MODULES or
                                             unresolvable(json.dumps(block))):
                # a group with every child dropped still names nothing -
                # drop it too
                cfg.pop(key, None)
                dropped.append(key)
            elif not block["modules"]:
                cfg.pop(key, None)

    # 6. Sweep the layout lists for any name whose block is gone (e.g.
    #    drawer children removed via DROP_MODULES in step 4's parent).
    present = set(k for k, v in cfg.items() if isinstance(v, dict))
    for lk in LAYOUT_KEYS:
        arr = cfg.get(lk)
        if isinstance(arr, list):
            cfg[lk] = [m for m in arr
                       if not m.startswith(("custom/", "group/")) or m in present]
    return cfg, dropped


# ---------------------------------------------------------------- templates ---
def strip_gtk4_at_rules(css_text):
    """Remove @keyframes blocks (and any other GTK4-only at-rule blocks).
    waybar is GTK3, whose CSS parser has no @keyframes - and it silently
    discards EVERYTHING after the first one in the file: with them left
    in place, every rule below the first @keyframes (including the
    workspace-state block this installer appends) never applied. The
    animations never ran on waybar anyway - dead code even upstream,
    where these themes were built for the same GTK3 waybar."""
    out = []
    skipping = False
    depth = 0
    for ln in css_text.split("\n"):
        stripped = ln.lstrip()
        if not skipping and stripped.startswith("@keyframes"):
            skipping = True
            depth = ln.count("{") - ln.count("}")
            if depth <= 0:  # single-line block
                skipping = False
            continue
        if skipping:
            depth += ln.count("{") - ln.count("}")
            if depth <= 0:
                skipping = False
            continue
        out.append(ln)
    return "\n".join(out)


def mix(h1, h2, t):
    """Linear mix between two hex colors, t in [0, 1]."""
    a = hex_to_rgb(h1)
    b = hex_to_rgb(h2)
    return "#{:02x}{:02x}{:02x}".format(
        *(round(x + (y - x) * t) for x, y in zip(a, b)))


def starship_colors(palette, by_role):
    """The prompt's six segment colors, derived the way the old rice's
    starship theming derived them: the base background stepped toward
    the foreground (lightened on dark themes, darkened on light ones) in
    two further steps for the neutral username/directory/git segments,
    then the theme's own cyan/magenta/blue for the language-icon/
    docker/time segments. A theme that defines none of those three hues
    (most HANCORE styles carry one accent only) falls back to the theme's
    own accent plus two mixes of it, so the prompt still follows the bar
    instead of snapping back to stock Catppuccin pastels."""
    has = lambda *roles: any(r in by_role for r in roles)
    p = dict(palette)
    p["seg_mid"] = mix(p["base"], p["text"], 0.15)
    p["seg_high"] = mix(p["base"], p["text"], 0.30)
    p["star_cyan"] = p["cyan"] if has("teal", "sky") else p["accent"]
    p["star_pink"] = p["pink"] if has("pink", "lavender") else mix(p["accent"], p["text"], 0.30)
    p["star_blue"] = p["blue"] if has("blue", "sapphire") else mix(p["accent"], "#000000", 0.30)
    return p


def extract_design(css_text):
    """Design tokens from the theme's own style.css, so the generated
    rofi/dunst themes follow the bar's look (corner rounding, font) the
    same way the old rice's hand-made per-theme files did. Radius = the
    most common border-radius in the stylesheet (module pills dominate);
    a 50%/pill bar gets generously rounded menus. Font = the first
    font-family the style declares."""
    radii = re.findall(r"border-radius:\s*([\d.]+)px", css_text)
    radius = 12
    if radii:
        radius = int(float(max(set(radii), key=radii.count)))
    elif re.search(r"border-radius:\s*50%", css_text):
        radius = 20
    if radius >= 40:  # pill-style caps - keep menus rounded but sane
        radius = 20
    radius = max(0, min(radius, 20))
    m = re.search(r"font-family:\s*['\"]([^'\"]+)['\"]", css_text)
    font = m.group(1) if m else "JetBrainsMono Nerd Font"
    return radius, font


ROFI_TEMPLATE = """* {{
    base: {base}ff;
    mantle: {mantle}ff;
    text: {text}ff;
    subtext: {subtext}ff;
    accent: {accent}ff;
    surface0: {surface0}ff;

    background-color: @base;
    text-color: @text;
    font: "{font} 11";
}}

window {{
    width: 30%;
    border-radius: {radius}px;
    background-color: @base;
}}

inputbar {{
    padding: 10px;
    background-color: @mantle;
    border-radius: {elem_radius}px;
    children: [prompt, entry];
}}

prompt {{ text-color: @accent; padding: 0 8px 0 0; }}
entry  {{ text-color: @text; }}

listview {{
    lines: 14;
    padding: 8px 0;
}}

element {{
    padding: 6px 10px;
    border-radius: {elem_radius}px;
}}
element-text, element-icon {{
    background-color: inherit;
    text-color: inherit;
}}

element selected {{
    background-color: @surface0;
    text-color: @accent;
}}
"""

ROFI_POWERMENU_TEMPLATE = """* {{
    base: {base}ff;
    mantle: {mantle}ff;
    text: {text}ff;
    subtext: {subtext}ff;
    accent: {accent}ff;
    surface0: {surface0}ff;

    background-color: @base;
    text-color: @text;
    font: "{font} 11";
}}

window {{
    width: 560px;
    background-color: @base;
    border: 2px;
    border-color: @accent;
    border-radius: {radius}px;
    padding: 24px;
}}

mainbox {{
    children: [ listview ];
}}

listview {{
    columns: 5;
    lines: 1;
    spacing: 10px;
    fixed-columns: true;
    scrollbar: false;
}}

element {{
    children: [ element-text ];
    padding: 26px;
    border-radius: {elem_radius}px;
    background-color: @mantle;
}}
element normal.normal {{
    text-color: @text;
}}
element selected {{
    background-color: @surface0;
    border: 2px;
    border-color: @accent;
    border-radius: {elem_radius}px;
}}
element-text {{
    font: "{font} 26";
    background-color: transparent;
    text-color: inherit;
    horizontal-align: 0.32;
    vertical-align: 0.5;
}}
"""

KITTY_TEMPLATE = """# {name}
foreground              {text}
background              {base}
selection_foreground    {base}
selection_background    {text}
cursor                  {accent}
cursor_text_color       {base}

color0  {surface1}
color8  {surface2}
color1  {red}
color9  {red}
color2  {green}
color10 {green}
color3  {yellow}
color11 {yellow}
color4  {blue}
color12 {blue}
color5  {pink}
color13 {pink}
color6  {cyan}
color14 {cyan}
color7  {text}
color15 {subtext}
"""

DUNST_TEMPLATE = """[global]
font = {font} 10
frame_width = 2
frame_color = "{accent}"
corner_radius = {radius}
background = "{base}"
foreground = "{text}"
width = 320
height = 100
offset = 12x40
padding = 12
horizontal_padding = 12
separator_color = "{surface1}"
mouse_left_click = do_action, close_current
mouse_middle_click = do_action, close_all
mouse_right_click = close_all

[urgency_low]
background = "{base}"
foreground = "{subtext}"
frame_color = "{surface1}"
timeout = 4

[urgency_normal]
background = "{base}"
foreground = "{text}"
frame_color = "{accent}"
timeout = 6

[urgency_critical]
background = "{base}"
foreground = "{red}"
frame_color = "{red}"
timeout = 0
"""

STARSHIP_TEMPLATE = r'''format = """
[]({base})\
$python\
$username\
[](bg:{seg_mid} fg:{base})\
$directory\
[](fg:{seg_mid} bg:{seg_high})\
$git_branch\
$git_status\
[](fg:{seg_high} bg:{star_cyan})\
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
[](fg:{star_cyan} bg:{star_pink})\
$docker_context\
[](fg:{star_pink} bg:{star_blue})\
$time\
[ ](fg:{star_blue})\
"""
command_timeout = 5000
# Disable the blank line at the start of the prompt
# add_newline = false

# You can also replace your username with a neat symbol like  to save some space
[username]
show_always = true
style_user = "bg:{base}"
style_root = "bg:{base}"
format = '[$user ]($style)'

[directory]
style = "bg:{seg_mid}"
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
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:{star_pink}"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:{seg_high}"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:{seg_high}"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:{base}"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:{star_cyan}"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R" # Hour:Minute Format
style = "bg:{star_blue}"
format = '[ $time ]($style)'
'''

# sway client.* border colors
BORDERS_TEMPLATE = """client.focused          {accent}  {base}  {text}  {accent}   {accent}
client.unfocused        {surface1}  {base}  {subtext}  {surface1}   {surface1}
client.focused_inactive {surface2}  {base}  {subtext}  {surface2}   {surface2}
client.urgent           {red}  {base}  {red}  {red}   {red}
"""

# [colors] ini feeding the repo's generate-{gtk,nvim,vscode}-themes.py.
# Every ROLE_CHAINS key is present so the chains always resolve.
COLORS_INI_TEMPLATE = """[colors]
; Palette extracted from the {name} waybar theme's style.css.
base = {base}
mantle = {mantle}
surface0 = {surface0}
surface1 = {surface1}
surface2 = {surface2}
text = {text}
subtext = {subtext}
red = {red}
green = {green}
yellow = {yellow}
blue = {blue}
purple = {accent}
magenta = {accent}
indigo = {accent}
teal = {cyan}
cyan = {cyan}
sky = {cyan}
peach = {orange}
orange = {orange}
pink = {pink}
lavender = {lavender}
"""

# Omarchy-format palette import: what the themes' own
# @import "../omarchy/current/theme/waybar.css" resolves against.
PALETTE_CSS_TEMPLATE = """/* Generated from the {name} theme's own colors - this is what the
   HANCORE styles' @import "../omarchy/current/theme/waybar.css"
   resolves against on this (non-Omarchy) install. */
@define-color background {base};
@define-color foreground {text};
@define-color accent {accent};
@define-color transparent rgba(0, 0, 0, 0);
@define-color border-inactive {surface1};
@define-color cava-fg {accent};

/* Base text color. Many HANCORE styles never set `color:` on their
   module widgets, leaving value text (module percentages etc.) to the
   GTK fallback foreground - near-black when GTK_THEME doesn't resolve
   (invisible on a dark bar, except on hover where the styles do set
   colors). Set at the window level so unstyled widgets INHERIT it
   (every explicit color rule in the theme's own CSS still wins); a
   bare `*` universal-selector rule was tried here first and KILLS
   every rule after it in GTK3's parser (verified live) - do not use
   a `*` rule in these stylesheets. */
window#waybar {{
  color: @foreground;
}}
"""

# Universal workspace-state colors, appended to EVERY theme's style.css
# with the palette's CONCRETE colors (not @accent references - the four
# rose-pine themes don't import the palette file, and appended rules must
# work in all 89). The HANCORE styles were written for Hyprland's class
# names (.active); sway/workspaces emits .focused/.urgent, so without this
# block most themes show no focused-workspace color at all. Sitting at the
# end of the sheet gives these rules the win at equal specificity, so a
# theme's own (hyprland-named) rules stay harmless where they overlap.
WORKSPACE_STATES_CSS = """/* --- appended by this rice's installer: universal workspace states ---
   The upstream styles target Hyprland's class names; sway/workspaces
   uses .focused/.urgent, so the active desktop and any workspace with an
   attention-needing window (xdg-activation, urgency hints) get explicit
   colors here, derived from this theme's own palette. Note: this
   system's waybar marks the current workspace with .visible (verified
   by probe: the class moves with focus; .focused/.active are never
   emitted by sway/workspaces here) - all three are styled so the block
   also works on waybar builds that do use .focused/.active. */
window#waybar #workspaces button.focused,
window#waybar #workspaces button.active,
window#waybar #workspaces button.visible {
  color: @ACCENT@;
}
window#waybar #workspaces button.urgent {
  color: @BASE@;
  background-color: @RED@;
  font-weight: bold;
}
/* Caffeine widget (custom/caffeine, replacing the native idle_inhibitor):
   activated = the rice's stay-awake is on (Mod+C or clicking the widget),
   flagged in the theme accent so it reads at a glance. The light-bulb
   glyph is one of the tallest Nerd Font icons - at the themes' base font
   size with their zero padding it overflows the label box and gets
   clipped at the bar edge (verified live on v7.2) - so pin a smaller
   font and side padding for it. */
window#waybar #custom-caffeine {
  font-size: 12px;
  padding: 0 4px;
}
window#waybar #custom-caffeine.activated {
  color: @ACCENT@;
}
"""


# Sway port of the themes' bundled window_pill.py (drops the hyprctl /
# Hyprland-socket2 dependency, takes the pill's two hardcoded text
# colors from the theme's palette).
WINDOW_PILL_TEMPLATE = r"""#!/usr/bin/env python3
# Sway port of HANCORE's bundled window_pill.py (was: hyprctl activewindow +
# Hyprland socket2). Polls swaymsg -t get_tree twice a second; the pill's two
# text colors come from this theme's palette.
import html
import json
import re
import subprocess
import time

MAX_TITLE_LEN = 42
TOP_FG = "@ACCENT@"
BOTTOM_FG = "@TEXT@"


def focused_node(tree):
    if tree.get("focused"):
        return tree
    for node_type in ("nodes", "floating_nodes"):
        for child in tree.get(node_type, []):
            hit = focused_node(child)
            if hit is not None:
                return hit
    return None


def print_status():
    try:
        tree = json.loads(subprocess.check_output(
            ["swaymsg", "-t", "get_tree"], text=True,
            stderr=subprocess.DEVNULL))
    except Exception:
        tree = {}

    node = focused_node(tree)
    if node is not None and (node.get("app_id") or node.get("window_properties", {}).get("class")):
        top_line = node.get("app_id") or node.get("window_properties", {}).get("class")
        title = node.get("name", "") or ""
        app_class = (top_line or "").lower()
        if "discord" in app_class or "vesktop" in app_class:
            title = re.sub(r"^\(\d+\)\s*", "", title)
            title = re.sub(r"^Discord\s*\|\s*", "", title)
        if len(title) > MAX_TITLE_LEN:
            title = title[:MAX_TITLE_LEN - 3] + "..."
        bottom_line = title
    else:
        top_line = "Desktop"
        bottom_line = "\u00A0"
        try:
            workspaces = json.loads(subprocess.check_output(
                ["swaymsg", "-t", "get_workspaces"], text=True,
                stderr=subprocess.DEVNULL))
            for ws in workspaces:
                if ws.get("focused"):
                    top_line = "Workspace %s" % ws.get("name", "?")
        except Exception:
            pass

    top_line = html.escape(top_line or "")
    bottom_line = html.escape(bottom_line)
    text = (
        "<span size='small' foreground='%s' rise='-1000'>%s</span>\n"
        "<span size='7500' weight='bold' foreground='%s'>%s</span>"
        % (TOP_FG, top_line, BOTTOM_FG, bottom_line)
    )
    print(json.dumps({
        "text": text,
        "class": "custom-window",
        "tooltip": "%s: %s" % (top_line, bottom_line),
    }), flush=True)


while True:
    print_status()
    time.sleep(0.5)
"""


def write_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def process_theme(src_dir, name):
    cfg_path = src_dir / "config.jsonc"
    raw = cfg_path.read_bytes().decode("utf-8", errors="replace")
    cfg = json.loads(strip_jsonc(raw))
    cfg, _dropped = adapt_config(cfg, name)

    css_text = (src_dir / "style.css").read_text(errors="replace")
    css_text = strip_gtk4_at_rules(css_text)

    # locally-imported css files (./rose-pine.css)
    imported = []
    for m in re.findall(r'@import\s+"([^"]+)"', css_text):
        p = (src_dir / m).resolve()
        if p.is_file():
            imported.append(p.read_text(errors="replace"))

    palette, dark, by_role = extract_palette(css_text, imported, raw)
    radius, font = extract_design(css_text)
    palette["radius"] = radius
    palette["elem_radius"] = max(0, radius - 4)
    palette["font"] = font

    tdir = CONF / "waybar" / "themes" / name
    tdir.mkdir(parents=True, exist_ok=True)

    out_cfg = json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"
    write_text(tdir / "config.jsonc", out_cfg)
    # Replace the upstream "@import ../omarchy/current/theme/waybar.css"
    # with the palette INLINED: waybar's own css-import preprocessing pass
    # (its "[debug] Parsing imports" step) mangles the rest of the
    # stylesheet when the import is present - every rule after the import
    # line, including the workspace block appended below, silently never
    # applied. Inlining the @define-colors (and the base-text-color rule)
    # sidesteps waybar's importer entirely. Verified live: identical css
    # with the import line removed renders the focused-workspace
    # indicator; with it, nothing after it applies.
    palette_inline = re.sub(r"^/\*.*?\*/\s*", "",
                            PALETTE_CSS_TEMPLATE.format(name=name, **palette),
                            flags=re.S).rstrip("\n")
    css_text = re.sub(r'^@import\s+"[^"]*omarchy[^"]*"\s*;?\s*$',
                      palette_inline, css_text, count=1, flags=re.M)
    ws_css = (WORKSPACE_STATES_CSS
              .replace("@ACCENT@", palette["accent"])
              .replace("@BASE@", palette["base"])
              .replace("@RED@", palette["red"]))
    write_text(tdir / "style.css", css_text.rstrip("\n") + "\n" + ws_css)
    write_text(tdir / "palette.css", PALETTE_CSS_TEMPLATE.format(name=name, **palette))

    # bundled extras (scripts + imported css), screenshots excluded
    for f in src_dir.iterdir():
        if f.name.endswith(".png") or f.name in ("config.jsonc", "style.css"):
            continue
        if f.is_file():
            if f.name == "window_pill.py":
                write_text(tdir / f.name,
                           WINDOW_PILL_TEMPLATE.replace("@ACCENT@", palette["accent"]).replace("@TEXT@", palette["text"]))
            else:
                shutil.copy2(f, tdir / f.name)
            if f.name.endswith((".py", ".sh")):
                (tdir / f.name).chmod(0o755)

    p = palette
    write_text(CONF / "rofi" / "themes" / (name + ".rasi"),
               ROFI_TEMPLATE.format(**p))
    write_text(CONF / "rofi" / "themes" / (name + "-powermenu.rasi"),
               ROFI_POWERMENU_TEMPLATE.format(**p))
    write_text(CONF / "kitty" / "themes" / (name + ".conf"),
               KITTY_TEMPLATE.format(name=name, **p))
    write_text(CONF / "dunst" / "themes" / (name + ".dunstrc"),
               DUNST_TEMPLATE.format(**p))
    write_text(CONF / "starship" / "themes" / (name + ".toml"),
               STARSHIP_TEMPLATE.format(**starship_colors(palette, by_role)))
    write_text(CONF / "sway" / "themes" / (name + ".conf"),
               BORDERS_TEMPLATE.format(**p))
    write_text(CONF / "polybar" / "themes" / (name + ".ini"),
               COLORS_INI_TEMPLATE.format(name=name, **p))
    return len(json.dumps(cfg)), dark


def main():
    src_conf = CLONE / "config"
    names = []
    for d in sorted(src_conf.iterdir()):
        if not d.is_dir() or d.name == "test" or not (d / "config.jsonc").is_file():
            continue
        names.append(d.name.lower())
    if not names:
        print("no themes found in %s" % src_conf)
        return 1

    ok, failed = [], []
    for d in sorted(src_conf.iterdir()):
        if not d.is_dir() or d.name == "test" or not (d / "config.jsonc").is_file():
            continue
        name = d.name.lower()
        try:
            process_theme(d, name)
            ok.append(name)
            print("theme %s: installed" % name)
        except Exception as e:
            failed.append(name)
            print("theme %s: FAILED (%s)" % (name, e))

    # seed the first theme as active everywhere the switcher looks
    if ok:
        name = ok[0]
        t = CONF / "waybar" / "themes" / name
        shutil.copy2(t / "config.jsonc", CONF / "waybar" / "config.jsonc")
        shutil.copy2(t / "style.css", CONF / "waybar" / "style.css")
        om = CONF / "omarchy" / "current" / "theme"
        om.mkdir(parents=True, exist_ok=True)
        shutil.copy2(t / "palette.css", om / "waybar.css")
        (CONF / "sway").mkdir(parents=True, exist_ok=True)
        shutil.copy2(CONF / "sway" / "themes" / (name + ".conf"),
                     CONF / "sway" / "current-borders.conf")
        shutil.copy2(CONF / "rofi" / "themes" / (name + ".rasi"), CONF / "rofi" / "current.rasi")
        shutil.copy2(CONF / "rofi" / "themes" / (name + "-powermenu.rasi"),
                     CONF / "rofi" / "current-powermenu.rasi")
        shutil.copy2(CONF / "kitty" / "themes" / (name + ".conf"), CONF / "kitty" / "current.conf")
        shutil.copy2(CONF / "dunst" / "themes" / (name + ".dunstrc"), CONF / "dunst" / "dunstrc")
        st_toml = CONF / "starship.toml"
        if st_toml.is_symlink():
            # don't write through e.g. mybash's symlinked starship.toml
            st_toml.unlink()
        shutil.copy2(CONF / "starship" / "themes" / (name + ".toml"), st_toml)
        write_text(CONF / "waybar" / "current-theme-name", name + "\n")
        print("active theme seeded: %s" % name)

    print("done: %d installed, %d failed" % (len(ok), len(failed)))
    return 0 if not failed else 2


if __name__ == "__main__":
    sys.exit(main())
