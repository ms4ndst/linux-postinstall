#!/usr/bin/env bash
# Summon/stash a floating "AI window" running the Mistral Vibe CLI (`vibe`)
# (Mod+A) via the niri scratchpad emulation, so an in-progress Vibe session
# isn't lost by just tucking the window away. The startup folder is configurable
# via the app menu's "Set AI Window Folder" entry (set-ai-window-folder.sh);
# $HOME if never set. `vibe --workdir` is its own documented flag for this.
exec ~/.local/bin/niri-scratch.sh '^AIVibe$' \
  sh -c 'exec kitty --class AIVibe -e vibe --workdir "$(cat "$HOME/.config/ai-window/workdir" 2>/dev/null || echo "$HOME")"'
