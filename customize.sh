SKIPUNZIP=0
REPLACE=""
MODDIR=${0%/*}
echo " "
echo "*******************"
echo "- Device information"
echo "- SDK: $(getprop ro.build.version.sdk)"
echo "- Manufacturer: $(getprop ro.fota.oem)"
echo "- Device codename: $(getprop ro.product.device)"
echo "- Android version: Android $(getprop ro.build.version.release)"
echo "*******************"

# Detect a supported charging-current control node.
if [ ! -f /sys/class/power_supply/battery/constant_charge_current ] && [ ! -f /sys/class/power_supply/battery/constant_charge_current_max ] && [ ! -f /sys/class/power_supply/battery/fast_charge_current ];
then
  echo "No supported charging-current control node was found."
  echo "Find the correct node for this device and update the script manually."
else
  echo "A supported charging-current control node was found."
fi

# Remove obsolete module directories.
rm -rf "/data/adb/modules/ChargeSA/"
rm -rf "/data/adb/modules/HeZheng/"

# Check whether the battery capacity node is available.
if [ ! -f "/sys/class/power_supply/battery/capacity" ]; then
  echo "Step-based charging control is unavailable; unrestricted charging remains available."
else
  echo "Step-based and unrestricted charging controls are available."
fi
sleep 1
echo "Please read the following information carefully."
echo "-------------------------------------"
echo "Version 4.2 information:"
echo "Charging control is intended to work with the screen on or off."
echo "Thermal profiles are generated from this device's own configuration."
echo "Only charging-related thermal controls are removed."
echo "Previously modified thermal profiles may be replaced by the generated profiles."
echo "Vendor-modified ROMs may not be supported."
echo "AOSP-like ROMs are probably not supported."
echo "KernelSU support is experimental."
echo "Thanks to everyone whose work contributed to this module."
echo "@HeZheng (core logic), @shadow3 (thermal modification), @Dudusiji (thermal decryption)"
echo "-------------------------------------"
sleep 3
# Restrict installation to Xiaomi devices.
var_device="`getprop ro.fota.oem`"
if [ "$var_device" != "Xiaomi" ]; then
  abort "This module supports Xiaomi devices only."
else
  echo "Installing..."
  sleep 1
  # Make the bundled patching tools executable.
  chmod a+x $MODPATH/miui-thermal
  chmod a+x $MODPATH/thermal-bat
  if ! sh "$MODPATH/edit.sh"; then
    abort "Failed to generate the charging thermal profiles."
  fi
  echo "Charging thermal controls were removed successfully. Reboot to apply the module."
fi
