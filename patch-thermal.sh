#!/system/bin/sh

# Schema-aware compatibility patcher for decrypted Xiaomi thermal files.
# It reproduces the transformations made by the v4.2 thermal-bat binary for
# the two BAT schemas observed on supported Xiaomi stock profiles.

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
    proportion_count = 0
    trig_index = 0
    clr_index = 0
    proportion_index = 0
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
            } else if (field == "proportion") {
                proportion_count++
                if (proportion_index == 0)
                    proportion_index = i
            }
        }

        if (algo_count != 1 || device_count != 1 || trig_count < 1 || clr_count < 1 ||
            !((algo == "monitor" && device == "battery") ||
              (algo == "sic" && device == "thermal_fcc_override" &&
               proportion_count == 1))) {
            printf "%s|ERROR|%s|unknown BAT schema algo=%s device=%s proportion=%d trig=%d clr=%d\n",
                filename, header, algo, device, proportion_count, trig_count, clr_count >> manifest
            invalid = 1
        } else if (algo == "monitor") {
            # v4.2 clears both threshold lists in monitor/battery sections.
            section[trig_index] = "trig"
            section[clr_index] = "clr"
            printf "%s|PATCHED|%s|v4.2 monitor compatibility: trig/clr cleared\n",
                filename, header >> manifest
            patched++
        } else {
            # v4.2 does not merely clear the SIC thresholds. It replaces the
            # proportion line with an empty trig line, replaces the original
            # trig line with an empty clr line, and leaves the populated clr
            # line in place. Preserve that unusual layout deliberately.
            section[proportion_index] = "trig"
            section[trig_index] = "clr"
            printf "%s|PATCHED|%s|v4.2 SIC compatibility: proportion/trig replaced; stock clr retained\n",
                filename, header >> manifest
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
