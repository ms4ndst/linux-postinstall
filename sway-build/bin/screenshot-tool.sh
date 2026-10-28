#!/usr/bin/env bash
# App Menu settings item: pick the default screenshot tool behind the Print
# key. The choice is written to ~/.config/sway/screenshot-tool and read by
# screenshot.sh at Print-key time, so the very next screenshot uses it - no
# sway reload needed. Offers:
#   greenshot - the full Wayland Greenshot
#               (github.com/ms4ndst/greenshot_for_linux): region picker with
#               magnifier, the classic Greenshot annotation editor, tray and
#               save/copy/OCR/printer/upload destinations. Not packaged by
#               any distro - built from source by the repo's post-install
#               scripts (needs the .NET 10 SDK) - so it's only listed when
#               actually installed.
#   classic   - this rice's built-in pipeline: slurp region select, grim
#               capture, satty annotation when installed (else a plain save
#               + wl-clipboard). Always available and always the fallback.
set -u
# sway's exec PATH is bare (/usr/local/bin:/usr/bin) and omits ~/.local/bin,
# where greenshot's packaging/install.sh links the `greenshot` command.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
STATE="$HOME/.config/sway/screenshot-tool"
mkdir -p "$(dirname "$STATE")"

LABELS=(); TOOLS=()
if command -v greenshot >/dev/null 2>&1; then
  LABELS+=("Greenshot  (region picker, full editor, tray)")
  TOOLS+=(greenshot)
fi
LABELS+=("Built-in  (slurp + grim + satty)")
TOOLS+=(classic)

# Pre-select the row that matches the current choice (rofi -selected-row).
SEL=0
CUR="$(cat "$STATE" 2>/dev/null)"
for i in "${!TOOLS[@]}"; do
  [ "${TOOLS[$i]}" = "$CUR" ] && SEL=$i
done

CHOSEN="$(printf '%s\n' "${LABELS[@]}" | rofi -dmenu -i -p "Screenshot Tool" -selected-row "$SEL" -theme ~/.config/rofi/current.rasi)"
[ -z "$CHOSEN" ] && exit 0

for i in "${!LABELS[@]}"; do
  if [ "${LABELS[$i]}" = "$CHOSEN" ]; then
    echo "${TOOLS[$i]}" > "$STATE"
    command -v notify-send >/dev/null && notify-send "Screenshot Tool" "Default set to: $CHOSEN"
    exit 0
  fi
done
