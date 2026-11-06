#!/usr/bin/env bash
# Theme the GDM login screen to match the active rice theme.
#
# GDM is GNOME Shell, whose theme is a single compiled resource bundle at
# /usr/share/gnome-shell/gnome-shell-theme.gresource. There is no drop-in GDM
# "theme folder"; the only way to set a login background / colors / font is to
# rebuild that bundle. This script does it SAFELY:
#   - it extracts a PRISTINE copy of the stock bundle (snapshotted once as
#     *.rice-orig, and kept), so re-runs never stack overrides;
#   - it only APPENDS a small override block to the theme CSS - no upstream file
#     is removed or rewritten, so the login screen stays complete;
#   - it backs the current bundle up to *.bak before installing;
#   - it NEVER restarts gdm (that would log you out) - changes show on the next
#     login / reboot.
#
# By default the login background is the theme's solid dark color (the same
# `base` the waybar/rofi theme uses), the text color is the theme `text`, the
# buttons/entry focus use the theme `accent`, and the font is the rice Nerd Font.
# Colors come from the active rofi theme (~/.config/rofi/current.rasi, which the
# waybar/rofi theme switcher rewrites on every theme change).
#
# Usage:
#   gdm-theme-sync.sh                 # solid theme background + colors + font
#   gdm-theme-sync.sh --wallpaper     # use the current wallpaper as background
#   gdm-theme-sync.sh --stage-only    # build + validate the bundle, don't install
#   gdm-theme-sync.sh --revert        # restore the stock GDM theme
#   gdm-theme-sync.sh --refresh-base  # re-snapshot the stock bundle as pristine
#                                     # (run this AFTER a gnome-shell update, which
#                                     # reverts the bundle to stock, then re-run)
#
# Needs root only for the final install step (and --revert/--refresh-base); it
# calls sudo for just that and prompts once. Everything else runs as you.
set -u

GRESOURCE="${GDM_THEME_GRESOURCE:-/usr/share/gnome-shell/gnome-shell-theme.gresource}"
PRISTINE="$GRESOURCE.rice-orig"
BACKUP="$GRESOURCE.bak"
PREFIX="/org/gnome/shell/theme"
BG_NAME="rice-gdm-bg.jpg"
RASI="${RICE_RASI:-$HOME/.config/rofi/current.rasi}"
FONT="${RICE_GDM_FONT:-JetBrainsMono Nerd Font}"
FONT_SIZE="${RICE_GDM_FONT_SIZE:-11}"
MARKER="rice-gdm-theme"
# GDM font + accent are RUNTIME dconf settings that override theme CSS, so the
# only reliable way to change them is a dconf override for the gdm user. We own
# a single file here; GDM Settings owns 95-gdm-settings - a higher number wins,
# so these keys override whatever GDM Settings set, and --revert removes it.
DCONF_FILE="/etc/dconf/db/gdm.d/96-rice-gdm-theme"

die() { echo "gdm-theme-sync: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
need glib-compile-resources
need gresource

MODE="sync"; USE_WALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stage-only)   MODE="stage" ;;
    --wallpaper)    USE_WALL=1 ;;
    --revert)       MODE="revert" ;;
    --refresh-base) MODE="refresh" ;;
    -h|--help)      sed -n '2,/^set -u/p' "$0" | sed 's/^# \{0,1\}//; /^set -u/d'; exit 0 ;;
    *) die "unknown option: $1 (try --help)";;
  esac; shift
done

[ -f "$GRESOURCE" ] || die "GDM theme bundle not found: $GRESOURCE"

# ---------------------------------------------------------------- revert
if [ "$MODE" = "revert" ]; then
  src=""
  [ -f "$PRISTINE" ] && src="$PRISTINE"
  [ -z "$src" ] && [ -f "$BACKUP" ] && src="$BACKUP"
  [ -n "$src" ] || die "no pristine/backup found to revert to"
  sudo sh -c '
    set -e
    install -m644 "$1" "$2"          # restore stock gresource
    rm -f "$3"                        # drop our dconf override
    command -v dconf >/dev/null 2>&1 && dconf update || true
  ' _ "$src" "$GRESOURCE" "$DCONF_FILE" || die "revert failed"
  echo "Reverted GDM (gresource + dconf override removed). Shows on next login."
  echo "Note: GDM Settings' own override (95-gdm-settings) is left untouched."
  exit 0
fi

# ---------------------------------------------------------------- refresh-base
if [ "$MODE" = "refresh" ]; then
  sudo install -m644 "$GRESOURCE" "$PRISTINE" || die "could not snapshot pristine"
  echo "Snapshotted the current GDM bundle as pristine ($PRISTINE)."
  echo "Now run 'gdm-theme-sync.sh' to re-apply the rice theme on top."
  exit 0
fi

