#!/usr/bin/env bash
# Restore the saved wallpaper with swaybg (niri has no built-in wallpaper;
# swaybg is a layer-shell client and works fine under niri). Picks the NEWEST of
# three sources by mtime, so the most recent wallpaper change always wins no
# matter which tool set it:
#   1. ~/.config/niri/wallpaper-saved   - a bare path, written by the rofi picker
#   2. ~/.azotebg                       - azote's own restore script. azote
#      detects this rice's WM as "sway" and writes the LATEST pick HERE (one
#      `swaybg -o <out> -i <path> -m <mode>` line per output) - it does NOT keep
#      swaybg.json up to date, so reading only the JSON restores a stale picture.
#   3. ~/.local/share/azote/swaybg.json - azote's older per-output JSON record.
# Falls back to the azote JSON, then ~/.config/niri/wallpaper.png (installer).
# niri does not re-run startup spawns on reload, but this is also bound/callable
# directly, so kill any previous swaybg first to avoid stacking.
set -u
CFG="$HOME/.config/niri"
SAVED="$CFG/wallpaper-saved"
AZOTEBG="$HOME/.azotebg"
AZOTE_JSON="$HOME/.local/share/azote/swaybg.json"

# --- pick the newest existing source by mtime --------------------------------
newest=""; newest_t=0
consider() {
  local f="$1" t
  [ -e "$f" ] || return
  t="$(stat -c %Y "$f" 2>/dev/null)" || return
  if [ "$t" -gt "$newest_t" ]; then newest_t="$t"; newest="$f"; fi
}
consider "$SAVED"; consider "$AZOTEBG"; consider "$AZOTE_JSON"

# Parse the `swaybg ... -o <out> -i <img> -m <mode>` lines azote writes into
# ~/.azotebg (one per output; -o/-m may be absent on a single display).
azotebg_args() {
  local line out img mode
  while IFS= read -r line; do
    case "$line" in *swaybg*-i*) ;; *) continue ;; esac
    out="$(sed -n "s/.*-o '\\([^']*\\)'.*/\\1/p" <<<"$line")"
    [ -z "$out" ] && out="$(sed -n 's/.*-o "\([^"]*\)".*/\1/p' <<<"$line")"
    img="$(sed -n 's/.*-i "\([^"]*\)".*/\1/p' <<<"$line")"
    [ -z "$img" ] && img="$(sed -n "s/.*-i '\\([^']*\\)'.*/\\1/p" <<<"$line")"
    mode="$(sed -n 's/.*-m \([^ &]*\).*/\1/p' <<<"$line")"; [ -z "$mode" ] && mode="fill"
    [ -n "$img" ] && [ -f "$img" ] || continue
    if [ -n "$out" ]; then ARGS+=(-o "$out" -i "$img" -m "$mode")
    else ARGS+=(-i "$img" -m "$mode"); fi
  done < "$AZOTEBG"
}

# Per-output entries from azote's JSON.
azote_json_args() {
  command -v jq >/dev/null 2>&1 || return
  local out path
  while IFS=$'\t' read -r out path; do
    [ -n "$out" ] && [ -n "$path" ] && [ -f "$path" ] \
      && ARGS+=(-o "$out" -i "$path" -m fill)
  done < <(jq -r '.[] | select(.name and .path) | [.name, .path] | @tsv' \
             "$AZOTE_JSON" 2>/dev/null)
}

ARGS=()
case "$newest" in
  "$SAVED")
    IMG="$(cat "$SAVED" 2>/dev/null)"
    [ -n "$IMG" ] && [ -f "$IMG" ] && ARGS=(-i "$IMG" -m fill)
    ;;
  "$AZOTEBG")   azotebg_args ;;
  "$AZOTE_JSON") azote_json_args ;;
esac

# If the newest source produced nothing usable (vanished files, parse miss),
# fall through: azote JSON, then the installer-seeded wallpaper.
[ "${#ARGS[@]}" -eq 0 ] && [ -f "$AZOTE_JSON" ] && azote_json_args
[ "${#ARGS[@]}" -eq 0 ] && [ -f "$CFG/wallpaper.png" ] \
  && ARGS=(-i "$CFG/wallpaper.png" -m fill)
[ "${#ARGS[@]}" -eq 0 ] && exit 0

pkill -x swaybg 2>/dev/null
for _ in 1 2 3 4 5; do pgrep -x swaybg >/dev/null 2>&1 || break; sleep 0.1; done
swaybg "${ARGS[@]}" >/dev/null 2>&1 &
disown || true
