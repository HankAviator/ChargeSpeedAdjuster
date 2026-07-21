#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/csa-status-test.$$
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

mkdir -p "$WORK"
cp "$ROOT/module-status.sh" "$ROOT/module.prop" "$WORK/"

sh "$WORK/module-status.sh" fail boot "boot failed"
grep -Fq 'description=[MODULE INACTIVE] ' "$WORK/module.prop"

sh "$WORK/module-status.sh" fail service "service failed"
sh "$WORK/module-status.sh" pass boot
grep -Fq 'description=[MODULE INACTIVE] ' "$WORK/module.prop"

sh "$WORK/module-status.sh" pass service
if grep -Fq '[MODULE INACTIVE]' "$WORK/module.prop"; then
    echo "inactive marker remained after every failure recovered" >&2
    exit 1
fi

grep -Fq 'description=Remove Xiaomi charging thermal limits with reversible current-stock overlays' \
    "$WORK/module.prop"

echo "module status marker test passed"