# ---------------------------------------------------------------- palette
getcol() {
  local hex
  hex=$(grep -oE "(^|[^a-zA-Z-])$1:[[:space:]]*#[0-9a-fA-F]{6,8}" "$RASI" 2>/dev/null \
          | grep -oE '#[0-9a-fA-F]{6,8}' | head -1)
  [ -n "$hex" ] && printf '#%s' "$(printf '%s' "${hex#\#}" | cut -c1-6)"
}
BASE=""; TEXT=""; ACCENT=""
if [ -f "$RASI" ]; then
  BASE=$(getcol base); TEXT=$(getcol text); ACCENT=$(getcol accent)
fi
: "${BASE:=#1e1e2e}"; : "${TEXT:=#cdd6f4}"; : "${ACCENT:=#89b4fa}"

# GNOME's accent-color is a fixed enum (GNOME 47+), not arbitrary hex - map the
# theme accent to the nearest named accent so GDM's native accent follows it.
nearest_accent() {
  local hex=${1#\#} r g b name ph pr pg pb d best bd
  r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
  best="blue"; bd=1000000000
  for pair in blue:3584e4 teal:2190a4 green:3a944a yellow:c88800 \
              orange:ed5b00 red:e62d42 pink:d56199 purple:9141ac slate:6f8396; do
    name=${pair%%:*}; ph=${pair#*:}
    pr=$((16#${ph:0:2})); pg=$((16#${ph:2:2})); pb=$((16#${ph:4:2}))
    d=$(( (r-pr)*(r-pr) + (g-pg)*(g-pg) + (b-pb)*(b-pb) ))
    [ "$d" -lt "$bd" ] && { bd=$d; best=$name; }
  done
  printf '%s' "$best"
}
ACCENT_NAME=$(nearest_accent "$ACCENT")
# Login text color. Default is the theme accent (the "red") per preference;
# override with RICE_GDM_TEXT_COLOR=#rrggbb (e.g. the near-white $TEXT) if wanted.
FG="${RICE_GDM_TEXT_COLOR:-$ACCENT}"
echo "Palette: base=$BASE text/fg=$FG accent=$ACCENT (~$ACCENT_NAME)   font='$FONT $FONT_SIZE'   (from $RASI)"

# ---------------------------------------------------------------- wallpaper (opt-in)
# Mirrors swaybg-restore.sh, including its "a newer azote pick overrides an
# older saved pick" rule - so --wallpaper tracks what you actually set in Azote.
resolve_wallpaper() {
  local cfg="$HOME/.config/niri" saved azote img
  saved="$cfg/wallpaper-saved"
  azote="$HOME/.local/share/azote/swaybg.json"
  img=""
  [ -f "$saved" ] && img=$(cat "$saved" 2>/dev/null)
  if [ -n "$img" ] && [ -f "$img" ]; then
    [ -f "$azote" ] && [ "$azote" -nt "$saved" ] && img=""   # newer azote wins
  else
    img=""
  fi
  if [ -z "$img" ] && [ -f "$azote" ] && command -v jq >/dev/null 2>&1; then
    img=$(jq -r 'first(.[] | select(.path) | .path) // empty' "$azote" 2>/dev/null)
    [ -n "$img" ] && [ -f "$img" ] || img=""
  fi
  [ -z "$img" ] && [ -f "$cfg/wallpaper.png" ] && img="$cfg/wallpaper.png"
  printf '%s' "$img"
}
WALL=""
if [ "$USE_WALL" = 1 ]; then
  command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 \
    || die "--wallpaper needs ImageMagick (magick/convert)"
  WALL=$(resolve_wallpaper)
  [ -n "$WALL" ] && echo "Wallpaper: $WALL" \
    || { echo "Wallpaper: none found - falling back to solid $BASE"; }
else
  echo "Background: solid $BASE (theme background; use --wallpaper for a photo)"
fi

# ---------------------------------------------------------------- stage
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gdm-theme.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT
EXTRACT="$TMP/theme"; mkdir -p "$EXTRACT"

SRC="$GRESOURCE"
[ -f "$PRISTINE" ] && SRC="$PRISTINE"
while IFS= read -r res; do
  rel="${res#$PREFIX/}"
  out="$EXTRACT/$rel"
  mkdir -p "$(dirname "$out")"
  gresource extract "$SRC" "$res" > "$out" || die "extract failed: $res"
done < <(gresource list "$SRC")

# Background block: solid theme color, or the wallpaper if --wallpaper resolved one.
if [ "$USE_WALL" = 1 ] && [ -n "$WALL" ]; then
  if command -v magick >/dev/null 2>&1; then MG=magick; else MG=convert; fi
  "$MG" "$WALL" -auto-orient -resize 2560x1600^ -gravity center \
    -extent 2560x1600 -quality 85 "$EXTRACT/$BG_NAME" 2>/dev/null \
    || cp "$WALL" "$EXTRACT/$BG_NAME"
  BG_BLOCK=$(printf "  background-color: %s;\n  background-image: url('resource://%s/%s');\n  background-size: cover;\n  background-position: center;\n  background-repeat: no-repeat;" \
    "$BASE" "$PREFIX" "$BG_NAME")
else
  BG_BLOCK=$(printf '  background-color: %s;\n  background-image: none;\n  background-gradient-direction: none;' "$BASE")
fi

# Override CSS. Appended last so it wins. Unknown selectors are no-ops in the
# shell's CSS engine, so the broad coverage is safe across GNOME versions.
OVERRIDE=$(cat <<CSS

/* --- $MARKER: appended by gdm-theme-sync.sh (keyed to the active rice theme) --- */
stage {
  font-family: "$FONT", "JetBrains Mono", monospace;
  color: $FG;
}
#lockDialogGroup {
$BG_BLOCK
}
.login-dialog, .unlock-dialog { color: $FG; }
.login-dialog StLabel, .unlock-dialog StLabel,
.login-dialog-prompt-label, .login-dialog-username,
.login-dialog-not-listed-label,
.screen-shield-clock, .screen-shield-clock-time, .screen-shield-clock-date,
.unlock-dialog-clock, .unlock-dialog-clock-time, .unlock-dialog-clock-date {
  color: $FG;
}
.login-dialog StEntry, .unlock-dialog StEntry {
  color: $FG;
  caret-color: $ACCENT;
}
.login-dialog StEntry:focus, .unlock-dialog StEntry:focus { border-color: $ACCENT; }
.login-dialog .button:default,
.unlock-dialog .button:default,
.modal-dialog .button:default {
  background-color: $ACCENT;
  color: $BASE;
  border-color: $ACCENT;
}
.login-dialog-user-list:expanded .login-dialog-user-list-item:selected,
.login-dialog .login-dialog-user-list-item:selected { background-color: $ACCENT; color: $BASE; }
/* --- end $MARKER --- */
CSS
)

appended=0
for css in gnome-shell.css gnome-shell-dark.css gnome-shell-light.css gdm.css gdm3.css; do
  if [ -f "$EXTRACT/$css" ]; then
    printf '%s\n' "$OVERRIDE" >> "$EXTRACT/$css"
    appended=$((appended+1))
  fi
done
[ "$appended" -gt 0 ] || die "no theme CSS found in the bundle to append to"

# Manifest listing EVERY extracted file (nothing dropped).
XML="$TMP/gnome-shell-theme.gresource.xml"
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<gresources>\n'
  printf '  <gresource prefix="%s">\n' "$PREFIX"
  ( cd "$EXTRACT" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) \
    | while IFS= read -r f; do printf '    <file>%s</file>\n' "$f"; done
  printf '  </gresource>\n</gresources>\n'
} > "$XML"

STAGED="$TMP/gnome-shell-theme.gresource"
glib-compile-resources --target="$STAGED" --sourcedir="$EXTRACT" "$XML" \
  || die "glib-compile-resources failed"
gresource list "$STAGED" >/dev/null || die "staged bundle is unreadable"
if [ "$USE_WALL" = 1 ] && [ -n "$WALL" ]; then
  gresource list "$STAGED" | grep -q "$BG_NAME" || die "staged bundle missing the background image"
fi
echo "Built + validated staged bundle."

# dconf override for the gdm user: font + accent + dark scheme (runtime settings
# that CSS cannot override). Only these theme-related keys; GDM Settings' other
# keys in 95-gdm-settings are left alone.
DCONF_CONTENT=$(cat <<DCONF
# Managed by gdm-theme-sync.sh - keyed to the active rice theme.
# Remove with 'gdm-theme-sync.sh --revert'. Do not hand-edit.
[org/gnome/desktop/interface]
font-name='$FONT $FONT_SIZE'
color-scheme='prefer-dark'
accent-color='$ACCENT_NAME'
DCONF
)

if [ "$MODE" = "stage" ] || [ -n "${GDM_THEME_NO_INSTALL:-}" ]; then
  OUTDIR="${XDG_CACHE_HOME:-$HOME/.cache}/rice"; mkdir -p "$OUTDIR"
  cp "$STAGED" "$OUTDIR/gnome-shell-theme.gresource"
  echo "Staged (not installed): $OUTDIR/gnome-shell-theme.gresource"
  echo "Would write dconf override $DCONF_FILE:"
  printf '%s\n' "$DCONF_CONTENT" | sed 's/^/    /'
  exit 0
fi

# ---------------------------------------------------------------- install
echo "Installing (needs root for $GRESOURCE + dconf)..."
sudo sh -c '
  set -e
  GRES="$1"; PRIS="$2"; BAK="$3"; NEW="$4"; DCF="$5"; DCC="$6"
  [ -f "$PRIS" ] || cp "$GRES" "$PRIS"          # pristine snapshot, first run only
  cp "$GRES" "$BAK"                              # rolling backup
  install -m644 "$NEW" "$GRES"                   # install themed gresource
  mkdir -p "$(dirname "$DCF")"
  printf "%s\n" "$DCC" > "$DCF"                  # font/accent/scheme for gdm user
  command -v dconf >/dev/null 2>&1 && dconf update || true
' _ "$GRESOURCE" "$PRISTINE" "$BACKUP" "$STAGED" "$DCONF_FILE" "$DCONF_CONTENT" \
  || die "install failed"

echo "Done. GDM now matches your rice theme - it shows on your NEXT login."
echo "  accent '$ACCENT_NAME' + font '$FONT $FONT_SIZE' set via dconf; background/text via theme."
echo "  revert:  gdm-theme-sync.sh --revert"
echo "  note:    don't 'systemctl restart gdm' while logged in (it logs you out)."
