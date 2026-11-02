#!/usr/bin/env python3
"""Calendar reminder daemon.

Polls every enabled evolution-data-server calendar for VALARM reminders
that just became due and fires a themed dunst notification for each,
instead of evolution-alarm-notify's own GTK popup window - which is fixed
to Catppuccin Mocha regardless of the active desktop theme (GTK apps in
this rice aren't part of the per-theme switcher the way polybar/rofi/
kitty/starship/dunst are - building 21 full GTK themes to cover it was
judged out of proportion to the payoff), and whose window this rice's own
setup disables (autostart Hidden=true + `systemctl --user mask
evolution-alarm-notify.service`) so it never appears at all. Routing
through dunst instead means calendar reminders automatically pick up
whichever theme is currently active (dunst is themed the same way as
kitty/rofi/starship) and automatically respect Do Not Disturb (dunst's own
pause state already suppresses every notify-send call while DND is on -
no separate gsettings toggle needed the way the old popup required).

Uses the real EDataServer/ECal GObject Introspection API (the same one
evolution-alarm-notify itself is built on) to enumerate calendars and
expand recurring events correctly, rather than re-parsing raw .ics data -
confirmed working against this machine's real calendars (Google, Exchange/
visma.com, local) before writing this, including reading each VALARM's
actual TRIGGER duration (e.g. "10 minutes before"), not a hardcoded lead
time, so a reminder set for a specific event keeps firing at the time that
event's own alarm actually specifies.
"""
import gi
gi.require_version("EDataServer", "1.2")
gi.require_version("ECal", "2.0")
gi.require_version("ICalGLib", "3.0")
from gi.repository import EDataServer, ECal, ICalGLib

import json
import os
import subprocess
import sys
import time

def _local_timezone():
    # Fallback for a genuinely floating ICalTime (get_timezone() returns
    # None) - see floating_safe_as_timet() below for the actual bug this
    # works around. Read /etc/localtime's symlink target rather than
    # hardcoding a zone name, so this keeps working if the system's
    # timezone ever changes.
    try:
        path = os.path.realpath("/etc/localtime")
        name = path.split("/usr/share/zoneinfo/", 1)[1]
        tz = ICalGLib.Timezone.get_builtin_timezone(name)
        if tz:
            return tz
    except Exception:
        pass
    return ICalGLib.Timezone.get_utc_timezone()

LOCAL_TZ = _local_timezone()

def floating_safe_as_timet(ical_time):
    # ICalTime.as_timet() (no zone argument) ALWAYS interprets the wall-
    # clock fields as UTC - confirmed directly against a real event: its
    # DTSTART correctly carried an attached "Europe/Stockholm" tzid
    # (get_timezone() was NOT None) and get_hour()/get_minute() correctly
    # read 13:40, yet as_timet() still returned 15:40 CEST. It simply
    # never consults the attached zone. as_timet_with_zone(that same
    # attached zone) gives the correct 13:40. This had gone unnoticed
    # because Exchange/Google meeting invites almost always store DTSTART
    # in real UTC already (is_utc() true), where the "always assume UTC"
    # behavior happens to be correct by coincidence - it only breaks on
    # events with an explicit local zone or a genuinely floating time
    # (e.g. a quick event added via a calendar app's own popup), silently
    # shifting every alarm by the local UTC offset (here, +2h/CEST).
    if ical_time is None:
        return None
    if ical_time.is_utc():
        return ical_time.as_timet()
    tz = ical_time.get_timezone() or LOCAL_TZ
    return ical_time.as_timet_with_zone(tz)

STATE_FILE = os.path.expanduser("~/.cache/calendar-reminder-notified.json")
POLL_INTERVAL = 30  # seconds between polls
LOOKBACK = 120  # seconds - catches alarms that became due since the last poll, with margin
INSTANCE_WINDOW = 14 * 24 * 3600  # how far ahead to expand recurring instances (14 days)
# How far back generate_instances_sync's own query range has to start -
# separate from LOOKBACK (which only gates which alarms count as "due" once
# instances are already found). Confirmed live: at least some real events
# (e.g. modified occurrences of a recurring meeting) silently vanish from
# generate_instances_sync's results when the query's start time is within
# roughly an hour of the event's own start - passed LOOKBACK's 120s here
# instead, the query missed real alarms every single time regardless of
# polling health (reproduced directly against this account's own real
# calendar data, not assumed). A query starting a full day back reliably
# finds them; LOOKBACK still does the actual narrow due/not-due filtering
# below, so this only widens what gets *considered*, not what fires.
QUERY_LOOKBACK = 24 * 3600
STATE_MAX_AGE = 3 * 24 * 3600  # prune notified-keys older than this

