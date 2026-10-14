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
