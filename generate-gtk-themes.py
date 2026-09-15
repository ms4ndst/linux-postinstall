#!/usr/bin/env python3
"""Generate GTK4/libadwaita AND GTK3 themes matching this rice's polybar/
rofi/kitty themes, so clicking the polybar clock (which opens
gnome-calendar, a libadwaita app) or the polybar network module (which
opens nm-connection-editor, a plain GTK3 app) - and any other GTK4/GTK3 app
launched with GTK_THEME set to match, or with the theme set globally via
gsettings - follows the active desktop theme instead of always showing
Catppuccin Mocha.

Built from gtk-theme-template.css and gtk3-theme-template.css (both
bundled in this repo - complete, hand-authored GTK4/libadwaita and GTK3
themes, originally from this machine's own separate "Cattish-Mocha" theme
project) as structural templates: read their real bytes and swap known
Catppuccin Mocha color occurrences (hex literals, and their rgba()/alpha()/
shade() equivalents) for each rice theme's own resolved role colors - the
exact same "known-hex string-replace inside real template bytes" technique
already used for this rice's starship prompt theming, applied here to GTK
stylesheets instead of a TOML file. The GTK4 template's 13 known hex values
are still substituted via an explicit hardcoded role map (MOCHA_ROLE_MAP);
the much larger GTK3 template (156 unique hex values, many of them
pre-baked tint/shade variants rather than the plain named colors GTK4 uses)
is instead handled algorithmically - see GTK3_CLASSIFICATION below.

Reuses generate-vscode-themes.py's own color-resolution logic (parse
polybar's [colors] block, ROLE_CHAINS fallbacks, with_alpha) rather than
reimplementing it a second time - both scripts need the exact same "what is
this theme's red/green/accent/etc" answer, and a theme's role resolution is
already established/tested there.

Scope: GTK4/libadwaita (gtk-4.0/gtk.css + gtk-dark.css) AND GTK3
(gtk-3.0/gtk.css + gtk-dark.css) - covers both the libadwaita apps (e.g.
gnome-calendar, opened by clicking the polybar clock) and plain GTK3 apps
in this rice (e.g. nm-connection-editor, opened by clicking the polybar
network module) that don't use libadwaita at all. GTK2 and gnome-shell
remain out of scope - not reported as an issue and a separate, larger
undertaking if ever needed.

Usage:
    python3 generate-gtk-themes.py

Writes each theme to ~/.themes/Rice-<name>/ as a real named GTK theme
(index.theme + gtk-4.0/{gtk.css,gtk-dark.css} + gtk-3.0/{gtk.css,
gtk-dark.css}). The GTK4 half is applied per-launch via GTK_THEME (see the
per-theme polybar date-module click action, which sets
GTK_THEME=Rice-<name> only for that one gnome-calendar invocation) with no
relogin needed; the GTK3 half has no per-invocation env var equivalent, so
it's picked up by setting the theme globally (gsettings + gtk-3.0/
gtk-4.0 settings.ini) whenever polybar-theme.sh switches rices - see that
script's GTK theme step.

Only the 21 base rice names are covered, not their -square counterparts,
matching this script's own existing GTK4 behavior (never handled -square
either): a "square" theme differs from its base only in polybar/rofi
corner-rounding, which has no GTK3/GTK4 theme equivalent, so the two would
produce byte-identical output. Callers (like polybar-theme.sh) strip a
"-square" suffix before looking up the GTK theme name.
"""
import colorsys
import importlib.util
import os
import re

# generate-vscode-themes.py has a hyphen in its filename, so it can't be
# imported with a plain `import` statement - load it by file path instead.
_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "generate_vscode_themes", os.path.join(_here, "generate-vscode-themes.py")
)
_vscode_gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_vscode_gen)

THEMES = _vscode_gen.THEMES
parse_theme_colors = _vscode_gen.parse_theme_colors
resolve = _vscode_gen.resolve
POLYBAR_THEMES_DIR = _vscode_gen.POLYBAR_THEMES_DIR

TEMPLATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gtk-theme-template.css")
GTK3_TEMPLATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gtk3-theme-template.css")
THEMES_ROOT = os.path.expanduser("~/.themes")