def load_notified():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def save_notified(notified):
    now = time.time()
    pruned = {k: v for k, v in notified.items() if now - v < STATE_MAX_AGE}
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(pruned, f)
    except Exception:
        pass
    return pruned

def notify(summary, location, start_ts):
    when = time.strftime("%H:%M", time.localtime(start_ts))
    body = when if not location else f"{when} — {location}"
    # -t 0 (explicit infinite expire-time) forces dunst to never
    # auto-dismiss this, independent of urgency - confirmed live: it stays
    # displayed indefinitely with plain -u normal too. Deliberately NOT
    # using -u critical for this: this rice's dunstrc hardcodes
    # urgency_critical to red text/frame in every theme, which would make
    # calendar reminders the one thing that ignores whichever theme is
    # actually active. dunst has no clickable close button regardless of
    # urgency - dismissal is still just clicking the notification (dunst's
    # own default left-click action), same as any other notification.
    subprocess.run(
        [
            "notify-send", "-a", "Calendar", "-i", "x-office-calendar",
            "-u", "normal", "-t", "0", "-h", "string:x-dunst-stack-tag:calendar-reminder",
            summary, body,
        ],
        check=False,
    )

def find_due(sources, now):
    due = []
    window_end = now + INSTANCE_WINDOW

    def instance_cb(icalcomp, instance_start, instance_end, user_data, cancellable):
        start_ts = floating_safe_as_timet(instance_start)
        if start_ts is None:
            return True
        uid = icalcomp.get_uid()
        idx = 0
        va = icalcomp.get_first_component(ICalGLib.ComponentKind.VALARM_COMPONENT)
        while va:
            trigger_prop = va.get_first_property(ICalGLib.PropertyKind.TRIGGER_PROPERTY)
            if trigger_prop:
                trig = trigger_prop.get_trigger()
                dur = trig.get_duration()
                if dur:
                    notify_at = start_ts + dur.as_int()
                    if now - LOOKBACK <= notify_at <= now:
                        key = f"{uid}:{int(start_ts)}:{idx}"
                        summary_prop = icalcomp.get_first_property(ICalGLib.PropertyKind.SUMMARY_PROPERTY)
                        location_prop = icalcomp.get_first_property(ICalGLib.PropertyKind.LOCATION_PROPERTY)
                        due.append((
                            key,
                            summary_prop.get_summary() if summary_prop else "(untitled event)",
                            location_prop.get_location() if location_prop else None,
                            start_ts,
                        ))
            idx += 1
            va = icalcomp.get_next_component(ICalGLib.ComponentKind.VALARM_COMPONENT)
        return True

    for src in sources:
        try:
            client = ECal.Client.connect_sync(src, ECal.ClientSourceType.EVENTS, 5, None)
            client.generate_instances_sync(int(now - QUERY_LOOKBACK), int(window_end), None, instance_cb, None)
        except Exception as e:
            print(f"calendar-reminder-daemon: skipping {src.get_display_name()}: {e}", file=sys.stderr)

    return due

def main():
    notified = load_notified()
    while True:
        try:
            registry = EDataServer.SourceRegistry.new_sync(None)
            sources = [
                s for s in registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)
                if s.get_enabled()
            ]
            now = time.time()
            due = find_due(sources, now)
            fired = False
            for key, summary, location, start_ts in due:
                if key in notified:
                    continue
                notify(summary, location, start_ts)
                notified[key] = now
                fired = True
            if fired:
                notified = save_notified(notified)
        except Exception as e:
            print(f"calendar-reminder-daemon: error: {e}", file=sys.stderr)
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
