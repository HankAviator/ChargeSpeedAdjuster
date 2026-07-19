#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/csa-v42-test.$$
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

mkdir -p "$WORK"
sh "$ROOT/patch-thermal.sh" \
    "$ROOT/tests/fixtures/v42-input.conf" \
    "$WORK/output.conf" \
    "$WORK/manifest.txt"

cmp "$ROOT/tests/fixtures/v42-expected.conf" "$WORK/output.conf"
grep -Fq 'v4.2 monitor compatibility: trig/clr cleared' "$WORK/manifest.txt"
grep -Fq 'relaxed bounded FCC/SIC curve installed' "$WORK/manifest.txt"
grep -Fq 'wireless charging thermal curve mapped to FCC bands' "$WORK/manifest.txt"

echo "charging thermal patch fixture passed"
