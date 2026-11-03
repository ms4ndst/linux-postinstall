#!/usr/bin/env bash
# Toggle a floating weather window from the waybar weather widget. First click
# opens a wttr.in-style report - the same ASCII-art condition pictures wttr.in
# draws - but rendered locally from open-meteo.com data (free, no API key),
# because wttr.in itself is frequently down or blocked on corporate networks.
# Clicking the widget again closes it (any key closes it too).
#
# The art is the wego icon set (plain ANSI colours + box chars, no Nerd-Font
# glyphs), so it renders in any font. Location: a city name resolved via
# open-meteo geocoding, or a literal "lat,lon"; set WEATHER_LOCATION or
# ~/.config/weather/location (default: Stockholm).
set -u

if [ "${1:-}" = "--show" ]; then
  python3 -I - <<'PYEOF'
import json, os, re, urllib.parse, urllib.request
from datetime import datetime

R = "\033[0m"
def paint(code, lines):
    return ["\033[%sm%s%s" % (code, ln, R) for ln in lines]

# wego / wttr.in ASCII art, 5 lines x 13 cols each.
ART = {
 "sunny": paint("38;5;226", ["    \\   /    ","     .-.     ","  ― (   ) ―  ","     `-'     ","    /   \\    "]),
 "partly": paint("38;5;250", ["   \\  /      "," _ /\"\".-.    ","   \\_(   ).  ","   /(___(__) ","             "]),
 "cloudy": paint("38;5;250", ["             ","     .--.    ","  .-(    ).  "," (___.__)__) ","             "]),
 "overcast": paint("38;5;240;1", ["             ","     .--.    ","  .-(    ).  "," (___.__)__) ","             "]),
 "fog": paint("38;5;251", ["             "," _ - _ - _ - ","  _ - _ - _  "," _ - _ - _ - ","             "]),
 "rain": paint("38;5;111", ["     .-.     ","    (   ).   ","   (___(__)  ","    ‘ ‘ ‘ ‘  ","   ‘ ‘ ‘ ‘   "]),
 "heavyrain": paint("38;5;21;1", ["     .-.     ","    (   ).   ","   (___(__)  ","  ‚‘‚‘‚‘‚‘   ","  ‚’‚’‚’‚’   "]),
 "snow": paint("38;5;255", ["     .-.     ","    (   ).   ","   (___(__)  ","    *  *  *  ","   *  *  *   "]),
 "sleet": paint("38;5;255", ["     .-.     ","    (   ).   ","   (___(__)  ","    ‘ * ‘ *  ","   * ‘ * ‘   "]),
 "thunder": paint("38;5;228", ["     .-.     ","    (   ).   ","   (___(__)  ","  ⚡‘‘⚡‘‘   ","  ‘⚡‘‘⚡‘   "]),
 "unknown": ["    .-.      ","     __)     ","    (        ","     `-'     ","      •      "],
}
# WMO weather code -> (text description, art key).
WMO = {
 0:("Clear","sunny"),1:("Mainly clear","sunny"),2:("Partly cloudy","partly"),
 3:("Overcast","overcast"),45:("Fog","fog"),48:("Rime fog","fog"),
 51:("Light drizzle","rain"),53:("Drizzle","rain"),55:("Heavy drizzle","rain"),
 56:("Freezing drizzle","sleet"),57:("Freezing drizzle","sleet"),
 61:("Light rain","rain"),63:("Rain","rain"),65:("Heavy rain","heavyrain"),
 66:("Freezing rain","sleet"),67:("Freezing rain","sleet"),
 71:("Light snow","snow"),73:("Snow","snow"),75:("Heavy snow","snow"),
 77:("Snow grains","snow"),80:("Rain showers","rain"),81:("Rain showers","rain"),
 82:("Violent showers","heavyrain"),85:("Snow showers","snow"),86:("Snow showers","snow"),
 95:("Thunderstorm","thunder"),96:("Thunderstorm, hail","thunder"),99:("Thunderstorm, hail","thunder"),
}
ARROWS = ["↓","↙","←","↖","↑","↗","→","↘"]

