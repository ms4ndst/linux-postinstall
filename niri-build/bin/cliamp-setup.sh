#!/usr/bin/env bash
# Opens cliamp's own provider-configuration wizard (`cliamp setup`) in a
# floating window (Mod+Shift+M) - a genuinely different command from bare
# `cliamp` (Mod+M via cliamp-toggle.sh). Picking/configuring a remote source
# (Navidrome, Plex, Spotify, ...) only happens inside `cliamp setup`'s own
# screen, which the player's TUI has no path to. Not scratchpad-toggled - the
# wizard is a one-shot flow that exits on its own, so it's launched fresh.
exec kitty --class CliampSetup -e cliamp setup
