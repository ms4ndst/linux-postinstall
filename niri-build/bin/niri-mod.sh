#!/usr/bin/env bash
# Launch NiriMod - the GTK4 settings editor for niri (github.com/srinivasr/
# NiriMod). Installed by the setup script via NiriMod's own install.sh, which
# drops a `nirimod` launcher on PATH and a .desktop entry. This wrapper keeps
# the keybind stable regardless of exactly how NiriMod was installed.
set -u
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

if command -v nirimod >/dev/null 2>&1; then
  exec nirimod "$@"
elif command -v niri-mod >/dev/null 2>&1; then
  exec niri-mod "$@"
elif command -v flatpak >/dev/null 2>&1 && flatpak info io.github.srinivasr.NiriMod >/dev/null 2>&1; then
  exec flatpak run io.github.srinivasr.NiriMod "$@"
else
  notify-send "NiriMod" "NiriMod is not installed. Re-run the niri setup, or install it from github.com/srinivasr/NiriMod" 2>/dev/null \
    || echo "NiriMod is not installed (github.com/srinivasr/NiriMod)" >&2
  exit 1
fi