def getj(u):
    req = urllib.request.Request(u, headers={"User-Agent": "wttrbar-shim"})
    with urllib.request.urlopen(req, timeout=12) as r:
        return json.load(r)

def resolve():
    loc = os.environ.get("WEATHER_LOCATION")
    if not loc:
        try:
            loc = open(os.path.expanduser("~/.config/weather/location")).read().strip()
        except Exception:
            loc = ""
    loc = loc or "Stockholm"
    m = re.match(r"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$", loc)
    if m:
        return float(m.group(1)), float(m.group(2)), loc
    r = getj("https://geocoding-api.open-meteo.com/v1/search?name="
             + urllib.parse.quote(loc) + "&count=1&language=en&format=json")
    hit = (r.get("results") or [None])[0]
    if not hit:
        raise ValueError("unknown location: %r" % loc)
    label = hit["name"] + ((", " + hit["country_code"]) if hit.get("country_code") else "")
    return hit["latitude"], hit["longitude"], label

def center(s, w):
    s = s[:w]
    pad = w - len(s)
    return " " * (pad // 2) + s + " " * (pad - pad // 2)

try:
    lat, lon, label = resolve()
    d = getj("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
             "&current=temperature_2m,apparent_temperature,weather_code,"
             "wind_speed_10m,wind_direction_10m,precipitation,relative_humidity_2m"
             "&daily=weather_code,temperature_2m_max,temperature_2m_min"
             "&forecast_days=4&wind_speed_unit=kmh&timezone=auto"
             % (lat, lon))
    cur = d["current"]
    desc, key = WMO.get(int(cur["weather_code"]), ("Unknown", "unknown"))
    art = ART.get(key, ART["unknown"])
    arrow = ARROWS[int((cur.get("wind_direction_10m", 0) % 360) / 45 + 0.5) % 8]
    info = [
        desc,
        "%d °C  (feels %d °C)" % (round(cur["temperature_2m"]), round(cur["apparent_temperature"])),
        "%s %d km/h" % (arrow, round(cur.get("wind_speed_10m", 0))),
        "%.1f mm  •  %d%% hum" % (cur.get("precipitation", 0.0), round(cur.get("relative_humidity_2m", 0))),
        "",
    ]
    print()
    print("  Weather report: " + label)
    print()
    for i in range(5):
        print("  %s   %s" % (art[i], info[i]))
    print()

    dy = d["daily"]
    cols = []
    for i, day in enumerate(dy["time"]):
        ddesc, dkey = WMO.get(int(dy["weather_code"][i]), ("Unknown", "unknown"))
        da = ART.get(dkey, ART["unknown"])
        name = datetime.strptime(day, "%Y-%m-%d").strftime("%A")
        lo = round(dy["temperature_2m_min"][i]); hi = round(dy["temperature_2m_max"][i])
        col = [center(name, 13)] + da + [center("%d / %d °C" % (hi, lo), 13)]
        cols.append(col)
    for r in range(len(cols[0])):
        print("  " + "  ".join(col[r] for col in cols))
    print()
    print("  (press any key to close)")
except Exception as e:
    print()
    print("  Weather unavailable — %s" % e)
    print("  Set a city with WEATHER_LOCATION or ~/.config/weather/location.")
    print()
    print("  (press any key to close)")
PYEOF
  read -rsn1 _ 2>/dev/null || true
  exit 0
fi

# Toggle: if a WeatherFloat window is open, close it; otherwise open one.
__wid="$(niri msg --json windows 2>/dev/null | jq -r '[.[] | select(.app_id=="WeatherFloat")][0].id // empty' 2>/dev/null)"
if [ -n "${__wid:-}" ]; then
  niri msg action focus-window --id "$__wid" >/dev/null 2>&1
  niri msg action close-window >/dev/null 2>&1
else
  kitty --class WeatherFloat \
        -o background_opacity=1.0 \
        -o window_padding_width=14 \
        -o font_size=12 \
        -e "$0" --show >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
