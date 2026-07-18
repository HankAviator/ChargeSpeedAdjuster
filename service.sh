#!/system/bin/sh

# Verify Magisk's visible vendor overlay after magic mounts are established.
# This check is deliberately read-only apart from its module-local log.

MODDIR=${0%/*}
GENERATED="$MODDIR/runtime/generated"
LOG="$MODDIR/runtime/vendor-overlay.log"
VENDOR_CONFIG=/vendor/etc

: > "$LOG"
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
    exit 1
fi

echo "ChargeSpeedAdjuster: verified $verified generated profiles at /vendor/etc" >> "$LOG"
exit 0
