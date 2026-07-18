#!/system/bin/sh

# Run in Magisk's blocking early-boot stage, after /data is available and
# before Xiaomi's late-start thermal daemon normally reads its profiles.

MODDIR=${0%/*}
LOG="$MODDIR/runtime/post-fs-data.log"

mkdir -p "$MODDIR/runtime"
if ! sh "$MODDIR/edit.sh" boot > "$LOG" 2>&1; then
    echo "ChargeSpeedAdjuster: generation/mount failed; using current stock profiles" >> "$LOG"
fi

exit 0
