#!/usr/bin/env python3
"""Generate VS Code color themes matching this rice's polybar/rofi/kitty themes.

Reads each theme's [colors] block straight out of the already-installed
~/.config/polybar/themes/<name>.ini files (the single source of truth every
other tool - rofi, kitty - already generates from) and writes a matching
VS Code color theme, installed as a small local (unpublished) VS Code
extension under ~/.vscode/extensions/. No marketplace account, packaging,
or network access needed - VS Code loads any extension folder with a valid
package.json it finds there on next startup.

Only the 21 base themes are covered, not their -square counterparts - a
"square" theme differs from its base only in polybar bar-corner/rofi-window
rounding, which has no VS Code equivalent (there's no "editor window corner
radius" concept), so the two would produce byte-identical VS Code themes.

Usage:
    python3 generate-vscode-themes.py

Then in VS Code: Ctrl+Shift+P -> "Preferences: Color Theme" -> pick one.
Re-run any time after editing a polybar theme's [colors] block to regenerate
(this script is idempotent - it always overwrites its own output directory).
"""
import configparser
import json
import os
import re

POLYBAR_THEMES_DIR = os.path.expanduser("~/.config/polybar/themes")
EXTENSION_DIR = os.path.expanduser("~/.vscode/extensions/linux-postinstall-rice-themes")

THEMES = [
    "aline", "archcraft", "brenda", "catppuccin-mocha", "cristina", "cynthia",
    "daniela", "dracula", "emilia", "h4ck3r", "hidrot", "isabel", "jan",
    "karla", "marisol", "nord", "pamela", "silvia", "varinka", "yael", "z0mbi3",
]

# aline is the one light theme in the whole set (confirmed in this rice's own
# README) - every other theme is dark. VS Code's uiTheme base affects default
# contrast assumptions for anything this theme doesn't explicitly override.
LIGHT_THEMES = {"aline"}

# Semantic role -> ordered list of [colors] keys to try, most-specific first.
# Built by reading every theme's real [colors] block (not guessed) - most
# themes share common names (red/green/yellow/blue/purple), a few have their
# own naming (hidrot's red0/red1/blue0/blue1/purple0/purple1/yellow1/aqua1,
# jan/z0mbi3's magenta, cristina/yael's indigo) or omit a role entirely
# (aline/varinka/isabel/h4ck3r have no orange-ish token at all). Falling
# back through the chain, and ultimately to text/subtext, guarantees every
# theme produces a complete, valid result with no missing-key crashes -
# the same fallback-chain approach already used for this rice's kitty ANSI
# palette generation, applied here to VS Code's role set instead.
ROLE_CHAINS = {
    "red":    ["red", "red1", "red0", "red-light"],
    "green":  ["green", "green1", "green0"],
    "yellow": ["yellow", "yellow1"],
    "blue":   ["blue", "blue1", "blue0", "blue-light"],
    "accent": ["mauve", "purple", "purple1", "purple0", "magenta", "indigo", "pink"],
    "cyan":   ["teal", "cyan", "sky", "aqua1"],
    "orange": ["peach", "orange"],
    "pink":   ["pink", "magenta", "lavender"],
}


def resolve(colors, role, default_role="text"):
    for key in ROLE_CHAINS[role]:
        if key in colors:
            return colors[key]
    return colors[default_role]


def parse_theme_colors(ini_path):
    # Several themes (jan, karla, marisol, pamela, varinka, hidrot) set a
    # real alpha channel on base/mantle - meaningful for a polybar bar
    # floating over the desktop, meaningless (and actively bad) for a VS
    # Code editor: an editor.background with alpha renders as an actually
    # see-through *window*, not a themed opaque one, since VS Code has no
    # compositor-overlay context to blend against the way polybar does.
    # Alpha is dropped here at the source so every downstream use (editor
    # background, sidebar, tabs, ...) is solid by construction; the
    # with_alpha() helper below adds controlled transparency back in only
    # for the specific UI affordances (selection/hover highlights) VS Code
    # itself expects to be translucent.
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(ini_path, encoding="utf-8")
    raw = dict(parser["colors"])
    colors = {}
    for key, val in raw.items():
        val = val.strip().strip('"')
        m = re.match(r"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$", val)
        if not m:
            continue
        hexval = m.group(1)
        if len(hexval) == 8:
            # polybar uses AARRGGBB - keep only the RRGGBB, drop the alpha.
            hexval = hexval[2:8]
        colors[key] = f"#{hexval}"
    return colors