# The 13 Catppuccin Mocha hex values the template actually uses (verified by
# enumerating every #rrggbb occurrence in the real file - see conversation),
# mapped to the semantic role each one plays. Every occurrence of a given
# hex - in an @define-color, a bare "background-color: #hex", or inside a
# GTK CSS alpha(#hex, N) call - gets the same role substitution, since GTK
# CSS's alpha() takes a literal color argument, not a variable reference.
MOCHA_ROLE_MAP = {
    "#cdd6f4": "text",
    "#11111b": "crust",     # darkest surface - this rice's themes only have
                             # base+mantle (no separate crust step), so this
                             # resolves to "mantle" below, same as the VS
                             # Code generator's own sidebar/activitybar bg.
    "#1e1e2e": "base",
    "#cba6f7": "accent",    # accent_bg_color / theme_selected_bg_color
    "#585b70": "border",    # no dedicated "surface2" role exists in this
                             # rice's palettes (VS Code generator only goes
                             # to surface1) - subtext is the closest already-
                             # resolved mid-tone standing in for a border.
    "#313244": "surface0",
    "#f9e2af": "yellow",
    "#f38ba8": "red",
    "#a6e3a1": "green",
    "#89dceb": "cyan",      # accent_color / link_color - Cattish-Mocha
                             # deliberately uses a DIFFERENT hue than
                             # accent_bg_color for text/link/focus-ring
                             # accents vs button/selection surfaces; this
                             # rice's own "accent" (mauve-ish) vs "cyan"
                             # role split mirrors that same two-tone design.
    "#b4befe": "pink",      # visited_link_color - pink role chain already
                             # falls back through lavender.
    "#fab387": "orange",    # destructive-action:hover - orange role chain
                             # already falls back through peach.
    "#acd9a8": "green",     # titlebutton:active - a slightly different
                             # green shade in the source than success_color;
                             # simplified to reuse the same resolved green
                             # rather than inventing a second green tone.
}

# rgba(R, G, B, alpha) triples in the template, and which role's RGB the
# R/G/B should be recomputed from for each theme (alpha stays unchanged -
# it's a translucency amount, not a color).
MOCHA_RGBA_ROLE_MAP = {
    (17, 17, 27): "crust",     # = #11111b
    (205, 214, 244): "text",   # = #cdd6f4
}

INDEX_THEME_TEMPLATE = """[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Rice-{name}
Comment=Auto-generated GTK4/libadwaita theme matching this rice's {name} desktop theme
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Rice-{name}
MetacityTheme=Rice-{name}
IconTheme=Adwaita
CursorTheme=Adwaita
ButtonLayout=close,minimize,maximize:menu
"""


def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))


def resolve_roles(colors):
    roles = {
        "text": colors["text"],
        "crust": colors["mantle"],
        "base": colors["base"],
        "accent": resolve(colors, "accent"),
        "border": colors["subtext"],
        "surface0": colors.get("surface0", colors["mantle"]),
        "yellow": resolve(colors, "yellow"),
        "red": resolve(colors, "red"),
        "green": resolve(colors, "green"),
        "cyan": resolve(colors, "cyan"),
        "pink": resolve(colors, "pink"),
        "orange": resolve(colors, "orange"),
    }
    return roles


def build_gtk_css(template_bytes, roles):
    css = template_bytes

    # 1. Plain hex substitutions - covers @define-color, bare
    #    "background-color: #hex", "border: ... #hex", and alpha(#hex, N)
    #    calls, since they all spell the color the same way.
    for mocha_hex, role in MOCHA_ROLE_MAP.items():
        css = css.replace(mocha_hex, roles[role])

    # 2. rgba(R, G, B, alpha) decimal triples - not caught by the hex
    #    substitution above since they're written as decimal, not #hex.
    for (r, g, b), role in MOCHA_RGBA_ROLE_MAP.items():
        new_r, new_g, new_b = hex_to_rgb(roles[role])
        css = css.replace(f"rgba({r}, {g}, {b}", f"rgba({new_r}, {new_g}, {new_b}")

    return css


