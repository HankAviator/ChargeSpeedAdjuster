#!/system/bin/sh

# Generated profiles are Magisk overlays or bind mounts and disappear on reboot.
# Never delete or restore files in /vendor or /data/vendor/thermal/config here.
echo "ChargeSpeedAdjuster: reboot to remove the thermal overlays and mounts."
