#!/system/bin/sh

# Verify Magisk's visible vendor overlay after magic mounts are established,
# then keep Xiaomi's independent wired and wireless thermal votes removed.

MODDIR=${0%/*}
GENERATED="$MODDIR/runtime/generated"
LOG="$MODDIR/runtime/vendor-overlay.log"
CHARGE_LOG="$MODDIR/runtime/charge-controls.log"
UEVENT_PID="$MODDIR/runtime/charge-uevent.pid"
VENDOR_CONFIG=/vendor/etc
WIRED_REMOVE=/sys/class/qcom-battery/thermal_remove
WIRELESS_REMOVE=/sys/class/qcom-battery/wls_thermal_remove

: > "$LOG"
: > "$CHARGE_LOG"
verified=0
failed=0

for source in "$GENERATED"/thermal-*.conf; do
    [ -f "$source" ] || continue
    filename=${source##*/}
    target="$VENDOR_CONFIG/$filename"

    if [ ! -f "$target" ] || ! cmp -s "$source" "$target"; then
        echo "ChargeSpeedAdjuster: vendor overlay mismatch: $filename" >> "$LOG"
        failed=$((failed + 1))
        continue
    fi

    context=$(ls -Z "$target" 2>/dev/null)
    case "$context" in
        *:system_file:*|*:vendor_configs_file:*) ;;
        *)
            echo "ChargeSpeedAdjuster: unexpected vendor label: $filename: $context" >> "$LOG"
            failed=$((failed + 1))
            continue
            ;;
    esac
    verified=$((verified + 1))
done

if [ "$failed" -ne 0 ] || [ "$verified" -eq 0 ]; then
    echo "ChargeSpeedAdjuster: ERROR: vendor overlay verified=$verified failed=$failed" >> "$LOG"
    exit 1
fi

echo "ChargeSpeedAdjuster: verified $verified generated profiles at /vendor/etc" >> "$LOG"

enable_charge_control() {
    control="$1"
    label="$2"

    if [ ! -e "$control" ]; then
        echo "ChargeSpeedAdjuster: ERROR: missing $label control: $control" >> "$CHARGE_LOG"
        return 1
    fi
    value=$(cat "$control" 2>/dev/null)
    [ "$value" = "1" ] && return 0
    previous_value=$value

    if ! echo 1 > "$control"; then
        echo "ChargeSpeedAdjuster: ERROR: cannot enable $label thermal removal" >> "$CHARGE_LOG"
        return 1
    fi
    value=$(cat "$control" 2>/dev/null)
    if [ "$value" != "1" ]; then
        echo "ChargeSpeedAdjuster: ERROR: $label thermal removal readback=$value" >> "$CHARGE_LOG"
        return 1
    fi

    echo "ChargeSpeedAdjuster: enabled $label charging thermal removal (was $previous_value)" >> "$CHARGE_LOG"
}

if ! enable_charge_control "$WIRED_REMOVE" wired ||
   ! enable_charge_control "$WIRELESS_REMOVE" wireless; then
    exit 1
fi

echo "ChargeSpeedAdjuster: verified wired and wireless driver thermal removal" >> "$CHARGE_LOG"

# Xiaomi resets these firmware properties when a charging path is detached or
# reconfigured. Block on kernel uevents instead of polling or using a timer.
if ! command -v busybox >/dev/null 2>&1; then
    echo "ChargeSpeedAdjuster: ERROR: BusyBox is required for charge uevents" >> "$CHARGE_LOG"
    exit 1
fi

echo $$ > "$UEVENT_PID"
echo "ChargeSpeedAdjuster: listening for charging-path uevents" >> "$CHARGE_LOG"
exec busybox uevent "$MODDIR/charge-event.sh"