def with_alpha(hex_color, alpha_hex):
    base = hex_color[:7]
    return f"{base}{alpha_hex}"


def build_ui_colors(c):
    base = c["base"]
    mantle = c["mantle"]
    surface0 = c.get("surface0", mantle)
    surface1 = c.get("surface1", surface0)
    text = c["text"]
    subtext = c["subtext"]
    accent = resolve(c, "accent")
    red = resolve(c, "red")
    green = resolve(c, "green")
    yellow = resolve(c, "yellow")
    blue = resolve(c, "blue")
    cyan = resolve(c, "cyan")
    orange = resolve(c, "orange")

    return {
        "editor.background": base,
        "editor.foreground": text,
        "editorLineNumber.foreground": subtext,
        "editorLineNumber.activeForeground": text,
        "editorCursor.foreground": accent,
        "editor.selectionBackground": with_alpha(surface1, "80"),
        "editor.inactiveSelectionBackground": with_alpha(surface1, "50"),
        "editor.lineHighlightBackground": surface0,
        "editor.wordHighlightBackground": with_alpha(surface1, "60"),
        "editorIndentGuide.background1": with_alpha(surface0, "80"),
        "editorIndentGuide.activeBackground1": with_alpha(surface1, "90"),
        "editorWhitespace.foreground": surface1,
        "editorBracketMatch.background": with_alpha(surface1, "60"),
        "editorBracketMatch.border": accent,
        "editorError.foreground": red,
        "editorWarning.foreground": yellow,
        "editorInfo.foreground": blue,
        "editorGutter.addedBackground": green,
        "editorGutter.modifiedBackground": yellow,
        "editorGutter.deletedBackground": red,
        "editorRuler.foreground": surface0,

        "activityBar.background": mantle,
        "activityBar.foreground": text,
        "activityBar.inactiveForeground": subtext,
        "activityBarBadge.background": accent,
        "activityBarBadge.foreground": base,

        "sideBar.background": mantle,
        "sideBar.foreground": text,
        "sideBar.border": mantle,
        "sideBarTitle.foreground": text,
        "sideBarSectionHeader.background": mantle,
        "sideBarSectionHeader.foreground": text,

        "statusBar.background": mantle,
        "statusBar.foreground": text,
        "statusBar.border": mantle,
        "statusBar.debuggingBackground": orange,
        "statusBar.debuggingForeground": base,
        "statusBar.noFolderBackground": mantle,

        "titleBar.activeBackground": mantle,
        "titleBar.activeForeground": text,
        "titleBar.inactiveBackground": mantle,
        "titleBar.inactiveForeground": subtext,

        "tab.activeBackground": base,
        "tab.activeForeground": text,
        "tab.inactiveBackground": mantle,
        "tab.inactiveForeground": subtext,
        "tab.border": mantle,
        "tab.activeBorderTop": accent,
        "editorGroupHeader.tabsBackground": mantle,
        "editorGroup.border": surface0,

        "panel.background": mantle,
        "panel.border": surface0,
        "panelTitle.activeForeground": text,
        "panelTitle.inactiveForeground": subtext,

        "terminal.background": base,
        "terminal.foreground": text,
        "terminal.ansiBlack": mantle,
        "terminal.ansiBrightBlack": subtext,
        "terminal.ansiRed": red,
        "terminal.ansiBrightRed": red,
        "terminal.ansiGreen": green,
        "terminal.ansiBrightGreen": green,
        "terminal.ansiYellow": yellow,
        "terminal.ansiBrightYellow": yellow,
        "terminal.ansiBlue": blue,
        "terminal.ansiBrightBlue": blue,
        "terminal.ansiMagenta": accent,
        "terminal.ansiBrightMagenta": accent,
        "terminal.ansiCyan": cyan,
        "terminal.ansiBrightCyan": cyan,
        "terminal.ansiWhite": text,
        "terminal.ansiBrightWhite": text,

        "button.background": accent,
        "button.foreground": base,
        "button.hoverBackground": with_alpha(accent, "cc"),
        "button.secondaryBackground": surface0,
        "button.secondaryForeground": text,

        "input.background": surface0,
        "input.foreground": text,
        "input.border": surface1,
        "input.placeholderForeground": subtext,
        "dropdown.background": surface0,
        "dropdown.foreground": text,
        "dropdown.border": surface1,

        "list.activeSelectionBackground": surface0,
        "list.activeSelectionForeground": text,
        "list.inactiveSelectionBackground": surface0,
        "list.hoverBackground": with_alpha(surface1, "50"),
        "list.highlightForeground": accent,

        "focusBorder": accent,
        "badge.background": accent,
        "badge.foreground": base,
        "progressBar.background": accent,

        "scrollbarSlider.background": with_alpha(surface1, "60"),
        "scrollbarSlider.hoverBackground": with_alpha(surface1, "90"),
        "scrollbarSlider.activeBackground": with_alpha(accent, "90"),

        "editorWidget.background": mantle,
        "editorWidget.foreground": text,
        "editorWidget.border": surface0,
        "editorSuggestWidget.background": mantle,
        "editorSuggestWidget.foreground": text,
        "editorSuggestWidget.selectedBackground": surface0,
        "editorHoverWidget.background": mantle,
        "editorHoverWidget.border": surface0,

        "peekView.border": accent,
        "peekViewEditor.background": mantle,
        "peekViewResult.background": mantle,
        "peekViewTitle.background": surface0,

        "diffEditor.insertedTextBackground": with_alpha(green, "33"),
        "diffEditor.removedTextBackground": with_alpha(red, "33"),

        "gitDecoration.addedResourceForeground": green,
        "gitDecoration.modifiedResourceForeground": yellow,
        "gitDecoration.deletedResourceForeground": red,
        "gitDecoration.untrackedResourceForeground": green,
        "gitDecoration.ignoredResourceForeground": subtext,
        "gitDecoration.conflictingResourceForeground": orange,

        "notificationCenter.border": surface0,
        "notifications.background": mantle,
        "notifications.foreground": text,

        "menu.background": mantle,
        "menu.foreground": text,
        "menu.selectionBackground": surface0,
        "menu.border": surface0,
    }


