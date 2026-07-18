#!/system/bin/sh

MODDIR=${0%/*}
WORKDIR="$MODDIR/temp"
STOCKDIR="$WORKDIR/stock"
ORIGIN_EN="$WORKDIR/origin_en"
ORIGIN_DE="$WORKDIR/origin_de"
EDITED_DE="$WORKDIR/edited_de"
EDITED_EN="$WORKDIR/edited_en"
MOUNTED_STOCK=""

fail() {
    echo "ChargeSpeedAdjuster: $*" >&2
    exit 1
}

cleanup() {
    # Unmount in reverse order. Every target is private to this installer run.
    for target in $MOUNTED_STOCK; do
        umount "$target" >/dev/null 2>&1 || true
    done
    rm -rf "$WORKDIR"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Mount the immutable block device behind a visible partition at a private path.
# Reading /vendor, /odm, or /system directly is unsafe during a module upgrade:
# the old Magisk module remains mounted until reboot and would be copied instead.
mount_stock_partition() {
    name="$1"
    live_mount="$2"
    mount_info="$(
        awk -v wanted="$live_mount" '
            $2 == wanted && ($3 == "erofs" || $3 == "ext4" || $3 == "squashfs") {
                print $1, $3
                exit
            }
        ' /proc/mounts
    )"

    [ -n "$mount_info" ] || fail "stock mount for $live_mount was not found"

    set -- $mount_info
    source_device="$1"
    source_fstype="$2"
    stock_mount="$STOCKDIR/$name"

    mkdir -p "$stock_mount" || fail "cannot create $stock_mount"
    mount -t "$source_fstype" -o ro "$source_device" "$stock_mount" ||
        fail "cannot mount stock $live_mount from $source_device"

    # Prepend so cleanup naturally unmounts in reverse order.
    MOUNTED_STOCK="$stock_mount $MOUNTED_STOCK"
    STOCK_MOUNT="$stock_mount"
}

copy_thermal_configs() {
    source_dir="$1"
    [ -d "$source_dir" ] || return 0

    for source_file in "$source_dir"/thermal-*.conf; do
        [ -f "$source_file" ] || continue
        cp -f "$source_file" "$ORIGIN_EN/" ||
            fail "cannot copy $source_file"
    done
}

rm -rf "$WORKDIR"
rm -rf "$MODDIR/system/vendor/etc"
mkdir -p "$STOCKDIR" "$ORIGIN_EN" "$ORIGIN_DE" "$EDITED_DE" "$EDITED_EN" \
    "$MODDIR/system/vendor/etc" || fail "cannot prepare working directories"

# Read immutable partitions from their underlying block devices, bypassing all
# active Magisk overlays from the currently installed module.
mount_stock_partition vendor /vendor
STOCK_VENDOR="$STOCK_MOUNT"

mount_stock_partition odm /odm
STOCK_ODM="$STOCK_MOUNT"

# On this Xiaomi/Magisk build, /system is a directory in the EROFS root mount.
mount_stock_partition system_root /
STOCK_SYSTEM="$STOCK_MOUNT/system"

# Preserve the original source precedence while making immutable sources clean:
# vendor -> writable Xiaomi data -> odm -> system.
copy_thermal_configs "$STOCK_VENDOR/etc"
copy_thermal_configs "/data/vendor/thermal/config"
copy_thermal_configs "$STOCK_ODM/etc"
copy_thermal_configs "$STOCK_SYSTEM/etc"

[ -n "$(ls -A "$ORIGIN_EN" 2>/dev/null)" ] || fail "no thermal configuration was found"

"$MODDIR/miui-thermal" -d=true -i="$ORIGIN_EN" -o="$ORIGIN_DE" ||
    fail "thermal configuration decryption failed"

"$MODDIR/thermal-bat" "$ORIGIN_DE/" "$EDITED_DE/" ||
    fail "charging thermal patch failed"

# Existing v4.2 behavior. Direct /data modification will be removed separately.
chattr -R -i /data/vendor/thermal/config/ >/dev/null 2>&1 || true
chmod -R 771 /data/vendor/thermal/config || fail "cannot prepare Xiaomi thermal data directory"

"$MODDIR/miui-thermal" -d=false -i="$EDITED_DE" -o="$EDITED_EN" ||
    fail "thermal configuration encryption failed"

cp -rf "$EDITED_EN/." "$MODDIR/system/vendor/etc/" ||
    fail "cannot create module overlay"
cp -rf "$EDITED_EN/." /data/vendor/thermal/config/ ||
    fail "cannot update Xiaomi thermal data"
