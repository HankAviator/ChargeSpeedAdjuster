#!/system/bin/sh

# BusyBox uevent supplies kernel-event fields through the environment. Ignore
# every event except USB and wireless power-supply changes.

MODDIR=${0%/*}
CHARGE_LOG="$MODDIR/runtime/charge-controls.log"
WIRED_REMOVE=/sys/class/qcom-battery/thermal_remove
WIRELESS_REMOVE=/sys/class/qcom-battery/wls_thermal_remove

case "$SUBSYSTEM:$POWER_SUPPLY_NAME:$DEVPATH" in
    power_supply:usb:*|power_supply:wireless:*) ;;
    *) exit 0 ;;
esac

restore_controls() {
    [ ! -e "$WIRED_REMOVE" ] || echo 0 > "$WIRED_REMOVE" 2>/dev/null
    [ ! -e "$WIRELESS_REMOVE" ] || echo 0 > "$WIRELESS_REMOVE" 2>/dev/null
}

set_control() {
    control="$1"
    label="$2"
    desired="$3"
    [ -e "$control" ] || return 0

    value=$(cat "$control" 2>/dev/null)
    [ "$value" = "$desired" ] && return 0
    if echo "$desired" > "$control" 2>/dev/null &&
       [ "$(cat "$control" 2>/dev/null)" = "$desired" ]; then
        echo "ChargeSpeedAdjuster: restored $label thermal removal=$desired after $POWER_SUPPLY_NAME uevent (was $value)" >> "$CHARGE_LOG"
    else
        echo "ChargeSpeedAdjuster: ERROR: failed to restore $label thermal removal after $POWER_SUPPLY_NAME uevent" >> "$CHARGE_LOG"
    fi
}

apply_controls() {
    if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ]; then
        restore_controls
        return 0
    fi
    set_control "$WIRED_REMOVE" wired 1
    set_control "$WIRELESS_REMOVE" wireless 0
}

apply_controls

# Some firmware resets happen shortly after the detach notification. These are
# ordinary non-wakeup sleeps and run only after a relevant charging event.
(
    sleep 1
    apply_controls
    sleep 2
    apply_controls
) &

exit 0
