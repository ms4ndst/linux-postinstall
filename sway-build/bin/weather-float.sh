#!/usr/bin/env bash
# Full wttr.in weather report (current conditions + 3-day forecast) in a
# scrollable pager - the floating companion to the waybar weather widget,
# which only shows today's temperature. Same wttr.in source the wttrbar
# widget uses, just the whole report, theme-colored by kitty's current theme.
# Launched from the weather widget's on-click in a floating kitty
# (--class WeatherFloat; floated + centered by the sway config). Press q to
# close.
#
# Location is wttr.in's own IP geolocation (no config needed). To pin a city,
# export WEATHER_LOCATION (e.g. "Stockholm" or "Gothenburg").
set -u
loc="${WEATHER_LOCATION:-}"
# ?F drops the "Follow @igor_chubin" footer line; m = metric units.
url="https://wttr.in/${loc}?Fm"

if out="$(curl -fsS --max-time 12 "$url" 2>/dev/null)" && [ -n "$out" ]; then
  # -R renders the ANSI colors, -X leaves the report on screen after quit is
  # not wanted here (kitty closes anyway), so plain -R with quit-on-q.
  printf '%s\n' "$out" | less -R
else
  printf '\n  Weather unavailable - offline, or wttr.in is unreachable.\n'
  printf '  (Set WEATHER_LOCATION to a city name if geo-IP guessed wrong.)\n\n'
  printf '  Press any key to close.\n'
  read -rn1 _
fi
