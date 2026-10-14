# sway-build — how `sway-setup-cattpuccin.sh` is generated

`sway-setup-cattpuccin.sh` (repo root) is a Sway/Wayland port of
`fedroa-setup-i3-cattpuccin.sh`, produced by transforming the i3 installer: most
heredocs (GTK/nvim/kitty/rofi/dunst themes, screensaver, battwatch, calendar
daemon, toggles) are reused verbatim; the i3/polybar/X11 pieces are replaced,
ported, or dropped. The 70 polybar bar themes are compiled 1:1 into waybar.

## Pipeline

```sh
# 1. Extract every polybar theme config.ini from the i3 installer into clean,
#    self-contained files (resolving gh0stzk's 3-level include chain).
python3 -I extract_themes.py ../fedroa-setup-i3-cattpuccin.sh /tmp/polybar-src

# 2. Compile each polybar .ini -> waybar config.jsonc + style.css. Faithfully
#    renders polybar's own primitives (custom/text sep modules -> powerline
#    caps via CSS color/background; internal/* -> waybar natives; custom/script
#    -> custom/* with exec/interval/on-click; ws-icon-N -> format-icons).
for f in /tmp/polybar-src/*.ini; do python3 -I polybar2waybar.py "$f" /tmp/out; done

# 3. Emit a shell block that writes all compiled theme dirs as heredocs.
python3 -I gen_theme_writer.py /tmp/out /tmp/theme-writer.sh

# 4. Transform the i3 installer into the sway installer (expects the compiled
#    out/ and theme-writer.sh laid out as <sway-dir>/out, <sway-dir>/theme-writer.sh,
#    <sway-dir>/config/sway.config, <sway-dir>/bin/*.sh).
python3 -I build_sway_installer.py ../fedroa-setup-i3-cattpuccin.sh <sway-dir> ../sway-setup-cattpuccin.sh
```

## Gotchas (learned the hard way)

- **Never use `re.S` (DOTALL) with nested quantifiers** in `build_sway_installer.py`
  post-clean patterns — it catastrophically backtracks on the 1.4 MB installer.
  All multi-line patterns are line-anchored (`re.M`, `[^\n]*`).
- gh0stzk themes are **3-file** (wrapper → `rices/<r>/config.ini` → `modules.ini`
  + `config/system.ini`), with relative `../` includes and an **unquoted**
  `<<GH0STZK_EOF` heredoc; `extract_themes.py` resolves all of that.
- The gh0stzk section is kept intact in the output (its `$GZ_BIN` backend scripts
  are referenced by the compiled gh0stzk waybar themes); its now-unused polybar
  configs are harmless.
- `sway.config` and the 8 runtime scripts (`bin/`) are the authored Wayland
  sources the transformer injects; edit those, not the generated installer.

## fedora-sway-setup.sh (HANCORE waybar-themes variant)

`fedora-sway-setup.sh` is built from `sway-setup-cattpuccin.sh` by
`build_fedora_sway.py`, replacing the embedded Catppuccin theme collection
with [HANCORE-linux/waybar-themes](https://github.com/HANCORE-linux/waybar-themes)
fetched at install time:

```sh
python3 -I build_fedora_sway.py   # ../sway-setup-cattpuccin.sh -> ../fedora-sway-setup.sh
```

Pieces (all under `sway-build/`):

- `hancore-theme-gen.py` — embedded into the installer. Clones the theme
  repo, adapts each theme (hyprland/* -> sway/*, omarchy/hyprctl/alacritty/
  wttrbar commands -> this rice's tools, bundled window_pill.py ported to
  swaymsg), extracts a palette per theme, and writes the same per-theme
  file set the old collection used (rofi/kitty/dunst/starship/sway
  borders + a [colors] ini + an Omarchy-format `palette.css` the styles'
  `@import "../omarchy/current/theme/waybar.css"` resolves against).
- `hancore-shims/` — wttrbar (Python reimplementation), battery-status and
  dnf-update-check helpers the adapted themes exec by name; installed to
  `~/.local/bin` (which `waybar-launch.sh` puts on the bar's PATH).
- `rice-gen-driver.py` — runs the repo's `generate-{gtk,nvim,vscode}-themes.py`
  for *every* theme in `~/.config/polybar/themes/*.ini` instead of their
  hardcoded THEMES lists.
- `bin/waybar-theme.sh` / `bin/waybar-launch.sh` — carry the additions the
  new themes need: the palette.css copy into
  `~/.config/omarchy/current/theme/waybar.css` on switch (which also
  carries a `* { color: @foreground }` base rule - HANCORE styles leave
  module value text uncolored, which otherwise falls back to the GTK
  theme foreground and goes invisible when GTK_THEME doesn't resolve),
  a PATH export, a GTK_THEME export pointing the bar at the current
  Rice-* GTK theme, and an early current-theme-name write so a failed
  switch can't desync the name file from the bar.

The installer asks up front whether to wipe existing themes first
(`CLEAN_THEMES`); a `n` keeps old themes working next to the new ones —
the driver regenerates GTK/nvim/vscode themes for both sets.
