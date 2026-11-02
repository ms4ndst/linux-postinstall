#!/usr/bin/env bash
# Summon/stash the Mistral Vibe web app (chat.mistral.ai) via the niri
# scratchpad emulation (Mod+Shift+A). Mistral ships no Linux desktop app, so it
# runs in a Chromium-family browser's --app mode (no tabs/toolbar) in its own
# profile dir, so --class takes effect and the sign-in is kept between launches.
set -u
profile="$HOME/.local/share/mistral-vibe-app"
url="https://chat.mistral.ai"

# Resolve a browser once so the spawn command handed to niri-scratch is concrete.
browser=""
for b in google-chrome-stable google-chrome chromium chromium-browser brave-browser microsoft-edge-stable vivaldi-stable vivaldi; do
  if command -v "$b" >/dev/null 2>&1; then browser="$b"; break; fi
done
if [ -z "$browser" ]; then
  notify-send "Mistral Vibe" "Needs a Chromium-based browser (Chrome, Chromium, Brave, Edge or Vivaldi) - install one from the post-install script's Browsers category." 2>/dev/null
  exit 1
fi

# --ozone-platform=x11 is deliberate: under native Wayland, Chromium/Vivaldi
# ignore --class for the app_id (it becomes vivaldi-<hash>-Default), so neither
# the floating window-rule nor the scratchpad could match. Forcing XWayland
# makes WM_CLASS=MistralVibe, which niri reports as app_id MistralVibe - so the
# window floats and the scratch toggle can find it.
exec ~/.local/bin/niri-scratch.sh '^MistralVibe$' \
  "$browser" --user-data-dir="$profile" --class=MistralVibe --ozone-platform=x11 \
  --no-first-run --no-default-browser-check --app="$url"
