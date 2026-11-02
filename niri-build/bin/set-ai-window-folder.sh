#!/usr/bin/env bash
# Sets the folder Mistral Vibe CLI starts in the next time Mod+a launches a
# fresh AI window (see ai-window-toggle.sh). `read -e -i` gives readline
# tab-completion and a pre-filled, editable default - same interactive
# style as set-screensaver-text.sh's own prompt, just editable in place
# instead of typed from scratch.
set -euo pipefail

CONF_DIR="$HOME/.config/ai-window"
WORKDIR_FILE="$CONF_DIR/workdir"
mkdir -p "$CONF_DIR"

CURRENT="$(cat "$WORKDIR_FILE" 2>/dev/null || echo "$HOME")"
echo "AI window startup folder is currently: $CURRENT"
read -r -e -i "$CURRENT" -p "New startup folder (tab-completes): " INPUT
INPUT="${INPUT:-$CURRENT}"
# read -e doesn't expand a leading ~ itself - do it manually before the
# directory check below, same as any other path a user might type here.
INPUT="${INPUT/#\~/$HOME}"

if [ ! -d "$INPUT" ]; then
  echo "Not a directory: $INPUT" >&2
  echo
  echo "Press any key to close..."
  read -r -n 1 -s
  exit 1
fi

echo "$INPUT" > "$WORKDIR_FILE"
echo "AI window will now start in: $INPUT"
echo
echo "Press any key to close..."
read -r -n 1 -s
