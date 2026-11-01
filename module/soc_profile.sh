#!/system/bin/sh

# Shared by the installer and Action. Use present CPUs, not hotplug online CPUs.
detect_soc_profile() {
    SOC_MODEL=$(getprop ro.soc.model 2>/dev/null) || SOC_MODEL=
    SOC_PLATFORM=$(getprop ro.board.platform 2>/dev/null) || SOC_PLATFORM=
    SOC_HARDWARE=$(getprop ro.hardware 2>/dev/null) || SOC_HARDWARE=
    SOC_ID=$(printf '%s %s %s' "$SOC_MODEL" "$SOC_PLATFORM" "$SOC_HARDWARE" | tr '[:upper:]' '[:lower:]')

    CPU_TOPOLOGY=$(LC_ALL=C awk '
        NR != 1 { invalid = 1; next }
        $0 !~ /^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$/ { invalid = 1; next }
        {
            parts = split($0, ranges, ",")
            previous = -1
            for (i = 1; i <= parts; i++) {
                ends = split(ranges[i], bounds, "-")
                lo = bounds[1] + 0
                hi = ends == 2 ? bounds[2] + 0 : lo
                if (lo > hi || lo <= previous) { invalid = 1; break }
                if (i == 1) first = lo
                count += hi - lo + 1
                previous = hi
            }
        }
        END {
            if (NR != 1 || invalid) print "unknown 0"
            else printf "%.0f %d\n", count, (count == 8 && first == 0 && previous == 7)
        }
    ' /sys/devices/system/cpu/present 2>/dev/null) || CPU_TOPOLOGY="unknown 0"
    CPU_COUNT=${CPU_TOPOLOGY% *}

    SOC_8G3=off
    PROFILE_NAME=Common
    case "$SOC_ID" in
        *sm8650*|*pineapple*)
            # Fixed 8G3 rules require all CPU IDs 0..7, not just any eight IDs.
            if [ "$CPU_TOPOLOGY" = "8 1" ]; then
                SOC_8G3=on
                PROFILE_NAME=8G3
            fi
            ;;
    esac
}
