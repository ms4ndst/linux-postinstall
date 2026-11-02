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
sudo dnf upgrade

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
