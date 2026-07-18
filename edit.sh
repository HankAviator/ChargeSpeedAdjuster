#!/system/bin/sh

# Generate validated thermal profiles from the device's current sources.
#
# Usage:
#   edit.sh generate  Generate/cache profiles without mounting them.
#   edit.sh boot      Generate if required, then bind-mount the cached profiles.

set -u

MODDIR=${0%/*}
MODE=${1:-generate}
RUNTIME="$MODDIR/runtime"
GENERATED="$RUNTIME/generated"
SIGNATURE_FILE="$RUNTIME/source.signature"
MANIFEST_FILE="$RUNTIME/patch-manifest.txt"
SOURCE_MANIFEST_FILE="$RUNTIME/source-manifest.txt"
LOG_FILE="$RUNTIME/generator.log"
DATA_CONFIG=/data/vendor/thermal/config
PATCH_VERSION=2
MOUNTED_STOCK=""
BOUND_TARGETS=""
TMPDIR=""

mkdir -p "$RUNTIME" || exit 1

log() {
    message="ChargeSpeedAdjuster: $*"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

fail() {
    log "ERROR: $*"
    return 1
}

cleanup() {
    # Undo partial bind mounts from this invocation only.
    for target in $BOUND_TARGETS; do
        umount "$target" >/dev/null 2>&1 || true
    done

    # Stock mounts are private read-only views created by this invocation.
    for target in $MOUNTED_STOCK; do
        umount "$target" >/dev/null 2>&1 || true
    done

    [ -z "$TMPDIR" ] || rm -rf "$TMPDIR"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mount_stock_partition() {
    name="$1"
    live_mount="$2"
    mount_info="$({
        awk -v wanted="$live_mount" '
            $2 == wanted && ($3 == "erofs" || $3 == "ext4" || $3 == "squashfs") {
                print $1, $3
                exit
            }
        ' /proc/mounts
    })"

    [ -n "$mount_info" ] || fail "stock mount for $live_mount was not found" || return 1
    set -- $mount_info
    source_device="$1"
    source_fstype="$2"
    stock_mount="$TMPDIR/stock/$name"

    mkdir -p "$stock_mount" || return 1
    mount -o ro -t "$source_fstype" "$source_device" "$stock_mount" || {
        fail "cannot mount stock $live_mount from $source_device"
        return 1
    }

    MOUNTED_STOCK="$stock_mount $MOUNTED_STOCK"
    STOCK_MOUNT="$stock_mount"
}

select_clean_source() {
    filename="$1"

    # The writable Xiaomi profiles on this device are derived primarily from
    # ODM. Preserve that relationship while keeping every source separate.
    if [ -f "$STOCK_ODM/etc/$filename" ]; then
        SELECTED_LAYER=odm
        SELECTED_SOURCE="$STOCK_ODM/etc/$filename"
        return 0
    fi
    if [ -f "$STOCK_VENDOR/etc/$filename" ]; then
        SELECTED_LAYER=vendor
        SELECTED_SOURCE="$STOCK_VENDOR/etc/$filename"
        return 0
    fi
    if [ -f "$STOCK_SYSTEM/etc/$filename" ]; then
        SELECTED_LAYER=system
        SELECTED_SOURCE="$STOCK_SYSTEM/etc/$filename"
        return 0
    fi

    # A data-only profile has no immutable counterpart. It is still a current
    # device source, not a module backup, so it may be used as a last resort.
    if [ -f "$DATA_CONFIG/$filename" ]; then
        SELECTED_LAYER=data
        SELECTED_SOURCE="$DATA_CONFIG/$filename"
        return 0
    fi

    return 1
}

prepare_sources() {
    mkdir -p "$TMPDIR/stock" "$TMPDIR/origin_en" || return 1

    mount_stock_partition vendor /vendor || return 1
    STOCK_VENDOR="$STOCK_MOUNT"

    mount_stock_partition odm /odm || return 1
    STOCK_ODM="$STOCK_MOUNT"

    # On this Xiaomi/Magisk build, /system is a directory in the root EROFS.
    mount_stock_partition system_root / || return 1
    STOCK_SYSTEM="$STOCK_MOUNT/system"

    odm_count=$(find "$STOCK_ODM/etc" -maxdepth 1 -type f -name 'thermal-*.conf' 2>/dev/null | wc -l)
    vendor_count=$(find "$STOCK_VENDOR/etc" -maxdepth 1 -type f -name 'thermal-*.conf' 2>/dev/null | wc -l)
    system_count=$(find "$STOCK_SYSTEM/etc" -maxdepth 1 -type f -name 'thermal-*.conf' 2>/dev/null | wc -l)
    log "clean immutable sources: odm=$odm_count vendor=$vendor_count system=$system_count"

    : > "$TMPDIR/source-manifest.txt"
    source_count=0

    for target in "$DATA_CONFIG"/thermal-*.conf; do
        [ -f "$target" ] || continue
        filename=${target##*/}

        if ! select_clean_source "$filename"; then
            fail "no current source was found for $filename"
            return 1
        fi

        cp -f "$SELECTED_SOURCE" "$TMPDIR/origin_en/$filename" || return 1
        digest=$(sha256sum "$SELECTED_SOURCE" | awk '{print $1}') || return 1
        echo "$filename|$SELECTED_LAYER|$digest" >> "$TMPDIR/source-manifest.txt"
        source_count=$((source_count + 1))
    done

    [ "$source_count" -gt 0 ] || {
        fail "no live Xiaomi thermal profiles were found"
        return 1
    }

    sort -o "$TMPDIR/source-manifest.txt" "$TMPDIR/source-manifest.txt"

    {
        echo "patch_version=$PATCH_VERSION"
        echo "fingerprint=$(getprop ro.build.fingerprint)"
        echo "vbmeta=$(getprop ro.boot.vbmeta.digest)"
        echo "converter=$(sha256sum "$MODDIR/miui-thermal" | awk '{print $1}')"
        echo "patcher=$(sha256sum "$MODDIR/patch-thermal.sh" | awk '{print $1}')"
        cat "$TMPDIR/source-manifest.txt"
    } > "$TMPDIR/signature-input.txt"

    sha256sum "$TMPDIR/signature-input.txt" | awk '{print $1}' > "$TMPDIR/source.signature"
}

