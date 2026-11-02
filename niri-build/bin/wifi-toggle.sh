#!/usr/bin/env bash
# Wifi radio on/off toggle for the network-wireless widget's right-click
# action. `nmcli radio wifi` only accepts on/off, not "toggle" - confirmed
# live: `nmcli radio wifi toggle` errors with "invalid 'wifi' argument:
# 'toggle' (use on/off)", and since the click action backgrounds it with
# `&`, that error went nowhere visible - right-click silently never
# toggled anything. Checking the current state first instead.
if [ "$(nmcli radio wifi)" = "enabled" ]; then
  nmcli radio wifi off
  notify-send -h string:x-dunst-stack-tag:wifi "Wi-Fi" "Disabled"
else
  nmcli radio wifi on
  notify-send -h string:x-dunst-stack-tag:wifi "Wi-Fi" "Enabled"
fi
