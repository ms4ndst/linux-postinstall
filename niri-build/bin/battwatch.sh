#!/usr/bin/env bash
# Checks the battery once a minute and warns via notify-send (dunst):
#   - plugged in but still draining (charger not keeping up), after two
#     checks in a row, so plugging in/unplugging doesn't cause false alarms
#   - low at 15%, critical at 8% while discharging
# Each warning fires once per event, not every minute; they share one dunst
# stack tag, so a newer warning replaces an older one. Started once from
# sway's config (exec, not exec_always); the flock makes a second copy exit
# at once, without pgrep and its self-matching pitfalls.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/battwatch.lock"
flock -n 9 || exit 0

# The laptop's own battery (BAT*), not a mouse/keyboard battery such as
# hidpp_battery_* (scope=Device).
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[ -n "$BAT" ] || exit 0   # no battery: a desktop, nothing to watch

on_ac() {  # any external supply (barrel charger or USB-C) delivering power
  local s
  for s in /sys/class/power_supply/*; do
    case "$(cat "$s/type" 2>/dev/null)" in
      Mains|USB|USB_C|USB_PD)
        [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && return 0 ;;
    esac
  done
  return 1
}
notify() { notify-send -u "$1" -h string:x-dunst-stack-tag:battwatch "$2" "$3"; }

drain_count=0 warned_drain=0 warned_low=0 warned_crit=0
while :; do
  cap=$(cat "$BAT/capacity" 2>/dev/null || echo 100)
  st=$(cat "$BAT/status" 2>/dev/null)
  if on_ac; then
    warned_low=0 warned_crit=0
    if [ "$st" = Discharging ]; then
      drain_count=$((drain_count + 1))
      if [ "$drain_count" -ge 2 ] && [ "$warned_drain" = 0 ]; then
        notify critical "Charger not keeping up" "Plugged in but the battery is still draining ($cap%). Check the charger's wattage, or connect it directly instead of through a dock."
        warned_drain=1
      fi
    else
      drain_count=0 warned_drain=0
    fi
  else
    drain_count=0 warned_drain=0
    if [ "$st" = Discharging ]; then
      if [ "$cap" -le 8 ] && [ "$warned_crit" = 0 ]; then
        notify critical "Battery critical" "$cap% left - plug in now. The laptop powers off at 5%."
        warned_crit=1 warned_low=1
      elif [ "$cap" -le 15 ] && [ "$warned_low" = 0 ]; then
        notify normal "Battery low" "$cap% left"
        warned_low=1
      fi
    fi
  fi
  sleep 60
done
