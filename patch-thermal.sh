#!/system/bin/sh

# Schema-aware charging thermal patcher for decrypted Xiaomi thermal files.
# It retains v4.2 compatibility for the battery monitor, installs a relaxed
# but bounded FCC/SIC curve, and disables Xiaomi's separate wireless-charge
# temperature threshold controller.

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
    is_bat_header = 0
    header = ""
    algo_count = 0
    device_count = 0
    trig_count = 0
    clr_count = 0
    proportion_count = 0
    target_count = 0
    ks_count = 0
    ki_count = 0
    kc_count = 0
    max_count = 0
    min_count = 0
    trig_index = 0
    clr_index = 0
    proportion_index = 0
    target_index = 0
    ks_index = 0
    ki_index = 0
    kc_index = 0
    max_index = 0
    min_index = 0
}

function first_field(line, fields) {
    sub(/\r$/, "", line)
    return split(line, fields, /[\t ]+/) ? fields[1] : ""
}

function flush_section(    i, fields, field, algo, device, schema) {
    if (count == 0)
        return

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
        } else if (field == "target") {
            target_count++
            if (target_index == 0)
                target_index = i
        } else if (field == "ks") {
            ks_count++
            if (ks_index == 0)
                ks_index = i
        } else if (field == "ki") {
            ki_count++
            if (ki_index == 0)
                ki_index = i
        } else if (field == "kc") {
            kc_count++
            if (kc_index == 0)
                kc_index = i
        } else if (field == "max") {
            max_count++
            if (max_index == 0)
                max_index = i
        } else if (field == "min") {
            min_count++
            if (min_index == 0)
                min_index = i
        }
    }

    if (algo_count == 1 && device_count == 1) {
        if (algo == "monitor" && device == "battery")
            schema = "battery-monitor"
        else if (algo == "sic" && device == "thermal_fcc_override")
            schema = "battery-sic"
        else if (algo == "monitor" && device == "wireless_charge")
            schema = "wireless-monitor"
    }

    if (schema != "" || is_bat_header ||
        device == "battery" || device == "thermal_fcc_override" ||
        device == "wireless_charge") {
        if (schema == "battery-monitor" && trig_count >= 1 && clr_count >= 1) {
            # v4.2 clears both threshold lists in monitor/battery sections.
            section[trig_index] = "trig"
            section[clr_index] = "clr"
            printf "%s|PATCHED|%s|v4.2 monitor compatibility: trig/clr cleared\n",
                filename, header >> manifest
            patched++
        } else if (schema == "battery-sic" && trig_count == 1 && clr_count == 1 &&
                   proportion_count == 1 && target_count == 1 && ks_count == 1 &&
                   ki_count == 1 && kc_count == 1 && max_count == 1 && min_count == 1) {
            # Temperatures are millidegrees Celsius. FCC values are mA. The
            # clear points provide 0.5 C hysteresis below each upward trigger.
            section[proportion_index] = "proportion\t0"
            section[trig_index] = "trig\t15000\t40000\t41300\t44500\t47000"
            section[clr_index] = "clr\t14000\t39500\t40800\t44000\t46500"
            section[target_index] = "target\t0\t40500\t43500\t45000\t47000"
            section[ks_index] = "ks\t0\t6500000\t6500000\t6500000\t6500000"
            section[ki_index] = "ki\t0\t100000\t100000\t100000\t100000"
            section[kc_index] = "kc\t0\t0\t0\t0\t0"
            section[max_index] = "max\t20900\t11600\t9300\t8140\t4650"
            section[min_index] = "min\t20900\t7000\t4650\t3500\t2330"
            printf "%s|PATCHED|%s|relaxed bounded FCC/SIC curve installed\n",
                filename, header >> manifest
            patched++
        } else if (schema == "wireless-monitor" && trig_count >= 1 && clr_count >= 1 &&
                   proportion_count == 0) {
            # Wireless charging uses its own temperature-to-throttle monitor.
            # Empty threshold lists disable that charging-specific controller
            # while preserving unrelated platform thermal sections.
            section[trig_index] = "trig"
            section[clr_index] = "clr"
            printf "%s|PATCHED|%s|wireless charging thermal thresholds cleared\n",
                filename, header >> manifest
            patched++
        } else {
            printf "%s|ERROR|%s|unknown charging schema algo=%s device=%s proportion=%d trig=%d clr=%d target=%d ks=%d ki=%d kc=%d max=%d min=%d\n",
                filename, header, algo, device, proportion_count, trig_count, clr_count,
                target_count, ks_count, ki_count, kc_count, max_count, min_count >> manifest
            invalid = 1
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
    is_bat_header = (clean_header ~ /^\[[^]]*-BAT\]$/)
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
