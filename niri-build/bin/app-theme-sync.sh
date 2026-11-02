#!/usr/bin/env bash
# Brings the terminal apps that draw their OWN colors in line with the
# active desktop theme - kitty's colors alone don't reach them. Run by
# waybar-theme.sh after every theme switch (and once by the setup script),
# reading the theme's kitty palette and niri focus-ring color that
# waybar-theme.sh has just put in place.
#   - cliamp (Mod+m): a custom theme, ~/.config/cliamp/themes/rice.toml
#     (cliamp's own custom-theme format; no bg, so the themed kitty
#     background shows through), selected in its config and applied live
#     to a running player via `cliamp theme rice`, which re-reads the file
#   - Mistral Vibe (Mod+a): Textual's ansi-dark/ansi-light theme, which
#     draws with the terminal's 16 colors - kitty's live recolor then
#     reaches it too, even mid-session. light vs dark from the background.
#   - Strata (Mod+E file manager): a custom theme in its own TOML format
#     (~/.config/strata/themes/rice.toml), live-reloaded by the app.
KITTY_CURRENT="$HOME/.config/kitty/current.conf"
BORDERS_CURRENT="$HOME/.config/niri/themes/current.kdl"
[ -f "$KITTY_CURRENT" ] || exit 0
kc() { awk -v k="$1" '$1 == k { print $2; exit }' "$KITTY_CURRENT"; }
hex() { [[ "$1" =~ ^#[0-9A-Fa-f]{6}$ ]] && printf '%s' "$1" || printf '%s' "$2"; }

# set_toml_key <file> <key> <value>: a top-level `key = "value"`, replaced
# if present, else put first (before any [section], where top-level keys go)
set_toml_key() {
  local f="$1" k="$2" v="$3"
  mkdir -p "$(dirname "$f")"
  if [ ! -f "$f" ]; then
    printf '%s = "%s"\n' "$k" "$v" > "$f"
  elif grep -q "^$k[[:space:]]*=" "$f"; then
    sed -i "s|^$k[[:space:]]*=.*|$k = \"$v\"|" "$f"
  else
    sed -i "1i $k = \"$v\"" "$f"
  fi
}

fg="$(hex "$(kc foreground)" '#cdd6f4')"
accent="$(hex "$(awk '/active-color/{ gsub(/[",]/,"",$2); print $2; exit }' "$BORDERS_CURRENT" 2>/dev/null)" "$(hex "$(kc color5)" "$fg")")"

if command -v cliamp >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/cliamp/themes"
  cat > "$HOME/.config/cliamp/themes/rice.toml" <<TOML
# Written by ~/.local/bin/app-theme-sync.sh from the active desktop theme
accent = "$accent"
bright_fg = "$fg"
fg = "$(hex "$(kc color8)" "$fg")"
green = "$(hex "$(kc color2)" '#a6e3a1')"
yellow = "$(hex "$(kc color3)" '#f9e2af')"
red = "$(hex "$(kc color1)" '#f38ba8')"
TOML
  set_toml_key "$HOME/.config/cliamp/config.toml" theme rice
  pgrep -x cliamp >/dev/null && cliamp theme rice >/dev/null 2>&1
fi

if command -v strata >/dev/null 2>&1; then
  # Strata ignores desktop GTK themes by design (it pins GTK to its own
  # built-in theme and drops GTK_THEME), so it gets themed through its
  # own custom-theme TOML instead: nine semantic tokens written from
  # the live kitty/border palette, selected once in settings.toml, and
  # live-reloaded whenever this file changes (matugen-style - a running
  # Strata re-tints every open window without a restart). Token mapping:
  # the kitty palette carries base/surface1/surface2 as background/
  # color0/color8, so surface is stepped between them and border blends
  # background with surface2; dim text is subtext (color15), danger red.
  bg_s="$(hex "$(kc background)" '#1e1e2e')"
  sur1_s="$(hex "$(kc color0)" '#4b4e55')"
  sur2_s="$(hex "$(kc color8)" '#585b70')"
  mixhex() {
    local t="${3:-50}"
    local ar=$((16#${1:1:2})) ag=$((16#${1:3:2})) ab=$((16#${1:5:2}))
    local br=$((16#${2:1:2})) bgx=$((16#${2:3:2})) bb=$((16#${2:5:2}))
    printf '#%02x%02x%02x' \
      $(( (ar * (100 - t) + br * t) / 100 )) \
      $(( (ag * (100 - t) + bgx * t) / 100 )) \
      $(( (ab * (100 - t) + bb * t) / 100 ))
  }
  mkdir -p "$HOME/.config/strata/themes"
  cat > "$HOME/.config/strata/themes/rice.toml" <<TOML
# Written by ~/.local/bin/app-theme-sync.sh from the active desktop theme
name = "Rice"
background = "$bg_s"
surface = "$(mixhex "$bg_s" "$sur1_s" 50)"
text = "$fg"
accent = "$accent"
danger = "$(hex "$(kc color1)" '#f38ba8')"
muted = "$sur1_s"
highlight = "$sur2_s"
border = "$(mixhex "$bg_s" "$sur2_s" 60)"
dim_text = "$(hex "$(kc color15)" "$fg")"
TOML
  # Strata's settings.toml requires BOTH mode and theme; a bare theme
  # key makes the file unparseable, and Strata then disables saving
  # for the whole session to preserve it (verified against the
  # upstream Preferences schema).
  set_toml_key "$HOME/.config/strata/settings.toml" mode theme
  set_toml_key "$HOME/.config/strata/settings.toml" theme rice
fi

if command -v ttt >/dev/null 2>&1; then
  # ttt (terminal IDE, run as `ttt` in any kitty window) is themed by a
  # rice-branded theme plugin: a rebranded, re-pointed copy of ttt's own
  # bundled "omarchy-theme" plugin - the same proven, contrast-safe
  # palette->theme converter - reading the rice palette written below and
  # emitting ~/.config/ttt/themes/rice.json. The stock omarchy-theme plugin is
  # disabled so no Omarchy naming reaches ttt's UI.
  tcfg="$HOME/.config/ttt"
  mkdir -p "$tcfg/themes" "$tcfg/plugins"
  # The rice palette as TOML for the plugin. background is a deepened copy of
  # kitty's: a ttt cell background exactly equal to kitty's own (translucent)
  # default background inherits kitty's background_opacity and shows the
  # wallpaper through the editor - the Strata problem - so deepen it ~18% to
  # render opaque while still reading as the theme's dark base.
  ttt_darken() { printf '#%02x%02x%02x' $(( 16#${1:1:2}*82/100 )) $(( 16#${1:3:2}*82/100 )) $(( 16#${1:5:2}*82/100 )); }
  {
    printf 'background = "%s"\n' "$(ttt_darken "$(hex "$(kc background)" '#1e1e2e')")"
    printf 'foreground = "%s"\n' "$fg"
    printf 'accent = "%s"\n' "$accent"
    for __i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      printf 'color%s = "%s"\n' "$__i" "$(hex "$(kc color$__i)" '#585b70')"
    done
  } > "$tcfg/rice-palette.toml"
  # Derive the rice-theme plugin once from ttt's installed omarchy-theme plugin
  # (ttt fetches that on first launch). Same converter, re-pointed + rebranded.
  if [ -f "$tcfg/plugins/omarchy-theme/init.lua" ] && [ ! -f "$tcfg/plugins/rice-theme/init.lua" ]; then
    mkdir -p "$tcfg/plugins/rice-theme"
    sed -e 's#~/.local/state/omarchy/current/theme/colors.toml#~/.config/ttt/rice-palette.toml#' \
        -e 's#~/.local/state/omarchy/current/theme/vscode-theme.json#~/.config/ttt/rice-tokens.json#' \
        -e 's#{config}/themes/omarchy.json#{config}/themes/rice.json#g' \
        -e 's/~= "omarchy"/~= "rice"/' \
        -e 's/Omarchy theme: /Rice theme: /g' \
        -e 's/Omarchy palette requires/Rice palette requires/' \
        "$tcfg/plugins/omarchy-theme/init.lua" > "$tcfg/plugins/rice-theme/init.lua"
    cat > "$tcfg/plugins/rice-theme/plugin.ttt.json" <<'PJSON'
{
  "name": "rice-theme",
  "displayName": "Rice Theme",
  "description": "Keep a TTT theme in sync with the active desktop rice palette.",
  "version": "0.1.0",
  "author": "linux-postinstall",
  "entry": "init.lua",
  "api": 1,
  "permissions": {
    "fs.read": ["~/.config/ttt"],
    "fs.write": ["{config}/themes"],
    "settings": true,
    "settings_keys": ["theme"],
    "commands": true
  }
}
PJSON
  fi
  # Disable the Omarchy plugin and register rice-theme (only once ttt has
  # created its plugin registry on first launch).
  if [ -f "$tcfg/plugins.ttt.json" ]; then
    python3 - "$tcfg/plugins.ttt.json" "$tcfg/plugins/rice-theme/init.lua" <<'PY' 2>/dev/null || true
import json, os, sys
reg_path, rice_init = sys.argv[1], sys.argv[2]
try:
    reg = json.load(open(reg_path))
    if not isinstance(reg, list):
        raise ValueError
except Exception:
    sys.exit(0)
for r in reg:
    if isinstance(r, dict) and r.get("name") == "omarchy-theme":
        r["enabled"] = False
if os.path.exists(rice_init) and not any(
        isinstance(r, dict) and r.get("name") == "rice-theme" for r in reg):
    reg.append({
        "name": "rice-theme", "displayName": "Rice Theme", "repo": "local",
        "path": "rice-theme", "version": "0.1.0", "enabled": True,
        "permissions": {"commands": True, "fs.read": ["~/.config/ttt"],
                        "fs.write": ["{config}/themes"], "network.http": False,
                        "settings": True, "settings_keys": ["theme"]},
        "grantsVersion": 2})
json.dump(reg, open(reg_path, "w"), indent=2)
open(reg_path, "a").write("\n")
PY
  fi
  # A hand-written fallback theme so ttt is themed even before the plugin runs
  # (or if its omarchy-theme source was never fetched); the plugin overwrites
  # themes/rice.json with a richer, contrast-safe version once active.
  if [ ! -f "$tcfg/themes/rice.json" ]; then
    ttt_bg="$(ttt_darken "$(hex "$(kc background)" '#1e1e2e')")"
    ttt_mut="$(hex "$(kc color8)" '#585b70')"
    cat > "$tcfg/themes/rice.json" <<JSON
{
  "default":   { "fg": "$fg", "bg": "$ttt_bg" },
  "muted":     { "fg": "$ttt_mut" },
  "statusBar": { "fg": "$accent" },
  "tabs":      { "active": { "fg": "$accent", "bold": true } },
  "editor":    { "lineNumber": { "fg": "$ttt_mut" } },
  "syntax": {
    "comment":  { "fg": "$ttt_mut" },
    "string":   { "fg": "$(hex "$(kc color2)" '#a6e3a1')" },
    "keyword":  { "fg": "$(hex "$(kc color5)" '#cba6f7')", "bold": true },
    "number":   { "fg": "$(hex "$(kc color1)" '#f38ba8')" },
    "function": { "fg": "$(hex "$(kc color4)" '#89b4fa')" }
  }
}
JSON
  fi
  # Select the rice theme (ttt merges a partial settings.json over its defaults).
  ttt_settings="$tcfg/settings.json"
  python3 - "$ttt_settings" <<'PY' 2>/dev/null || { [ -f "$ttt_settings" ] || printf '{\n  "theme": "rice"\n}\n' > "$ttt_settings"; }
import json, os, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}
d["theme"] = "rice"
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
fi

if command -v vibe >/dev/null 2>&1 || [ -d "$HOME/.vibe" ]; then
  bg="$(hex "$(kc background)" '#1e1e2e')"
  r=$((16#${bg:1:2})); g=$((16#${bg:3:2})); b=$((16#${bg:5:2}))
  if [ $(( (r * 299 + g * 587 + b * 114) / 1000 )) -gt 140 ]; then
    vibe_theme=ansi-light
  else
    vibe_theme=ansi-dark
  fi
  set_toml_key "$HOME/.vibe/config.toml" theme "$vibe_theme"
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
systemctl --user try-restart xdg-desktop-portal-manual.service   xdg-desktop-portal-gtk-manual.service xdg-desktop-portal-wlr-manual.service 2>/dev/null || true

# libadwaita apps (gnome-calendar and every GNOME 47+ app) deliberately
# block theme CSS - the only levers GNOME allows are the color-scheme
# (already prefer-dark via gsettings) and the PRESET accent colors. Map
# the active theme's accent hue to the closest preset so highlights,
# selected-day and buttons follow the rice's hue as closely as GNOME
# permits.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$BORDERS_CURRENT" <<'ACCENTEOF'
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
