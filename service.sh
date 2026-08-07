#!/system/bin/sh

# Verify Magisk's visible vendor overlay after magic mounts are established,
# then keep Xiaomi's independent wired and wireless thermal-removal controls
# enabled. The mapped wireless monitor still applies its mitigation states.

MODDIR=${0%/*}
GENERATED="$MODDIR/runtime/generated"
LOG="$MODDIR/runtime/vendor-overlay.log"
CHARGE_LOG="$MODDIR/runtime/charge-controls.log"
UEVENT_PID="$MODDIR/runtime/charge-uevent.pid"
STATUS="$MODDIR/module-status.sh"
VENDOR_CONFIG=/vendor/etc
WIRED_REMOVE=${WIRED_REMOVE:-/sys/class/qcom-battery/thermal_remove}
WIRELESS_REMOVE=${WIRELESS_REMOVE:-/sys/class/qcom-battery/wls_thermal_remove}

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
    sh "$STATUS" fail service "vendor overlay verification failed" || true
    exit 1
fi

echo "ChargeSpeedAdjuster: verified $verified generated profiles at /vendor/etc" >> "$LOG"

set_charge_control() {
    control="$1"
    label="$2"
    desired="$3"

    if [ ! -e "$control" ]; then
        echo "ChargeSpeedAdjuster: ERROR: missing $label control: $control" >> "$CHARGE_LOG"
        return 1
    fi
    value=$(cat "$control" 2>/dev/null)
    [ "$value" = "$desired" ] && return 0
    previous_value=$value

    if ! echo "$desired" > "$control"; then
        echo "ChargeSpeedAdjuster: ERROR: cannot set $label thermal removal=$desired" >> "$CHARGE_LOG"
        return 1
    fi
    value=$(cat "$control" 2>/dev/null)
    if [ "$value" != "$desired" ]; then
        echo "ChargeSpeedAdjuster: ERROR: $label thermal removal readback=$value expected=$desired" >> "$CHARGE_LOG"
        return 1
    fi

    echo "ChargeSpeedAdjuster: set $label charging thermal removal=$desired (was $previous_value)" >> "$CHARGE_LOG"
}

if ! set_charge_control "$WIRED_REMOVE" wired 1 ||
   ! set_charge_control "$WIRELESS_REMOVE" wireless 1; then
    sh "$STATUS" fail service "charging thermal-removal control setup failed" || true
    exit 1
fi

echo "ChargeSpeedAdjuster: verified wired and wireless thermal removal" >> "$CHARGE_LOG"

# Xiaomi resets these firmware properties when a charging path is detached or
# reconfigured. Block on kernel uevents instead of polling or using a timer.
if ! command -v busybox >/dev/null 2>&1; then
    echo "ChargeSpeedAdjuster: ERROR: BusyBox is required for charge uevents" >> "$CHARGE_LOG"
    sh "$STATUS" fail service "BusyBox charging-event listener is unavailable" || true
    exit 1
fi

if ! sh "$STATUS" pass event ||
   ! sh "$STATUS" pass service; then
    echo "ChargeSpeedAdjuster: ERROR: could not clear module inactive status" >> "$CHARGE_LOG"
    exit 1
fi

echo $$ > "$UEVENT_PID"
echo "ChargeSpeedAdjuster: listening for charging-path uevents" >> "$CHARGE_LOG"
exec busybox uevent "$MODDIR/charge-event.sh"
