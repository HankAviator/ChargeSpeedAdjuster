#!/system/bin/sh

# Generated profiles are bind mounts and disappear automatically on reboot.
# Never delete or restore files in /data/vendor/thermal/config here.
echo "ChargeSpeedAdjuster: reboot to remove the temporary thermal profile mounts."