# ---------------------------------------------------------------------------
# GTK3
#
# The GTK3 template (gtk3-theme-template.css, copied byte-for-byte from this
# machine's own Cattish-Mocha/gtk-3.0/gtk.css) is a much bigger and messier
# surface than the GTK4 one: 156 unique hex colors, only ~10 of which are
# plain Catppuccin Mocha named colors written directly (@define-color
# theme_fg_color #cdd6f4; etc, plus a handful of exact-canonical colors used
# straight in the CSS body like #89dceb sky). The other ~146 are pre-baked
# tint/shade variants (hover/pressed states, gradient stops, shadow ramps)
# that some earlier Sass-like build pipeline flattened to literal hex - and
# a big block of GNOME/Nautilus-style reference swatch colors
# (STRAWBERRY_100, GRAPE_500, SILVER_900, ...) used by things like file-tag
# color pickers, which are a fixed, theme-independent palette upstream (the
# same swatch grid shows up unchanged across real GTK themes) and are
# deliberately left untouched here rather than force-mapped onto Catppuccin.
#
# Rather than hardcode a 146-entry lookup table (which would only be
# correct for Mocha and would need hand-redoing for every future template
# edit), every real/in-use color in the template is classified
# algorithmically at import time: find its closest Catppuccin-Mocha
# canonical role by hue (falling back to a lightness-only match among the
# neutral ramp for near-gray colors, where hue is numerically unstable and
# would otherwise spuriously snap to an unrelated saturated role), then
# store its HLS delta from that role. To retint for another rice, resolve
# that same role against the rice's own (much smaller) palette, apply the
# stored delta in HLS space, and convert back to hex.
CANONICAL_MOCHA = {
    "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7", "mauve": "#cba6f7",
    "red": "#f38ba8", "maroon": "#eba0ac", "peach": "#fab387", "yellow": "#f9e2af",
    "green": "#a6e3a1", "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
    "blue": "#89b4fa", "lavender": "#b4befe", "text": "#cdd6f4", "subtext1": "#bac2de",
    "subtext0": "#a6adc8", "overlay2": "#9399b2", "overlay1": "#7f849c", "overlay0": "#6c7086",
    "surface2": "#585b70", "surface1": "#45475a", "surface0": "#313244", "base": "#1e1e2e",
    "mantle": "#181825", "crust": "#11111b",
}

# The neutral ramp - the only roles a near-gray (low-saturation) derived
# color is allowed to match against. Without this restriction, a
# low-saturation color can end up numerically "closest" to a saturated
# role (e.g. green) purely because that role's lightness happens to line
# up, producing a nonsensical result (verified while building this: a
# muted blue-gray #babcc8 was initially misclassified as "green" this way).
NEUTRAL_ROLES = {
    "text", "subtext1", "subtext0", "overlay2", "overlay1", "overlay0",
    "surface2", "surface1", "surface0", "base", "mantle", "crust",
}

REVERSE_CANONICAL_MOCHA = {v: k for k, v in CANONICAL_MOCHA.items()}


def hex_to_hls(hex_color):
    r, g, b = (c / 255.0 for c in hex_to_rgb(hex_color))
    return colorsys.rgb_to_hls(r, g, b)


def hls_to_hex(h, l, s):
    h = h % 1.0
    l = min(1.0, max(0.0, l))
    s = min(1.0, max(0.0, s))
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return "#{:02x}{:02x}{:02x}".format(
        round(min(1.0, max(0.0, r)) * 255),
        round(min(1.0, max(0.0, g)) * 255),
        round(min(1.0, max(0.0, b)) * 255),
    )


def hue_dist(h1, h2):
    d = abs(h1 - h2) % 1.0
    return min(d, 1.0 - d)


_CANONICAL_HLS = {role: hex_to_hls(hexval) for role, hexval in CANONICAL_MOCHA.items()}


def classify_color(hex_color):
    """Return (role, delta_h, delta_l, delta_s) for a template hex color -
    which of the 26 canonical Mocha roles it's closest to, and its HLS
    offset from that role's canonical value. An exact match against one of
    the 26 canonical hexes (the plain named colors, plus body colors like
    #89dceb sky that are used directly with no dedicated variable) always
    wins outright with a zero delta, rather than letting the nearest-role
    search find it "approximately" - it's not approximate, it IS that role.
    """
    hex_color = hex_color.lower()
    if hex_color in REVERSE_CANONICAL_MOCHA:
        return REVERSE_CANONICAL_MOCHA[hex_color], 0.0, 0.0, 0.0

    h, l, s = hex_to_hls(hex_color)
    achromatic = s < 0.15
    best = None
    for role, (ch, cl, cs) in _CANONICAL_HLS.items():
        if achromatic:
            if role not in NEUTRAL_ROLES:
                continue
            dist = abs(l - cl)
        else:
            dist = hue_dist(h, ch) * 4.0 + abs(l - cl) + abs(s - cs) * 0.8
        if best is None or dist < best[0]:
            best = (dist, role, ch, cl, cs)
    _, role, ch, cl, cs = best
    dh = h - ch
    if dh > 0.5:
        dh -= 1.0
    elif dh < -0.5:
        dh += 1.0
    return role, dh, l - cl, s - cs


