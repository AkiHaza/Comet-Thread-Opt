#!/system/bin/sh
MODDIR=${0%/*}
PID_FILE="$MODDIR/AppOpt.pid"
LOG_FILE="$MODDIR/AppOpt.log"
MAX_LOG_BYTES=65536
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)

log_start_event() {
	local log_used log_remaining
	log_used=0
	[ ! -f "$LOG_FILE" ] || log_used=$(wc -c < "$LOG_FILE")
	log_remaining=$((MAX_LOG_BYTES-log_used))
	[ "$log_remaining" -gt 0 ] || return 0
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" |
		head -c "$log_remaining" >> "$LOG_FILE"
}

# comm can contain spaces and parentheses; strip through its last closing ).
read_process_identity() {
	case "$1" in ''|*[!0-9]*|0) return 1 ;; esac
	IFS= read -r PROCESS_STAT < "/proc/$1/stat" 2>/dev/null || return 1
	PROCESS_FIELDS=${PROCESS_STAT##*) }
	[ "$PROCESS_FIELDS" != "$PROCESS_STAT" ] || return 1
	set -- $PROCESS_FIELDS
	[ "$#" -ge 20 ] || return 1
	case "$1" in Z|X|x) return 1 ;; esac
	PROCESS_PARENT=$2
	shift 19
	PROCESS_START=$1
	case "$PROCESS_START" in ''|*[!0-9]*) return 1 ;; esac
}

identity_is_alive() {
	[ -n "$BOOT_ID" ] && [ "$3" = "$BOOT_ID" ] || return 1
	read_process_identity "$1" && [ "$PROCESS_START" = "$2" ]
}

is_appopt_process() {
	read_process_identity "$1" || return 1
	PROCESS_CMD=$(tr '\0' '\n' < "/proc/$1/cmdline" 2>/dev/null | head -n 1)
	[ "$PROCESS_CMD" = "$MODDIR/AppOpt" ]
}

appopt_identity_is_alive() {
	identity_is_alive "$1" "$2" "$3" &&
		is_appopt_process "$1" && [ "$PROCESS_START" = "$2" ]
}

read_pid_record() {
	[ -r "$PID_FILE" ] || return 1
	IFS=' ' read -r RECORD_PID RECORD_START RECORD_BOOT RECORD_EXTRA < "$PID_FILE" 2>/dev/null || return 1
	[ -z "$RECORD_EXTRA" ] &&
		appopt_identity_is_alive "$RECORD_PID" "$RECORD_START" "$RECORD_BOOT"
}

write_pid_record() {
	RECORD_TMP="$PID_FILE.$$"
	(umask 077; printf '%s %s %s\n' "$1" "$2" "$BOOT_ID" > "$RECORD_TMP") &&
		mv -f "$RECORD_TMP" "$PID_FILE"
}

stop_appopt_identity() {
	appopt_identity_is_alive "$1" "$2" "$3" || return 0
	kill "$1" 2>/dev/null || return 1
	local remaining=5
	while appopt_identity_is_alive "$1" "$2" "$3" && [ "$remaining" -gt 0 ]; do
		remaining=$((remaining-1))
		sleep 1 9>&-
	done
	if appopt_identity_is_alive "$1" "$2" "$3"; then
		kill -9 "$1" 2>/dev/null
	fi
}

stop_late_load_instance() {
	if read_pid_record; then
		stop_appopt_identity "$RECORD_PID" "$RECORD_START" "$RECORD_BOOT"
	fi
	# Legacy records are accepted only after capturing an exact binary identity.
	if command -v pidof >/dev/null 2>&1; then
		APP_OPT_PIDS=$(pidof AppOpt 2>/dev/null)
	elif [ -f "$PID_FILE" ]; then
		IFS=' ' read -r APP_OPT_PIDS _ < "$PID_FILE"
	fi
	for APP_OPT_PID in $APP_OPT_PIDS; do
		if is_appopt_process "$APP_OPT_PID"; then
			stop_appopt_identity "$APP_OPT_PID" "$PROCESS_START" "$BOOT_ID"
		fi
	done
	rm -f "$PID_FILE"
}

wait_sys_boot_completed() {
	local remaining=9
	until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$remaining" -le 0 ]; do
		remaining=$((remaining-1))
		sleep 9 9>&-
	done
}

module_is_enabled() {
	[ "$STOP_REQUESTED" != "1" ] &&
		[ -d "$MODDIR" ] && [ -x "$MODDIR/AppOpt" ] &&
		[ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ]
}

monotonic_seconds() {
	IFS=' ' read -r UPTIME_VALUE _ < /proc/uptime
	MONOTONIC_SECONDS=${UPTIME_VALUE%%.*}
}

remove_own_pid_record() {
	[ -r "$PID_FILE" ] || return 0
	IFS=' ' read -r RECORD_PID RECORD_START RECORD_BOOT RECORD_EXTRA < "$PID_FILE"
	if [ "$RECORD_PID" = "$APP_PID" ] && [ "$RECORD_START" = "$APP_START" ] &&
		[ "$RECORD_BOOT" = "$BOOT_ID" ] && [ -z "$RECORD_EXTRA" ]; then
		rm -f "$PID_FILE"
	fi
}

stop_previous_watchdog() {
	[ -r "$WATCHDOG_FILE" ] || return 0
	local old_pid old_start old_boot old_extra remaining
	IFS=' ' read -r old_pid old_start old_boot old_extra < "$WATCHDOG_FILE"
	[ -z "$old_extra" ] && identity_is_alive "$old_pid" "$old_start" "$old_boot" || return 0
	kill "$old_pid" 2>/dev/null || return 1
	remaining=8
	while identity_is_alive "$old_pid" "$old_start" "$old_boot" && [ "$remaining" -gt 0 ]; do
		remaining=$((remaining-1))
		sleep 1 9>&-
	done
	if identity_is_alive "$old_pid" "$old_start" "$old_boot"; then
		kill -9 "$old_pid" 2>/dev/null
	fi
}

prepare_log() {
	if [ -f "$LOG_FILE" ]; then
		mv -f "$LOG_FILE" "$LOG_FILE.prev" || return 1
	fi
	: > "$LOG_FILE" || return 1
	log_start_event "starting AppOpt"
}

finish_logger() {
	if [ -n "$LOGGER_PID" ]; then
		if identity_is_alive "$LOGGER_PID" "$LOGGER_START" "$BOOT_ID"; then
			# A descendant may still hold stdout after AppOpt has exited.
			sleep 1 9>&-
			stop_owned_child "$LOGGER_PID" "$LOGGER_START"
		fi
		if ! identity_is_alive "$LOGGER_PID" "$LOGGER_START" "$BOOT_ID"; then
			wait "$LOGGER_PID" 2>/dev/null
		fi
		LOGGER_PID=
		LOGGER_START=
	fi
}

stop_owned_child() {
	local child_pid child_start remaining
	child_pid=$1
	child_start=$2
	identity_is_alive "$child_pid" "$child_start" "$BOOT_ID" || return 0
	[ "$PROCESS_PARENT" = "$$" ] || return 1
	kill "$child_pid" 2>/dev/null || return 1
	remaining=2
	while identity_is_alive "$child_pid" "$child_start" "$BOOT_ID" && [ "$remaining" -gt 0 ]; do
		remaining=$((remaining-1))
		sleep 1 9>&-
	done
	if identity_is_alive "$child_pid" "$child_start" "$BOOT_ID" && [ "$PROCESS_PARENT" = "$$" ]; then
		kill -9 "$child_pid" 2>/dev/null
	fi
}

start_appopt() {
	prepare_log || return 1
	LOG_PIPE="$MODDIR/.AppOpt.log.$$"
	rm -f "$LOG_PIPE"
	if ! mkfifo "$LOG_PIPE"; then
		log_start_event "cannot create startup log pipe"
		return 1
	fi
	LOG_USED=$(wc -c < "$LOG_FILE")
	LOG_REMAINING=$((MAX_LOG_BYTES-LOG_USED))
	(
		trap '' HUP
		exec 8<&0
		LOGGER_STOP=0
		trap 'LOGGER_STOP=1; [ -z "$LOG_READER" ] || kill "$LOG_READER" 2>/dev/null' INT TERM
		head -c "$LOG_REMAINING" <&8 >> "$LOG_FILE" &
		LOG_READER=$!
		[ "$LOGGER_STOP" = "0" ] || kill "$LOG_READER" 2>/dev/null
		wait "$LOG_READER" 2>/dev/null
		[ "$LOGGER_STOP" = "0" ] || exit 0
		cat <&8 > /dev/null &
		LOG_READER=$!
		[ "$LOGGER_STOP" = "0" ] || kill "$LOG_READER" 2>/dev/null
		wait "$LOG_READER" 2>/dev/null
	) 9>&- < "$LOG_PIPE" &
	LOGGER_PID=$!
	LOGGER_START=
	if read_process_identity "$LOGGER_PID"; then LOGGER_START=$PROCESS_START; fi
	nohup "$MODDIR/AppOpt" -c "$MODDIR/applist.conf" 9>&- > "$LOG_PIPE" 2>&1 &
	APP_PID=$!
	APP_CHILD=1
	APP_START=
	if read_process_identity "$APP_PID"; then APP_START=$PROCESS_START; fi
	sleep 1 9>&-
	rm -f "$LOG_PIPE"
	LOG_PIPE=
	if is_appopt_process "$APP_PID" && { [ -z "$APP_START" ] || [ "$APP_START" = "$PROCESS_START" ]; }; then
		APP_START=$PROCESS_START
		if write_pid_record "$APP_PID" "$APP_START"; then return 0; fi
		stop_appopt_identity "$APP_PID" "$APP_START" "$BOOT_ID"
	fi
	# The owned child can still be in nohup/exec when its argv0 check fails.
	stop_owned_child "$APP_PID" "$APP_START"
	APP_STATUS=1
	if ! identity_is_alive "$APP_PID" "$APP_START" "$BOOT_ID"; then
		wait "$APP_PID" 2>/dev/null
		APP_STATUS=$?
	fi
	[ "$APP_STATUS" -eq 0 ] && APP_STATUS=1
	finish_logger
	remove_own_pid_record
	APP_PID=
	return 1
}

watchdog_cleanup() {
	trap - EXIT
	trap '' HUP INT TERM
	if [ -n "$APP_PID" ]; then
		if [ "$APP_CHILD" = "1" ]; then
			stop_owned_child "$APP_PID" "$APP_START"
			if ! identity_is_alive "$APP_PID" "$APP_START" "$BOOT_ID"; then
				wait "$APP_PID" 2>/dev/null
			fi
		else
			stop_appopt_identity "$APP_PID" "$APP_START" "$BOOT_ID"
		fi
		remove_own_pid_record
	fi
	[ -n "$LOG_PIPE" ] && rm -f "$LOG_PIPE"
	finish_logger
	if [ -r "$WATCHDOG_FILE" ]; then
		IFS=' ' read -r RECORD_PID RECORD_START RECORD_BOOT RECORD_EXTRA < "$WATCHDOG_FILE"
		if [ "$RECORD_PID" = "$$" ] && [ "$RECORD_START" = "$WATCHDOG_START" ] &&
			[ "$RECORD_BOOT" = "$BOOT_ID" ] && [ -z "$RECORD_EXTRA" ]; then
			rm -f "$WATCHDOG_FILE"
		fi
	fi
}

WATCHDOG_FILE="$MODDIR/.AppOpt.watchdog.pid"
[ -n "$BOOT_ID" ] || exit 1
if [ "$1" != "--watchdog" ]; then
	wait_sys_boot_completed
	module_is_enabled || exit 0
	if [ "$KSU_LATE_LOAD" = "1" ]; then stop_previous_watchdog; fi
	exec 9>> "$MODDIR/.AppOpt.service.lock" || exit 1
	"$MODDIR/AppOpt" --acquire-service-lock
	LOCK_STATUS=$?
	[ "$LOCK_STATUS" -eq 73 ] && exit 0
	[ "$LOCK_STATUS" -eq 0 ] || exit 1
	if [ "$KSU_LATE_LOAD" = "1" ]; then stop_late_load_instance; fi
	# The child retains fd 9 while this startup shell returns to the Root manager.
	nohup /system/bin/sh "$MODDIR/service.sh" --watchdog >/dev/null 2>&1 &
	exit 0
fi

# Internal mode is valid only with the startup shell's inherited lock fd.
"$MODDIR/AppOpt" --acquire-service-lock || exit 1
module_is_enabled || exit 0
read_process_identity "$$" || exit 1
WATCHDOG_START=$PROCESS_START
APP_PID=
APP_START=
APP_CHILD=0
LOGGER_PID=
LOGGER_START=
LOG_PIPE=
STOP_REQUESTED=0
trap 'STOP_REQUESTED=1' HUP INT TERM
trap watchdog_cleanup EXIT
(umask 077; printf '%s %s %s\n' "$$" "$WATCHDOG_START" "$BOOT_ID" > "$WATCHDOG_FILE.$$") &&
	mv -f "$WATCHDOG_FILE.$$" "$WATCHDOG_FILE" || exit 1

if read_pid_record; then
	APP_PID=$RECORD_PID
	APP_START=$RECORD_START
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

CRASH_COUNT=0
while module_is_enabled; do
	monotonic_seconds
	RUN_STARTED=$MONOTONIC_SECONDS
	APP_STATUS=1
	if [ -z "$APP_PID" ]; then
		start_appopt
	fi
	if [ -n "$APP_PID" ]; then
		while module_is_enabled && appopt_identity_is_alive "$APP_PID" "$APP_START" "$BOOT_ID"; do
			sleep 1 9>&-
		done
		module_is_enabled || break
		if [ "$APP_CHILD" = "1" ]; then
			# argv0 may change while the same owned child remains alive.
			stop_owned_child "$APP_PID" "$APP_START"
			if ! identity_is_alive "$APP_PID" "$APP_START" "$BOOT_ID"; then
				wait "$APP_PID" 2>/dev/null
				APP_STATUS=$?
			fi
		fi
		finish_logger
		remove_own_pid_record
		APP_PID=
	fi
	# A manually started instance won the daemon lock. Do not fight its owner.
	[ "$APP_STATUS" -eq 73 ] && exit 0
	module_is_enabled || break
	monotonic_seconds
	if [ $((MONOTONIC_SECONDS-RUN_STARTED)) -ge 60 ]; then CRASH_COUNT=0; fi
	CRASH_COUNT=$((CRASH_COUNT+1))
	case "$CRASH_COUNT" in 1) RETRY_DELAY=5 ;; 2) RETRY_DELAY=10 ;; 3) RETRY_DELAY=30 ;; *) RETRY_DELAY=60 ;; esac
	log_start_event "AppOpt exited (status $APP_STATUS); retrying in $RETRY_DELAY seconds"
	while [ "$RETRY_DELAY" -gt 0 ] && module_is_enabled; do
		sleep 1 9>&-
		RETRY_DELAY=$((RETRY_DELAY-1))
	done
done
