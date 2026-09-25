#!/usr/bin/env bash
# ai-key-manager — store/test/remove Anthropic + Mistral API keys in the
# Secret Service keyring (GNOME Keyring). Used by ~/.config/crush/crushrc:
#   secret-tool lookup service anthropic|mistral
# Keys never touch argv, disk, or shell history: zenity -> stdin -> secret-tool,
# and curl reads its auth header from a process-substitution fd.
# Deps: zenity, secret-tool (libsecret), curl, a running Secret Service daemon.
set -u

TITLE="AI API Keys"

die() { zenity --error --title="$TITLE" --width=360 --text="$1" 2>/dev/null; exit 1; }
for c in zenity secret-tool curl; do
  command -v "$c" >/dev/null || { notify-send "$TITLE" "Missing dependency: $c" 2>/dev/null; echo "missing $c" >&2; exit 1; }
done

label()  { case $1 in anthropic) echo "Anthropic (Claude)";; mistral) echo "Mistral";; esac; }

# HTTP status of GET /v1/models with the given key (key passed on stdin).
test_key() {
  local svc=$1 key
  IFS= read -r key
  case $svc in
    anthropic)
      curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
        -H @<(printf 'x-api-key: %s\nanthropic-version: 2023-06-01\n' "$key") \
        https://api.anthropic.com/v1/models ;;
    mistral)
      curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
        -H @<(printf 'Authorization: Bearer %s\n' "$key") \
        https://api.mistral.ai/v1/models ;;
  esac
}

explain() {
  case $1 in
    200) echo "valid";;
    401|403) echo "rejected (invalid or revoked key)";;
    000) echo "no response (network?)";;
    *) echo "HTTP $1";;
  esac
}

set_key() {
  local svc=$1 key code
  key=$(zenity --password --title="$TITLE — $(label "$svc")" 2>/dev/null) || return
  key=$(printf '%s' "$key" | tr -d '[:space:]')
  [[ -n $key ]] || { die "Empty key — nothing stored."; }

  # Sanity check: catches the "typed my login password" mistake.
  if [[ $svc == anthropic && $key != sk-ant-* ]]; then
    zenity --question --title="$TITLE" --width=380 \
      --text="This doesn't look like an Anthropic API key (should start with sk-ant-).\n\nStore it anyway?" 2>/dev/null || return
  fi

  code=$(printf '%s\n' "$key" | test_key "$svc")
  if [[ $code != 200 ]]; then
    zenity --question --title="$TITLE" --width=380 \
      --text="$(label "$svc") says: $(explain "$code").\n\nStore it anyway?" 2>/dev/null || { key=; return; }
  fi

  if printf '%s' "$key" | secret-tool store --label="$(label "$svc") API" service "$svc"; then
    zenity --info --title="$TITLE" --width=320 --text="$(label "$svc") key stored ($(explain "$code"))." 2>/dev/null
  else
    die "Could not write to the keyring. Is gnome-keyring-daemon running?"
  fi
  key=
}

status() {
  local out="" svc key code
  for svc in anthropic mistral; do
    key=$(secret-tool lookup service "$svc" 2>/dev/null)
    if [[ -z $key ]]; then
      out+="$(label "$svc"): not set\n"
    else
      code=$(printf '%s\n' "$key" | test_key "$svc")
      out+="$(label "$svc"): stored, $(explain "$code")\n"
    fi
  done
  key=
  zenity --info --title="$TITLE — status" --width=360 --text="$out" 2>/dev/null
}

remove_key() {
  local svc=$1
  zenity --question --title="$TITLE" --width=320 \
    --text="Remove the stored $(label "$svc") key?" 2>/dev/null || return
  secret-tool clear service "$svc"
  zenity --info --title="$TITLE" --width=300 --text="$(label "$svc") key removed." 2>/dev/null
}

while :; do
  choice=$(zenity --list --title="$TITLE" --width=380 --height=320 \
    --text="Keys are stored in your login keyring." \
    --column="id" --column="Action" --hide-column=1 --print-column=1 \
    set-anthropic "Set Anthropic (Claude) key" \
    set-mistral   "Set Mistral key" \
    status        "Test stored keys" \
    rm-anthropic  "Remove Anthropic key" \
    rm-mistral    "Remove Mistral key" 2>/dev/null) || exit 0
  case $choice in
    set-anthropic) set_key anthropic ;;
    set-mistral)   set_key mistral ;;
    status)        status ;;
    rm-anthropic)  remove_key anthropic ;;
    rm-mistral)    remove_key mistral ;;
    *)             exit 0 ;;
  esac
done