def find_gtk3_body_start(template_text):
    for i, line in enumerate(template_text.split("\n")):
        if line.strip().startswith("* {"):
            return i
    return 0


def collect_gtk3_known_colors(template_text):
    """Every real, in-use color in the GTK3 template, as lowercase #hex
    strings - the ones that should retint per-rice. Excludes the
    GNOME/Nautilus-style reference swatch grid (STRAWBERRY_500 etc, see
    module docstring) but includes everything else: header named colors,
    every hex literal in the CSS body, and hex-equivalents of decimal
    rgba()/rgb() triples (some colors - notably wm_highlight/
    wm_borders_edge-style overrides - are only ever spelled out in decimal,
    never as a literal #hex, so scanning for #hex alone would silently
    miss them).
    """
    lines = template_text.split("\n")
    body_start = find_gtk3_body_start(template_text)
    header_text = "\n".join(lines[:body_start])
    body_text = "\n".join(lines[body_start:])

    known = set()
    for m in re.finditer(r"@define-color\s+(\S+)\s+([^;]+);", header_text):
        name, value = m.group(1), m.group(2)
        if re.match(r"^[A-Z][A-Z0-9]*_[0-9]+$", name):
            continue  # reference swatch grid entry - leave untouched
        known.update(h.lower() for h in re.findall(r"#[0-9a-fA-F]{6}", value))

    known.update(h.lower() for h in re.findall(r"#[0-9a-fA-F]{6}\b", body_text))

    for r, g, b in re.findall(r"rgba?\(\s*(\d+),\s*(\d+),\s*(\d+)", template_text):
        known.add("#{:02x}{:02x}{:02x}".format(int(r), int(g), int(b)))

    return known


def resolve_gtk3_roles(colors):
    """Resolve all 26 Catppuccin-Mocha canonical roles against one rice's
    own (much smaller, ~10-15 color) palette. Several roles collapse onto
    the same resolved color for most rices - e.g. teal/sky/sapphire all
    fall back to whatever single "cyan-ish" key a rice defines, and
    overlay0/overlay1/overlay2/subtext0/subtext1 all fall back to a rice's
    one "subtext" key - the same simplification already used elsewhere in
    this script/repo (e.g. crust -> mantle) for roles finer-grained than
    what a given rice's [colors] block actually distinguishes. Distinct
    hex output across those collapsed roles still comes from each one's
    own stored HLS delta.
    """
    base = colors["base"]
    mantle = colors.get("mantle", base)
    surface0 = colors.get("surface0", mantle)
    surface1 = colors.get("surface1", surface0)
    text = colors["text"]
    subtext = colors.get("subtext", text)
    accent = resolve(colors, "accent")
    red = resolve(colors, "red")
    green = resolve(colors, "green")
    yellow = resolve(colors, "yellow")
    blue = resolve(colors, "blue")
    cyan = resolve(colors, "cyan")
    orange = resolve(colors, "orange")
    pink = resolve(colors, "pink")

    return {
        "rosewater": red,
        "flamingo": red,
        "pink": pink,
        "mauve": accent,
        "red": red,
        "maroon": red,
        "peach": orange,
        "yellow": yellow,
        "green": green,
        "teal": colors.get("teal", cyan),
        "sky": colors.get("sky", cyan),
        "sapphire": colors.get("sapphire", cyan),
        "blue": blue,
        "lavender": colors.get("lavender", pink),
        "text": text,
        "subtext1": subtext,
        "subtext0": subtext,
        "overlay2": subtext,
        "overlay1": subtext,
        "overlay0": subtext,
        "surface2": surface1,
        "surface1": surface1,
        "surface0": surface0,
        "base": base,
        "mantle": mantle,
        "crust": mantle,
    }


_HEX_LITERAL_RE = re.compile(r"#[0-9a-fA-F]{6}\b")
_RGBA_TRIPLE_RE = re.compile(r"(rgba?\(\s*)(\d+)(\s*,\s*)(\d+)(\s*,\s*)(\d+)")


