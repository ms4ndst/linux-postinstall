#!/usr/bin/env bash
# Runs the actual dnf upgrade (same fully-interactive flow as before -
# dnf's own "Is this ok [y/N]:" prompt is untouched), then checks whether
# it left the system needing a reboot (kernel/glibc/systemd/etc. update)
# via dnf-utils' `needs-restarting -r` and offers to reboot right away.
# Exit code semantics are the inverse of a typical command: 1 means a
# reboot IS required, 0 means it's not (confirmed against the real tool,
# not assumed from the name) - this rice's polybar update-count widget
# only reports pending package counts, not reboot-required state, so
# without this the only other way to notice is by chance days later.
set -uo pipefail

# dnf5 only: a background updater (GNOME Software via dnf5daemon) may have
# downloaded updates and staged them as an offline "install on reboot"
# transaction. That conflicts with the online upgrade below - dnf warns it
# would be "invalidated" - and with two mechanisms fighting, the updates can
# stay perpetually un-applied, so the bar's update count never clears. Clear
# any stored offline transaction first so this online upgrade is the single
# source of truth. `dnf offline clean` is a safe no-op when nothing is staged.
if command -v dnf >/dev/null 2>&1 && dnf offline --help >/dev/null 2>&1; then
  st="$(sudo dnf offline status 2>/dev/null || true)"
  if [ -n "$st" ] && ! grep -qi 'no offline transaction' <<<"$st"; then
    echo "A background updater had staged updates for offline (reboot) install;"
    echo "clearing that so these updates apply online now..."
    sudo dnf offline clean >/dev/null 2>&1 || true
    echo
  fi
fi

sudo dnf upgrade

# Nudge the bar's update-count widget to re-check now, so the count drops
# to 0 the moment the upgrade finishes instead of staying stale until the
# widget's next 15-min poll. waybar's custom/update module listens on
# SIGRTMIN+9; harmless if waybar isn't running or nothing was installed.
pkill -RTMIN+9 waybar 2>/dev/null || true

echo
if needs-restarting -r >/dev/null 2>&1; then
  echo "No reboot required."
else
  echo "A reboot is required to finish applying these updates."
  read -r -p "Reboot now? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS])
      systemctl reboot
      ;;
    *)
      echo "Not rebooting - remember to reboot later to finish applying updates."
      ;;
  esac
fi
read -r -p "Press Enter to close..." _
