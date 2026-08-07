#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/csa-charge-controls-test.$$
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

mkdir -p "$WORK/runtime"
cp "$ROOT/charge-event.sh" "$WORK/charge-event.sh"
cat > "$WORK/module-status.sh" <<'EOF'
#!/bin/sh
exit 0
EOF

WIRED_REMOVE="$WORK/thermal_remove"
WIRELESS_REMOVE="$WORK/wls_thermal_remove"
TEMP_LIMIT_REMOVE="$WORK/remove_temp_limit"
export WIRED_REMOVE WIRELESS_REMOVE TEMP_LIMIT_REMOVE

printf '0\n' > "$WIRED_REMOVE"
printf '0\n' > "$WIRELESS_REMOVE"
printf '0\n' > "$TEMP_LIMIT_REMOVE"

SUBSYSTEM=power_supply POWER_SUPPLY_NAME=usb DEVPATH=/devices/usb \
    sh "$WORK/charge-event.sh"
sleep 4

[ "$(cat "$WIRED_REMOVE")" = 1 ]
[ "$(cat "$WIRELESS_REMOVE")" = 1 ]
[ "$(cat "$TEMP_LIMIT_REMOVE")" = 1 ]

touch "$WORK/disable"
SUBSYSTEM=power_supply POWER_SUPPLY_NAME=usb DEVPATH=/devices/usb \
    sh "$WORK/charge-event.sh"
sleep 4

[ "$(cat "$WIRED_REMOVE")" = 0 ]
[ "$(cat "$WIRELESS_REMOVE")" = 0 ]
[ "$(cat "$TEMP_LIMIT_REMOVE")" = 0 ]

echo "charging control restoration test passed"
