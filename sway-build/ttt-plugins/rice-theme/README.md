# rice-theme (ttt plugin)

Keeps a ttt theme (`~/.config/ttt/themes/rice.json`, selected as `theme: "rice"`)
in sync with the active desktop rice palette, with **no Omarchy branding**.

It is a rebranded, re-pointed copy of ttt's own bundled `omarchy-theme` plugin -
the same proven, contrast-safe palette->theme converter. The Sway rice's
`~/.local/bin/app-theme-sync.sh` derives it at runtime from the user's installed
`~/.config/ttt/plugins/omarchy-theme/init.lua` (ttt fetches that on first launch)
with these substitutions, then ships `plugin.ttt.json` (this directory) as the
manifest and disables the stock `omarchy-theme` plugin in `plugins.ttt.json`:

    ~/.local/state/omarchy/current/theme/colors.toml      -> ~/.config/ttt/rice-palette.toml
    ~/.local/state/omarchy/current/theme/vscode-theme.json -> ~/.config/ttt/rice-tokens.json
    {config}/themes/omarchy.json                          -> {config}/themes/rice.json
    settings.get("theme") ~= "omarchy"                    -> ~= "rice"
    "Omarchy theme: ..."  (log + notify)                  -> "Rice theme: ..."
    "Omarchy palette requires ..."                        -> "Rice palette requires ..."

`app-theme-sync.sh` writes `~/.config/ttt/rice-palette.toml` from the live kitty
palette on every theme switch. The palette's `background` is a deepened copy of
kitty's background: a ttt cell background exactly equal to kitty's own
(translucent) default background would inherit kitty's `background_opacity` and
show the wallpaper through the editor; a slightly darker shade renders opaque.
A hand-written partial `rice.json` is seeded as a fallback for the moment before
the plugin first runs.
