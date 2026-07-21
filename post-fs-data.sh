#!/system/bin/sh

# Run in Magisk's blocking early-boot stage, after /data is available and
# before Xiaomi's late-start thermal daemon normally reads its profiles.
# Kitsune applies module magic mounts after module post-fs-data scripts. Here,
# edit.sh refreshes their backing files and mounts the writable data cache;
# service.sh verifies the visible /vendor/etc overlay later in the boot.

MODDIR=${0%/*}
LOG="$MODDIR/runtime/post-fs-data.log"
STATUS="$MODDIR/module-status.sh"

mkdir -p "$MODDIR/runtime"
sh "$STATUS" fail boot "profile generation and mounting did not complete" || true
if ! sh "$MODDIR/edit.sh" boot > "$LOG" 2>&1; then
    echo "ChargeSpeedAdjuster: generation/mount failed; using current stock profiles" >> "$LOG"
    sh "$STATUS" fail boot "profile generation or mounting failed" || \
        echo "ChargeSpeedAdjuster: ERROR: could not update module inactive status" >> "$LOG"
    exit 0
fi

# Keep the module marked inactive until the late Magisk overlay and charging
# control verification completes. This also exposes a service that never ran.
sh "$STATUS" fail service "late overlay and charging-control verification pending" || \
    echo "ChargeSpeedAdjuster: ERROR: could not set pending service status" >> "$LOG"
sh "$STATUS" pass boot || \
    echo "ChargeSpeedAdjuster: ERROR: could not clear boot failure status" >> "$LOG"

exit 0