def build_token_colors(c):
    accent = resolve(c, "accent")
    red = resolve(c, "red")
    green = resolve(c, "green")
    yellow = resolve(c, "yellow")
    blue = resolve(c, "blue")
    cyan = resolve(c, "cyan")
    orange = resolve(c, "orange")
    pink = resolve(c, "pink")
    subtext = c["subtext"]
    text = c["text"]

    def rule(name, scope, foreground, style=None):
        settings = {"foreground": foreground}
        if style:
            settings["fontStyle"] = style
        return {"name": name, "scope": scope, "settings": settings}

    return [
        rule("Comment", ["comment", "punctuation.definition.comment"], subtext, "italic"),
        rule("String", ["string", "string.quoted", "punctuation.definition.string"], green),
        rule("Numeric / boolean / language constant", [
            "constant.numeric", "constant.language", "constant.character",
            "constant.character.escape",
        ], orange),
        rule("Keyword", ["keyword", "keyword.control", "keyword.operator.logical"], accent),
        rule("Storage / modifier", ["storage", "storage.type", "storage.modifier"], accent, "italic"),
        rule("Function / method name", [
            "entity.name.function", "support.function", "meta.function-call",
        ], blue),
        rule("Class / type name", [
            "entity.name.class", "entity.name.type", "support.class", "support.type",
            "entity.other.inherited-class",
        ], yellow),
        rule("Variable", ["variable", "variable.other.readwrite"], text),
        rule("Parameter", ["variable.parameter"], orange, "italic"),
        rule("Constant / enum member", ["variable.other.constant", "variable.other.enummember"], orange),
        rule("Property / attribute", [
            "variable.other.property", "meta.object-literal.key", "support.type.property-name",
        ], cyan),
        rule("Tag (HTML/JSX)", ["entity.name.tag"], accent),
        rule("Tag attribute", ["entity.other.attribute-name"], yellow),
        rule("Operator / punctuation", ["keyword.operator", "punctuation"], subtext),
        rule("Regexp", ["string.regexp"], cyan),
        rule("Markup heading", ["markup.heading"], accent, "bold"),
        rule("Markup bold", ["markup.bold"], text, "bold"),
        rule("Markup italic", ["markup.italic"], text, "italic"),
        rule("Markup link", ["markup.underline.link", "string.other.link"], blue, "underline"),
        rule("Markup quote", ["markup.quote"], subtext, "italic"),
        rule("Diff inserted", ["markup.inserted"], green),
        rule("Diff deleted", ["markup.deleted"], red),
        rule("Invalid / deprecated", ["invalid", "invalid.deprecated"], red, "underline"),
        rule("Preprocessor / decorator", ["meta.preprocessor", "punctuation.definition.decorator", "entity.name.function.decorator"], pink),
    ]


