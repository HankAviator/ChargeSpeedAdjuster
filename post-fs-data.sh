#!/system/bin/sh

# Run in Magisk's blocking early-boot stage, after /data is available and
# before Xiaomi's late-start thermal daemon normally reads its profiles.
# Kitsune applies module magic mounts after module post-fs-data scripts. Here,
# edit.sh refreshes their backing files and mounts the writable data cache;
# service.sh verifies the visible /vendor/etc overlay later in the boot.

MODDIR=${0%/*}
LOG="$MODDIR/runtime/post-fs-data.log"

mkdir -p "$MODDIR/runtime"
if ! sh "$MODDIR/edit.sh" boot > "$LOG" 2>&1; then
    echo "ChargeSpeedAdjuster: generation/mount failed; using current stock profiles" >> "$LOG"
fi

exit 0
