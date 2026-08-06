#!/system/bin/sh

MODDIR="${0%/*}"
PID_FILE="$MODDIR/AppOpt.pid"

is_appopt_process() {
    [ -n "$1" ] && [ -r "/proc/$1/cmdline" ] || return 1
    PROCESS_CMD=$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null)
    case "$PROCESS_CMD" in
        "$MODDIR/AppOpt"*) return 0 ;;
    esac
    return 1
}

stop_late_load_instance() {
    APP_OPT_PIDS=""
    if command -v pidof >/dev/null 2>&1; then
        APP_OPT_PIDS=$(pidof AppOpt 2>/dev/null)
    fi
    if [ -z "$APP_OPT_PIDS" ] && [ -f "$PID_FILE" ]; then
        APP_OPT_PIDS=$(cat "$PID_FILE" 2>/dev/null)
    fi

    for APP_OPT_PID in $APP_OPT_PIDS; do
        is_appopt_process "$APP_OPT_PID" || continue
        kill "$APP_OPT_PID" 2>/dev/null || continue
        RETRIES=5
        while kill -0 "$APP_OPT_PID" 2>/dev/null && [ "$RETRIES" -gt 0 ]; do
            RETRIES=$((RETRIES - 1))
            sleep 1
        done
        if kill -0 "$APP_OPT_PID" 2>/dev/null; then
            kill -9 "$APP_OPT_PID" 2>/dev/null
        fi
    done
    rm -f "$PID_FILE"
}

wait_sys_boot_completed() {
    local retries=9
    until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$retries" -le 0 ]; do
        retries=$((retries - 1))
        sleep 9
    done
}

# KernelSU late-load 软启动后重建 AppOpt，正常启动模式不进入此分支。
if [ "${KSU_LATE_LOAD:-0}" = "1" ]; then
    stop_late_load_instance
fi

wait_sys_boot_completed

[ -x "$MODDIR/AppOpt" ] || exit 1

APP_OPT_RUNNING=0
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if is_appopt_process "$OLD_PID"; then
        APP_OPT_RUNNING=1
    fi
fi

if [ "$APP_OPT_RUNNING" != "1" ]; then
    nohup "$MODDIR/AppOpt" -c "$MODDIR/applist.conf" -b AkiAppOpt >/dev/null 2>&1 &
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
