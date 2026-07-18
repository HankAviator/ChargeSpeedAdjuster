#!/system/bin/sh

# Schema-aware patcher for decrypted Xiaomi thermal configuration files.
# Only threshold values in validated *-BAT sections are removed. All other
# fields, including SIC proportion/target/ks values, are preserved.

set -u

INPUT=${1:-}
OUTPUT=${2:-}
MANIFEST=${3:-}

[ -n "$INPUT" ] && [ -n "$OUTPUT" ] && [ -n "$MANIFEST" ] || {
    echo "Usage: patch-thermal.sh INPUT OUTPUT MANIFEST" >&2
    exit 2
}

filename=${INPUT##*/}

awk -v filename="$filename" -v manifest="$MANIFEST" '
function reset_section() {
    delete section
    count = 0
    is_bat = 0
    header = ""
    algo_count = 0
    device_count = 0
    trig_count = 0
    clr_count = 0
    trig_index = 0
    clr_index = 0
}

function first_field(line, fields) {
    sub(/\r$/, "", line)
    return split(line, fields, /[\t ]+/) ? fields[1] : ""
}

function flush_section(    i, fields, field, algo, device, status) {
    if (count == 0)
        return

    if (is_bat) {
        for (i = 2; i <= count; i++) {
            field = first_field(section[i], fields)
            if (field == "algo_type") {
                algo_count++
                algo = fields[2]
            } else if (field == "device") {
                device_count++
                device = fields[2]
            } else if (field == "trig") {
                trig_count++
                if (trig_index == 0)
                    trig_index = i
            } else if (field == "clr") {
                clr_count++
                if (clr_index == 0)
                    clr_index = i
            }
        }

        if (algo_count != 1 || device_count != 1 || trig_count < 1 || clr_count < 1 ||
            !((algo == "monitor" && device == "battery") ||
              (algo == "sic" && device == "thermal_fcc_override"))) {
            printf "%s|ERROR|%s|unknown BAT schema algo=%s device=%s trig=%d clr=%d\n",
                filename, header, algo, device, trig_count, clr_count >> manifest
            invalid = 1
        } else {
            # Preserve the field names but remove all threshold values. This is
            # the intended effect of v4.2 without relying on relative lines.
            section[trig_index] = "trig"
            section[clr_index] = "clr"
            printf "%s|PATCHED|%s|algo=%s device=%s trig/clr thresholds removed\n",
                filename, header, algo, device >> manifest
            patched++
        }
    }

    for (i = 1; i <= count; i++)
        print section[i]
}

BEGIN {
    reset_section()
}

/^\[/ {
    flush_section()
    reset_section()
    section[++count] = $0
    header = $0
    clean_header = $0
    sub(/\r$/, "", clean_header)
    is_bat = (clean_header ~ /^\[[^]]*-BAT\]$/)
    next
}

{
    section[++count] = $0
}

END {
    flush_section()
    if (invalid)
        exit 3
    if (patched == 0)
        printf "%s|UNCHANGED|-|no BAT sections\n", filename >> manifest
}
' "$INPUT" > "$OUTPUT"

status=$?
if [ "$status" -ne 0 ]; then
    rm -f "$OUTPUT"
    exit "$status"
fi

exit 0
