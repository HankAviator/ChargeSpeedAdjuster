#!/system/bin/sh

# Reflect persistent runtime failures in Magisk's module description. Each
# component owns one failure file so that one successful stage cannot hide a
# failure reported by another stage.

set -u

MODDIR=${0%/*}
RUNTIME="$MODDIR/runtime"
MODULE_PROP="$MODDIR/module.prop"
MARKER="[MODULE INACTIVE]"
MODE=${1:-}
COMPONENT=${2:-}
REASON=${3:-unspecified failure}

case "$MODE" in
    fail|pass) ;;
    *) exit 2 ;;
esac

case "$COMPONENT" in
    ''|*[!a-z0-9-]*) exit 2 ;;
esac

mkdir -p "$RUNTIME" || exit 1
FAILURE_FILE="$RUNTIME/status-fail-$COMPONENT"

update_description() {
    state="$1"
    current=$(sed -n 's/^description=//p' "$MODULE_PROP" | head -n 1)
    [ -n "$current" ] || return 1

    case "$current" in
        "$MARKER "*) base=${current#"$MARKER "} ;;
        "$MARKER") base="" ;;
        *) base=$current ;;
    esac

    if [ "$state" = inactive ]; then
        desired="$MARKER $base"
    else
        desired=$base
    fi
    [ "$current" = "$desired" ] && return 0

    temporary="$MODULE_PROP.status.$$"
    if ! awk -v description="$desired" '
        BEGIN { replaced = 0 }
        /^description=/ {
            if (!replaced) {
                print "description=" description
                replaced = 1
            }
            next
        }
        { print }
        END {
            if (!replaced)
                print "description=" description
        }
    ' "$MODULE_PROP" > "$temporary"; then
        rm -f "$temporary"
        return 1
    fi

    # Preserve the existing module.prop inode, permissions, and SELinux label.
    cat "$temporary" > "$MODULE_PROP" || {
        rm -f "$temporary"
        return 1
    }
    rm -f "$temporary"
}

if [ "$MODE" = fail ]; then
    printf '%s\n' "$REASON" > "$FAILURE_FILE" || exit 1
    update_description inactive
    exit $?
fi

rm -f "$FAILURE_FILE"
for failure in "$RUNTIME"/status-fail-*; do
    if [ -e "$failure" ]; then
        update_description inactive
        exit $?
    fi
done

update_description active
