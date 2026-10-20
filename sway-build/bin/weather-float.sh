#!/usr/bin/env bash
# Toggle a floating weather window from the waybar weather widget. First click
# opens the full wttr.in report (current conditions + 3-day forecast) in a
# floating, OPAQUE, theme-colored kitty; clicking the widget again closes it
# (q inside the window closes it too). The same wttr.in source the wttrbar
# widget uses, just the whole report instead of today's temperature.
#
# Opaque (background_opacity=1.0) because the rice's kitty is translucent and
# the wallpaper/other windows bleeding through made the report unreadable; a
# smaller font_size so the 4-column forecast table fits the window width.
#
# Location is wttr.in's own IP geolocation (no config). To pin a city, export
# WEATHER_LOCATION (e.g. "Stockholm" or "Gothenburg").
set -u

# --show is the renderer, run inside the kitty window.
if [ "${1:-}" = "--show" ]; then
  loc="${WEATHER_LOCATION:-}"
  url="https://wttr.in/${loc}?Fm"        # F = no footer, m = metric
  if out="$(curl -fsS --max-time 12 "$url" 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s\n' "$out" | less -R       # -R keeps colors; scroll if it overflows
  else
    printf '\n  Weather unavailable - offline, or wttr.in is unreachable.\n'
    printf '  (Set WEATHER_LOCATION to a city name if geo-IP guessed wrong.)\n\n'
    printf '  Press any key to close.\n'
    read -rn1 _
  fi
  exit 0
fi

# Toggle: if a WeatherFloat window is open, close it; otherwise open one.
if swaymsg -t get_tree 2>/dev/null | grep -q '"WeatherFloat"'; then
  swaymsg '[app_id="WeatherFloat"] kill' >/dev/null 2>&1
else
  kitty --class WeatherFloat \
        -o background_opacity=1.0 \
        -o font_size=9 \
        -e "$0" --show >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
