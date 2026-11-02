#!/usr/bin/env bash
# Scratchpad emulation for niri. Niri has no scratchpad or minimize, so this
# uses a dedicated named "scratch" workspace (defined in config.kdl) as the
# hidden stash. Toggle semantics mirror the Sway rice's scratchpad toggles:
#   - no window matching the app-id    -> run the spawn command (summon fresh)
#   - matching window parked on scratch -> move it to the current workspace +
#                                          focus it (show)
#   - matching window visible elsewhere -> move it to scratch, focus stays put
#                                          (hide, without killing it)
# Hiding to another workspace keeps the process alive (and MPRIS/IPC live), so
# a playing cliamp or an in-progress chat is just tucked away, not lost.
#
# Usage: niri-scratch.sh <app-id-regex> <spawn command...>
set -u
command -v jq >/dev/null 2>&1 || { echo "niri-scratch.sh: jq is required" >&2; exit 1; }

APPID_RE="${1:-}"; shift || true
[ -n "$APPID_RE" ] && [ "$#" -ge 1 ] || {
  echo "usage: niri-scratch.sh <app-id-regex> <cmd...>" >&2; exit 1; }

# Debounce. A flaky AI/Copilot key (and some keyboards) emits a single press as
# two events a few ms apart; unguarded, the second invocation races the first
# and cancels the toggle (hide then show = "won't hide") or spawns a duplicate.
# A repeat within DEBOUNCE_MS of the previous run is dropped; an intentional
# re-press (~1s later) still works.
#
# The flock only guards the stamp read-modify-write and is released IMMEDIATELY
# after (fd 9 closed): the toggle may end in `exec "$@"`, and a held lock would
# be inherited by the long-lived spawned app, blocking every later press until
# that app closes.
DEBOUNCE_MS=500
__tag="$(printf '%s' "$APPID_RE" | tr -c 'A-Za-z0-9' '_')"
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/niri-scratch.$__tag.lock"
flock 9
__stamp="${XDG_RUNTIME_DIR:-/tmp}/niri-scratch.$__tag.stamp"
__now=$(date +%s%3N)
if [ -f "$__stamp" ]; then
  __last="$(cat "$__stamp" 2>/dev/null || echo 0)"
  if [ $(( __now - __last )) -lt "$DEBOUNCE_MS" ]; then exec 9>&-; exit 0; fi
fi
echo "$__now" > "$__stamp"
exec 9>&-   # release the lock before any find/spawn/exec below

windows="$(niri msg --json windows 2>/dev/null || echo '[]')"
read -r wid wws < <(printf '%s' "$windows" | jq -r --arg re "$APPID_RE" '
  ([ .[] | select(.app_id != null and (.app_id | test($re))) ] | .[0]) as $w
  | if $w == null then "" else "\($w.id) \($w.workspace_id)" end')

# Not running yet -> summon it. The window-rule in config.kdl opens it floating.
if [ -z "${wid:-}" ]; then
  exec "$@"
fi

# Decide by WHERE the window is relative to the CURRENT workspace, not merely
# whether it sits on "scratch". A window left on another desktop (because you
# switched desktops after summoning it) must be summoned here, not hidden -
# hiding it then would do nothing visible and feel like "the toggle is broken".
# Compare workspace ids (stable across niri's index renumbering); move by the
# focused workspace's index.
read -r cur_id cur_idx < <(niri msg --json workspaces 2>/dev/null \
  | jq -r '.[] | select(.is_focused) | "\(.id) \(.idx)"')

if [ -n "${cur_id:-}" ] && [ "${wws:-}" = "$cur_id" ]; then
  # On the current workspace (visible here) -> hide it. Niri has no scratchpad
  # and a named stash workspace would steal desktop 1 (config workspaces are
  # pinned to the front), so park the window on the trailing empty workspace
  # that niri always keeps at the end of the focused output - past the user's
  # real desktops. Niri then appends a fresh empty, so each hide stacks there.
  __out="$(niri msg --json workspaces 2>/dev/null | jq -r '.[] | select(.is_focused) | .output')"
  __last="$(niri msg --json workspaces 2>/dev/null \
    | jq -r --arg o "$__out" '[ .[] | select(.output==$o) | .idx ] | max')"
  niri msg action move-window-to-workspace --window-id "$wid" --focus false "${__last:-1}" >/dev/null 2>&1 || true
else
  # On another desktop (or stashed at the end) -> bring it here and focus it.
  niri msg action move-window-to-workspace --window-id "$wid" --focus true "${cur_idx:-1}" >/dev/null 2>&1 || true
  niri msg action focus-window --id "$wid" >/dev/null 2>&1 || true
fi