cache_is_current() {
    [ -f "$SIGNATURE_FILE" ] || return 1
    [ -d "$GENERATED" ] || return 1
    cmp -s "$SIGNATURE_FILE" "$TMPDIR/source.signature" || return 1

    expected=$(wc -l < "$TMPDIR/source-manifest.txt")
    actual=0
    for file in "$GENERATED"/thermal-*.conf; do
        [ -f "$file" ] || continue
        actual=$((actual + 1))
    done
    [ "$expected" -eq "$actual" ] || return 1

    while IFS='|' read -r filename _layer _digest; do
        [ -n "$filename" ] || continue
        [ -s "$GENERATED/$filename" ] || return 1
    done < "$TMPDIR/source-manifest.txt"

    return 0
}

generate_profiles() {
    mkdir -p \
        "$TMPDIR/origin_de" \
        "$TMPDIR/origin_reencrypted" \
        "$TMPDIR/edited_de" \
        "$TMPDIR/edited_en" \
        "$TMPDIR/roundtrip" || return 1

    chmod 700 "$TMPDIR/origin_de" "$TMPDIR/origin_reencrypted" "$TMPDIR/edited_de" \
        "$TMPDIR/edited_en" "$TMPDIR/roundtrip"

    "$MODDIR/miui-thermal" -d=true -i="$TMPDIR/origin_en" -o="$TMPDIR/origin_de" || {
        fail "thermal configuration decryption failed"
        return 1
    }

    # Xiaomi's AES-CBC format is deterministic. Re-encrypting untouched stock
    # must reproduce every source byte-for-byte before any patch is attempted.
    "$MODDIR/miui-thermal" -d=false -i="$TMPDIR/origin_de" -o="$TMPDIR/origin_reencrypted" || {
        fail "stock crypto compatibility check failed"
        return 1
    }
    for source in "$TMPDIR/origin_en"/thermal-*.conf; do
        [ -f "$source" ] || continue
        filename=${source##*/}
        cmp -s "$source" "$TMPDIR/origin_reencrypted/$filename" || {
            fail "stock crypto mismatch for $filename"
            return 1
        }
    done

    : > "$TMPDIR/patch-manifest.txt"
    for input in "$TMPDIR/origin_de"/thermal-*.conf; do
        [ -f "$input" ] || continue
        filename=${input##*/}
        "$MODDIR/patch-thermal.sh" \
            "$input" \
            "$TMPDIR/edited_de/$filename" \
            "$TMPDIR/patch-manifest.txt" || {
            fail "schema validation failed for $filename"
            return 1
        }
    done

    "$MODDIR/miui-thermal" -d=false -i="$TMPDIR/edited_de" -o="$TMPDIR/edited_en" || {
        fail "thermal configuration encryption failed"
        return 1
    }

    # Prove that every encrypted output decrypts to the exact patched text.
    "$MODDIR/miui-thermal" -d=true -i="$TMPDIR/edited_en" -o="$TMPDIR/roundtrip" || {
        fail "encrypted output round-trip failed"
        return 1
    }

    expected=$(wc -l < "$TMPDIR/source-manifest.txt")
    verified=0
    for input in "$TMPDIR/edited_de"/thermal-*.conf; do
        [ -f "$input" ] || continue
        filename=${input##*/}
        [ -s "$TMPDIR/edited_en/$filename" ] || {
            fail "missing encrypted output for $filename"
            return 1
        }
        cmp -s "$input" "$TMPDIR/roundtrip/$filename" || {
            fail "round-trip mismatch for $filename"
            return 1
        }
        verified=$((verified + 1))
    done
    [ "$expected" -eq "$verified" ] || {
        fail "profile count mismatch: expected $expected, verified $verified"
        return 1
    }

    rm -rf "$RUNTIME/generated.new" "$RUNTIME/generated.old"
    mv "$TMPDIR/edited_en" "$RUNTIME/generated.new" || return 1

    if [ -d "$GENERATED" ]; then
        mv "$GENERATED" "$RUNTIME/generated.old" || return 1
    fi

    if ! mv "$RUNTIME/generated.new" "$GENERATED"; then
        [ ! -d "$RUNTIME/generated.old" ] || mv "$RUNTIME/generated.old" "$GENERATED"
        return 1
    fi

    rm -rf "$RUNTIME/generated.old"
    cp -f "$TMPDIR/source.signature" "$SIGNATURE_FILE.new" || return 1
    mv -f "$SIGNATURE_FILE.new" "$SIGNATURE_FILE" || return 1
    cp -f "$TMPDIR/patch-manifest.txt" "$MANIFEST_FILE.new" || return 1
    mv -f "$MANIFEST_FILE.new" "$MANIFEST_FILE" || return 1
    cp -f "$TMPDIR/source-manifest.txt" "$SOURCE_MANIFEST_FILE.new" || return 1
    mv -f "$SOURCE_MANIFEST_FILE.new" "$SOURCE_MANIFEST_FILE" || return 1

    chmod 700 "$RUNTIME" "$GENERATED"
    chmod 600 "$SIGNATURE_FILE" "$MANIFEST_FILE" "$SOURCE_MANIFEST_FILE"
    chmod 644 "$GENERATED"/thermal-*.conf
    log "generated and verified $verified profiles from current device sources"
    for layer in odm vendor system data; do
        count=$(awk -F '|' -v wanted="$layer" '$2 == wanted { count++ } END { print count + 0 }' "$SOURCE_MANIFEST_FILE")
        [ "$count" -eq 0 ] || log "source layer $layer: $count profiles"
    done
}

bind_profiles() {
    boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    if [ -n "$boot_id" ] && [ -f "$RUNTIME/mounted.boot-id" ] && \
        [ "$(cat "$RUNTIME/mounted.boot-id")" = "$boot_id" ]; then
        expected=0
        mounted=0
        for source in "$GENERATED"/thermal-*.conf; do
            [ -f "$source" ] || continue
            expected=$((expected + 1))
            target="$DATA_CONFIG/${source##*/}"
            if awk -v wanted="$target" '$2 == wanted { found=1 } END { exit !found }' /proc/mounts; then
                mounted=$((mounted + 1))
            fi
        done
        if [ "$expected" -gt 0 ] && [ "$mounted" -eq "$expected" ]; then
            log "verified $mounted profiles already mounted for this boot"
            return 0
        fi
        fail "mount marker is inconsistent: expected $expected profiles, found $mounted"
        return 1
    fi

    mounted=0
    for source in "$GENERATED"/thermal-*.conf; do
        [ -f "$source" ] || continue
        filename=${source##*/}
        target="$DATA_CONFIG/$filename"
        [ -f "$target" ] || {
            fail "bind target disappeared: $target"
            return 1
        }

        if awk -v wanted="$target" '$2 == wanted { found=1 } END { exit !found }' /proc/mounts; then
            fail "refusing to cover an existing mount at $target"
            return 1
        fi

        mount -o bind "$source" "$target" || {
            fail "cannot bind $source over $target"
            return 1
        }
        BOUND_TARGETS="$target $BOUND_TARGETS"

        # Label through the data-side mountpoint. This works even when the
        # module directory itself does not permit setting the vendor label.
        chcon u:object_r:thermal_data_file:s0 "$target" >/dev/null 2>&1 || {
            fail "cannot label the mounted profile at $target"
            return 1
        }
        context=$(ls -Z "$target" 2>/dev/null)
        case "$context" in
            *:thermal_data_file:*) ;;
            *) fail "unexpected SELinux label after mounting $target"; return 1 ;;
        esac

        mounted=$((mounted + 1))
    done

    [ "$mounted" -gt 0 ] || {
        fail "no generated profiles were mounted"
        return 1
    }

    # The mounts are now committed; cleanup must not undo them.
    BOUND_TARGETS=""
    echo "$boot_id" > "$RUNTIME/mounted.boot-id"
    chmod 600 "$RUNTIME/mounted.boot-id"
    log "bind-mounted $mounted validated profiles before thermal service startup"
}

case "$MODE" in
    generate|boot) ;;
    *) fail "unknown mode: $MODE"; exit 2 ;;
esac

: > "$LOG_FILE"
TMPDIR="$RUNTIME/work.$$"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR" || exit 1

if ! prepare_sources; then
    exit 1
fi

if cache_is_current; then
    log "cached profiles match the current stock source signature"
else
    log "source change detected; regenerating profiles"
    if ! generate_profiles; then
        log "generation failed; leaving current stock files unmounted"
        exit 1
    fi
fi

if [ "$MODE" = boot ]; then
    if ! bind_profiles; then
        log "mounting failed; leaving current stock files unmounted"
        exit 1
    fi
fi

exit 0
