#!/usr/bin/env bash
# Guard-and-launch wrapper for calendar-reminder-daemon.py, kept as its own
# script rather than inlined in sway's exec line. Inlining it as
# `sh -c 'pgrep -f calendar-reminder-daemon.py >/dev/null || python3
# ~/.local/bin/calendar-reminder-daemon.py'` looked fine but never actually
# worked: pgrep -f matches against a process's FULL command line, and that
# inline sh -c command's own argv literally contains the text
# "calendar-reminder-daemon.py" (twice - once in the pgrep pattern, once in
# the fallback command) - so the guard matched itself every single time,
# always finding a "match" and never falling through to actually launch the
# daemon. Confirmed directly: a real reboot left the daemon never running
# at all, silently, no error anywhere - the exact same shape of bug as the
# xdg-desktop-portal duplication guard, just self-matching instead of
# duplicating. Kept as a separate file so pgrep -f's search text has no
# reason to appear in the checking process's own command line at all.
pgrep -f calendar-reminder-daemon.py >/dev/null || exec python3 ~/.local/bin/calendar-reminder-daemon.py
