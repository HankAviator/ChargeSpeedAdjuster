#!/system/bin/sh

# Generated profiles are Magisk overlays or bind mounts and disappear on reboot.
# Never delete or restore files in /vendor or /data/vendor/thermal/config here.
MODDIR=${0%/*}
if [ -f "$MODDIR/runtime/charge-uevent.pid" ]; then
    watcher_pid=$(cat "$MODDIR/runtime/charge-uevent.pid" 2>/dev/null)
    case "$watcher_pid" in
        ''|*[!0-9]*) ;;
        *)
            cmdline=$(tr '\000' ' ' < "/proc/$watcher_pid/cmdline" 2>/dev/null)
            case "$cmdline" in
                *busybox*uevent*"$MODDIR/charge-event.sh"*) kill "$watcher_pid" 2>/dev/null ;;
            esac
            ;;
    esac
fi
for control in \
    /sys/class/qcom-battery/thermal_remove \
    /sys/class/qcom-battery/wls_thermal_remove \
    /sys/class/qcom-battery/remove_temp_limit; do
    [ ! -e "$control" ] || echo 0 > "$control" 2>/dev/null
done
echo "ChargeSpeedAdjuster: reboot to remove the thermal overlays and mounts."
