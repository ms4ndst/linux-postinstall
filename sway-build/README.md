# sway-build — sources embedded into `fedora-sway-setup.sh`

`fedora-sway-setup.sh` (repo root) is the single, standalone installer:
every file in this directory is embedded into it as a heredoc, and
`build_fedora_sway.py` re-syncs those embeds in place. Edit a source here,
then re-run the build.

```
python3 -I build_fedora_sway.py   # re-embeds the sources below into ../fedora-sway-setup.sh
```

## Sources

- `bin/*.sh` — the rice's helper scripts (~/.local/bin): theme switcher,
  bar launcher, lock, idle, wallpaper, colorpicker, screenshot, cursor and
  icon switchers, caffeine widget backend
- `hancore-theme-gen.py` — adapts all HANCORE-linux/waybar-themes to this
  Sway/Fedora rice at install time (config rewrite, palette extraction,
  matching rofi/kitty/dunst/starship/sway-border themes)
- `hancore-shims/` — the helper binaries the adapted themes exec by name
  (wttrbar, hancore-battery-status, hancore-update-check, vscode-theme-sync)
- `rice-gen-driver.py` — runs the repo's generate-{gtk,nvim,vscode}-themes.py
  over every installed theme (installer section 15)

Everything else in `fedora-sway-setup.sh` — the sway config, the remaining
helper-script heredocs, the prose — is edited directly in that file.

## Legacy (kept, unused)

`build_sway_installer.py`, `polybar2waybar.py`, `extract_themes.py`,
`gen_theme_writer.py` and `config/sway.config` are the old
i3 -> sway-setup-cattpuccin.sh generation chain, kept for reference only —
nothing consumes them anymore (that intermediate script is gone), and
`config/sway.config` has drifted from the config embedded in the installer.


## Gotchas (learned the hard way)

- All anchors are unique heredoc-opener strings — never line numbers; the
  build refuses to run if one is missing or duplicated.
- `build_fedora_sway.py` writes back only what it re-embedded; after any
  run, `bash -n ../fedora-sway-setup.sh` as a smoke test.
- The installer's sway config heredoc substitutes `@@XKB_LAYOUT@@` at
  install time (`sed` with the detected layout). When re-extracting the
  config from the installer by hand, always re-run that substitution on the
  extracted copy.
- The installer still keeps a `polybar-*` script family and
  `~/.config/polybar/themes/` as the feed for the GTK/Neovim/VS Code theme
  generators — the names are heritage, the files are load-bearing.