def build_theme(name):
    ini_path = os.path.join(POLYBAR_THEMES_DIR, f"{name}.ini")
    c = parse_theme_colors(ini_path)
    return {
        "name": f"Rice - {name}",
        "type": "light" if name in LIGHT_THEMES else "dark",
        "colors": build_ui_colors(c),
        "tokenColors": build_token_colors(c),
    }


def title_case(name):
    return " ".join(w.capitalize() for w in name.replace("-", " ").split())


def main():
    themes_out_dir = os.path.join(EXTENSION_DIR, "themes")
    os.makedirs(themes_out_dir, exist_ok=True)

    contributed = []
    for name in THEMES:
        ini_path = os.path.join(POLYBAR_THEMES_DIR, f"{name}.ini")
        if not os.path.isfile(ini_path):
            print(f"skip {name}: {ini_path} not found")
            continue
        theme_json = build_theme(name)
        out_path = os.path.join(themes_out_dir, f"{name}-color-theme.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(theme_json, f, indent=2)
            f.write("\n")
        contributed.append({
            "label": title_case(name),
            "uiTheme": "vs-light" if name in LIGHT_THEMES else "vs-dark",
            "path": f"./themes/{name}-color-theme.json",
        })
        print(f"wrote {out_path}")

    package_json = {
        "name": "linux-postinstall-rice-themes",
        "displayName": "Linux Postinstall Rice Themes",
        "description": "VS Code themes matching this rice's polybar/rofi/kitty desktop themes",
        "version": "1.0.0",
        "publisher": "local",
        "engines": {"vscode": "^1.60.0"},
        "categories": ["Themes"],
        "contributes": {"themes": contributed},
    }
    package_path = os.path.join(EXTENSION_DIR, "package.json")
    with open(package_path, "w", encoding="utf-8") as f:
        json.dump(package_json, f, indent=2)
        f.write("\n")
    print(f"wrote {package_path}")
    print(f"\n{len(contributed)} themes installed to {EXTENSION_DIR}")
    print("Restart VS Code, then Ctrl+Shift+P -> \"Preferences: Color Theme\" to pick one.")


if __name__ == "__main__":
    main()
