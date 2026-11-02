#!/usr/bin/env bash
# Summon/stash the floating Cliamp window (Mod+M) via the niri scratchpad
# emulation, instead of leaving "quit the TUI" as the only way to get it out of
# the way (kitty exits the moment its child does, so closing has always meant
# killing playback). cliamp keeps MPRIS + its IPC socket alive while parked on
# the scratch workspace, so hiding it doesn't stop playback or lose control.
# Quitting cliamp itself (q in the TUI) still fully stops it.
exec ~/.local/bin/niri-scratch.sh '^Cliamp$' kitty --class Cliamp -e cliamp
