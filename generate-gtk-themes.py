#!/usr/bin/env python3
"""Generate GTK4/libadwaita themes matching this rice's polybar/rofi/kitty
themes, so clicking the polybar clock (which opens gnome-calendar) - and any
other libadwaita app launched with GTK_THEME set to match - follows the
active desktop theme instead of always showing Catppuccin Mocha.

Built from gtk-theme-template.css (bundled in this repo - a complete,
hand-authored GTK4/libadwaita theme covering libadwaita's full named-color
system plus the specific overrides needed for portal file dialogs and
Chromium/Electron client-side decorations, originally from this machine's
own separate "Cattish-Mocha" theme project) as a structural template: read
its real bytes and swap its 13 Catppuccin Mocha hex values (plus their
rgba()/alpha() occurrences) for each rice theme's own resolved role colors -
the exact same "known-hex string-replace inside real template bytes"
technique already used for this rice's starship prompt theming, applied
here to a GTK4 stylesheet instead of a TOML file.

Reuses generate-vscode-themes.py's own color-resolution logic (parse
polybar's [colors] block, ROLE_CHAINS fallbacks, with_alpha) rather than
reimplementing it a second time - both scripts need the exact same "what is
this theme's red/green/accent/etc" answer, and a theme's role resolution is
already established/tested there.

Scope: GTK4/libadwaita only (gtk-4.0/gtk.css + gtk-dark.css), not GTK2/GTK3/
gnome-shell - the actual complaint this fixes (gnome-calendar, opened by
clicking the polybar clock) is a libadwaita app; GTK2/3 apps in this rice
(pcmanfm, nitrogen, system-config-printer) weren't reported as an issue and
are a separate, larger undertaking if ever needed.

Usage:
    python3 generate-gtk-themes.py

Writes each theme to ~/.themes/Rice-<name>/ as a real named GTK theme
(index.theme + gtk-4.0/{gtk.css,gtk-dark.css}), installed immediately (no
relogin needed) since GTK_THEME is applied per-launch, not session-wide -
see the per-theme polybar date-module click action, which sets
GTK_THEME=Rice-<name> only for that one gnome-calendar invocation.
"""
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

        with open(os.path.join(theme_dir, "index.theme"), "w", encoding="utf-8") as f:
            f.write(INDEX_THEME_TEMPLATE.format(name=name))

        print(f"wrote {theme_dir}")

    print(f"\n{len(THEMES)} GTK4 themes written to {THEMES_ROOT}/Rice-<name>/")


if __name__ == "__main__":
    main()
