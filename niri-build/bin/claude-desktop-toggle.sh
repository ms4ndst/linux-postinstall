#!/usr/bin/env bash
# Summon/stash Claude Desktop via the niri scratchpad emulation (Copilot/AI key,
# or Mod+Shift+F23), so an in-progress conversation isn't lost by tucking the
# window away. Matches the native-Wayland app-id and the XWayland class.
exec ~/.local/bin/niri-scratch.sh '^(com\.anthropic\.Claude|claude)$' claude-desktop-unofficial
