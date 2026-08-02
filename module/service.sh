#!/system/bin/sh

wait_sys_boot_completed() {
    local retries=9
    until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$retries" -le 0 ]; do
        retries=$((retries - 1))
        sleep 9
    done
}

wait_sys_boot_completed

MODDIR="${0%/*}"
PID_FILE="$MODDIR/AppOpt.pid"

[ -x "$MODDIR/AppOpt" ] || exit 1

APP_OPT_RUNNING=0
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        OLD_CMD=$(tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null)
        case "$OLD_CMD" in
            "$MODDIR/AppOpt"*) APP_OPT_RUNNING=1 ;;
        esac
    fi
fi

if [ "$APP_OPT_RUNNING" != "1" ]; then
    nohup "$MODDIR/AppOpt" -c "$MODDIR/applist.conf" -b AppOpt >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
fi

for MAX_CPUS in /sys/devices/system/cpu/cpu*/core_ctl/max_cpus; do
    [ -e "$MAX_CPUS" ] || continue
    MIN_CPUS="${MAX_CPUS%/*}/min_cpus"
    if [ -e "$MIN_CPUS" ] && [ "$(cat "$MAX_CPUS")" != "$(cat "$MIN_CPUS")" ]; then
        chmod a+w "$MIN_CPUS"
        cat "$MAX_CPUS" > "$MIN_CPUS"
        chmod a-w "$MIN_CPUS"
    fi
done

# 如需暂停绿厂 oiface，请取消下一行注释；恢复时将 0 改为 1。
# [ -n "$(getprop persist.sys.oiface.enable)" ] && setprop persist.sys.oiface.enable 0

# 如需禁用米系机型 joyose，请取消下一行注释。
# pm disable-user com.xiaomi.joyose; pm clear com.xiaomi.joyose
