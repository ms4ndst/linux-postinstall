# niri-build — sources embedded into `fedora-niri-setup.sh`

`fedora-niri-setup.sh` (repo root) is the single, standalone installer for the
**niri** rice — the scrolling-tiling-compositor sibling of `fedora-sway-setup.sh`.
Every source below is embedded into it as a heredoc, and `build_fedora_niri.py`
re-syncs those embeds in place. Edit a source here, then re-run the build.

```
python3 -I build_fedora_niri.py   # re-embeds the sources below into ../fedora-niri-setup.sh
```

## Sources

- `config/niri.kdl` — the niri config (keybinds, window rules, outputs,
  startup, focus-ring accent). Ships with `@@XKB_LAYOUT@@`/`@@CURSOR_THEME@@`
  placeholders the installer fills from `localectl` and the cursor theme.
- `bin/*.sh` — the rice's helper scripts (`~/.local/bin`): the theme switcher
  (`waybar-theme.sh`), bar launcher, lock, idle, wallpaper, screenshot,
  colorpicker, volume/brightness OSD, and `niri-mod.sh` (the NiriMod launcher).

## Shared with the Sway rice (not duplicated here)

The theme-generation engine is **compositor-agnostic** and is embedded straight
from `../sway-build/` by the builder — there is only one copy to maintain:

- `../sway-build/hancore-theme-gen.py` — adapts every
  HANCORE-linux/waybar-themes theme and writes matching waybar/rofi/kitty/
  dunst/starship files plus a palette fragment, seeding the first as active.
- `../sway-build/hancore-shims/*` — the helper binaries the adapted themes exec
  by name (wttrbar, hancore-battery-status, hancore-update-check,
  vscode-theme-sync).

The niri installer runs that generator unchanged, then (in section 6) **rewrites
the generated waybar module names** to niri's (`sway/workspaces` →
`niri/workspaces`, `sway/window` → `niri/window`, `sway/language` →
`niri/language`, `swaymsg` → `niri msg`) and **converts each sway border
fragment** into a niri `focus-ring` KDL fragment under `~/.config/niri/themes/`.
niri's `include "themes/current.kdl"` (positional, live-reloaded) then lets the
switcher retint the focus-ring with a plain file copy — the niri analog of the
Sway rice's `include current-borders.conf`.

## Settings management: NiriMod

`fedora-niri-setup.sh` installs **NiriMod** (github.com/srinivasr/NiriMod), a
GTK4/libadwaita editor for `config.kdl` that validates through `niri validate`
and preserves comments. It is bound to `Mod+Shift+S` via `bin/niri-mod.sh`.

## OpenMandriva port

`port_openmandriva_niri.py` regenerates **`../openmandriva-niri-setup.sh`** from
`../fedora-niri-setup.sh` by anchored string substitution — the niri analog of
`../sway-build/port_openmandriva.py`. Run it **after** the Fedora build:

```
python3 -I build_fedora_niri.py          # 1. refresh the Fedora script
python3 -I port_openmandriva_niri.py     # 2. re-port to OpenMandriva
```

Everything distro-independent carries over byte-for-byte. The port **imports**
the OpenMandriva repo preamble + source-build blocks from the Sway port (one
source of truth), then applies the niri-specific deltas: **niri comes from OM's
own repos** (Rolling/ROME + Cooker — no COPR), `dex-autostart` → systemd's
`xdg-desktop-autostart.target`, **satty** from its GitHub release binary and
**nwg-displays** via pipx (dropping the Sway-only `wdisplays` build), plus the
shared `--setopt=strict=0` installs and verified package renames. Stale anchors
print a WARN. Smoke-test with `bash -n ../openmandriva-niri-setup.sh`.

## Gotchas (learned from the Sway rice)

- All anchors are unique heredoc-opener strings — never line numbers; the build
  refuses to run if one is missing or duplicated.
- After any run, `bash -n ../fedora-niri-setup.sh` as a smoke test, and
  `niri validate` the config on a machine that has niri.
- niri `include` needs niri **25.11+**; the installer always seeds
  `themes/current.kdl` so the include never dangles.
- niri does **not** re-run `spawn-at-startup` on config reload (unlike Sway's
  `exec_always`), so the launcher scripts guard against double-launch
  themselves (`pgrep -x`).

## Scratchpad emulation

Niri has no scratchpad or minimize, so `bin/niri-scratch.sh` emulates one with a
dedicated named `scratch` workspace (declared in `config/niri.kdl`). The
cliamp / Claude / Mistral Vibe / AI-window toggles call it: summon if not
running, move to `scratch` to hide (process stays alive), move back + focus to
show. It uses `niri msg action move-window-to-workspace --window-id … --focus …`
and `focus-window --id …` against `niri msg --json windows`/`workspaces`.

## Scope — full parity

The whole Sway rice is ported: compositor + bar + theme switcher, NiriMod, and
the long tail — app-menu, powermenu, wifi toggle/menu, caffeine/DND, OSD
volume/brightness, notification center, screensaver (+ text setter), the
calendar reminder daemon, battwatch, fix-mx-scroll, cursor/icon theme switchers,
cliamp + Strata installs, the Jabra/HP hardware tweaks, the GTK/Neovim/VS Code
theme generators, and `app-theme-sync.sh` (retints cliamp/Vibe/Strata from the
niri focus-ring + kitty palette).

Deliberately dropped (X11/i3-only, or replaced natively): the `polybar-*` widget
backends and `snixembed` (waybar has a native SNI tray). `arrange-displays.sh`
opens `nwg-displays`/NiriMod instead of issuing runtime output moves (niri has
no such IPC; outputs live in `config.kdl`). `screensaver.sh`'s mouse-move
dismiss uses `xdotool` (X11) so it only reacts to keypresses under niri — the
keypress dismiss works. `ai-key-manager` is an optional external repo tool, not
installed here (the app-menu entry is guarded).
