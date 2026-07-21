SKIPUNZIP=0
REPLACE=""

ui_print " "
ui_print "*******************"
ui_print "- Device information"
ui_print "- SDK: $(getprop ro.build.version.sdk)"
ui_print "- Manufacturer: $(getprop ro.fota.oem)"
ui_print "- Device codename: $(getprop ro.product.device)"
ui_print "- Android version: Android $(getprop ro.build.version.release)"
ui_print "*******************"

if [ "$(getprop ro.fota.oem)" != "Xiaomi" ]; then
    abort "This module supports Xiaomi devices only."
fi

if [ ! -d /data/vendor/thermal/config ]; then
    abort "Xiaomi thermal profile directory was not found."
fi

ui_print "- Installing the current-stock thermal profile generator"
ui_print "- Stock and /data files will not be overwritten"
ui_print "- Generated profiles will overlay /vendor/etc and mount over Xiaomi's /data cache"
ui_print "- Battery limits are removed; FCC and wireless charging use relaxed mapped curves"
ui_print "- An empty Xiaomi writable profile directory is supported"
ui_print "- An OS/profile change will force regeneration from the new sources"

# Remove only obsolete modules with different IDs. Never delete ChargeSA while
# Magisk is staging an update of ChargeSA itself.
rm -rf /data/adb/modules/HeZheng

# Rebuild any previous conventional overlay from the current immutable stock.
rm -rf "$MODPATH/system"
rm -rf "$MODPATH/runtime"
rm -f "$MODPATH/thermal-bat"

chmod 755 \
    "$MODPATH/charge-event.sh" \
    "$MODPATH/edit.sh" \
    "$MODPATH/module-status.sh" \
    "$MODPATH/patch-thermal.sh" \
    "$MODPATH/post-fs-data.sh" \
    "$MODPATH/service.sh" \
    "$MODPATH/uninstall.sh" \
    "$MODPATH/miui-thermal"

# Validate compatibility and prepare the first cache now. No profiles are
# mounted during installation; post-fs-data.sh applies them after reboot.
if ! sh "$MODPATH/edit.sh" generate; then
    abort "Failed to generate validated thermal profiles from current stock."
fi

ui_print "- Profile generation, charging patch, vendor-overlay staging, and crypto validation succeeded"
ui_print "- Runtime failures will mark the module description with [MODULE INACTIVE]"
ui_print "- Reboot to apply the reversible vendor overlay and data-directory mount"