def build_gtk3_css(template_text, classification, colors):
    resolved = resolve_gtk3_roles(colors)

    new_hex_for = {}
    for hex_val, (role, dh, dl, ds) in classification.items():
        ph, pl, ps = hex_to_hls(resolved[role])
        new_hex_for[hex_val] = hls_to_hex(ph + dh, pl + dl, ps + ds)

    # Single pass over the original text for each substitution kind - a
    # regex callback looks each match up in new_hex_for and only ever reads
    # from the ORIGINAL bytes being scanned, so there's no risk of one
    # replacement's output being re-matched/re-replaced by a later rule
    # (the classic hazard with sequential str.replace() calls).
    def hex_sub(m):
        return new_hex_for.get(m.group(0).lower(), m.group(0))

    css = _HEX_LITERAL_RE.sub(hex_sub, template_text)

    def rgba_sub(m):
        r, g, b = int(m.group(2)), int(m.group(4)), int(m.group(6))
        old_hex = "#{:02x}{:02x}{:02x}".format(r, g, b)
        new_hex = new_hex_for.get(old_hex)
        if new_hex is None:
            return m.group(0)
        nr, ng, nb = hex_to_rgb(new_hex)
        return f"{m.group(1)}{nr}{m.group(3)}{ng}{m.group(5)}{nb}"

    css = _RGBA_TRIPLE_RE.sub(rgba_sub, css)
    return css


def main():
    with open(TEMPLATE_PATH, encoding="utf-8") as f:
        template = f.read()

    # Sanity check: every hex this script knows how to substitute should
    # account for every #rrggbb occurrence in the template - if a future
    # edit to Cattish-Mocha/gtk-4.0/gtk.css introduces a new color, this
    # catches it instead of silently leaving Catppuccin Mocha hardcoded in
    # the generated output.
    all_hexes = set(re.findall(r"#[0-9a-fA-F]{6}", template))
    unmapped = all_hexes - set(MOCHA_ROLE_MAP)
    if unmapped:
        print(f"WARNING: template has unmapped hex colors: {unmapped}")

    with open(GTK3_TEMPLATE_PATH, encoding="utf-8") as f:
        gtk3_template = f.read()
    gtk3_known_colors = collect_gtk3_known_colors(gtk3_template)
    gtk3_classification = {hexval: classify_color(hexval) for hexval in gtk3_known_colors}

    for name in THEMES:
        ini_path = os.path.join(POLYBAR_THEMES_DIR, f"{name}.ini")
        if not os.path.isfile(ini_path):
            print(f"skip {name}: {ini_path} not found")
            continue
        colors = parse_theme_colors(ini_path)
        roles = resolve_roles(colors)
        css = build_gtk_css(template, roles)

        theme_dir = os.path.join(THEMES_ROOT, f"Rice-{name}")
        gtk4_dir = os.path.join(theme_dir, "gtk-4.0")
        os.makedirs(gtk4_dir, exist_ok=True)

        with open(os.path.join(gtk4_dir, "gtk.css"), "w", encoding="utf-8") as f:
            f.write(css)
        # Dark-only per theme (matches Cattish-Mocha's own gtk.css ==
        # gtk-dark.css convention) - GTK_THEME forces a specific named
        # theme regardless of prefer-dark-scheme, so both files rendering
        # identically is correct, not a missing light variant.
        with open(os.path.join(gtk4_dir, "gtk-dark.css"), "w", encoding="utf-8") as f:
            f.write(css)

        gtk3_css = build_gtk3_css(gtk3_template, gtk3_classification, colors)
        gtk3_dir = os.path.join(theme_dir, "gtk-3.0")
        os.makedirs(gtk3_dir, exist_ok=True)
        with open(os.path.join(gtk3_dir, "gtk.css"), "w", encoding="utf-8") as f:
            f.write(gtk3_css)
        # Dark-only, matching Cattish-Mocha/gtk-3.0's own gtk.css ==
        # gtk-dark.css convention (same reasoning as the GTK4 pair above).
        with open(os.path.join(gtk3_dir, "gtk-dark.css"), "w", encoding="utf-8") as f:
            f.write(gtk3_css)

        with open(os.path.join(theme_dir, "index.theme"), "w", encoding="utf-8") as f:
            f.write(INDEX_THEME_TEMPLATE.format(name=name))

        print(f"wrote {theme_dir}")

    print(f"\n{len(THEMES)} GTK4+GTK3 themes written to {THEMES_ROOT}/Rice-<name>/")


if __name__ == "__main__":
    main()
