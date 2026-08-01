SKIPUNZIP=0
check_magisk_version() {
	ui_print "- Magisk version: $MAGISK_VER_CODE"
	ui_print "- Module version: $(grep_prop version "${TMPDIR}/module.prop")"
	ui_print "- Module versionCode: $(grep_prop versionCode "${TMPDIR}/module.prop")"
	ui_print "********************************************"
	ui_print "- $(grep_prop description "${TMPDIR}/module.prop")"
	if [ "$MAGISK_VER_CODE" -lt 20400 ]; then
		ui_print "********************************************"
		ui_print "! 请安装 Magisk v20.4+ (20400+)"
		abort    "********************************************"
	fi
}
check_soc_model() {
	ui_print "********************************************"
	ui_print "检测SoC中…"
	soc_model=$(getprop ro.soc.model)
	ui_print "型号: $soc_model"
	if [ "$soc_model" != "SM8650" ]; then
		ui_print "仅支持8Gen3"
		abort    "你的SoC型号($soc_model)"
	else
		ui_print "SoC支持，继续安装"
	fi
}
check_required_files() {
	REQUIRED_FILE_LIST="/sys/devices/system/cpu/present /proc/loadavg"
	for REQUIRED_FILE in $REQUIRED_FILE_LIST; do
		if [ ! -e $REQUIRED_FILE ]; then
			ui_print "********************************************"
			ui_print "! $REQUIRED_FILE 文件不存在"
			ui_print "! 请联系模块作者"
			abort    "********************************************"
		fi
	done
}
extract_bin() {
	ui_print "********************************************"
	if [ "$ARCH" = "arm" ]; then
		cp $MODPATH/bin/armeabi-v7a/AppOpt $MODPATH
	elif [ "$ARCH" = "arm64" ]; then
		cp $MODPATH/bin/arm64-v8a/AppOpt $MODPATH
	elif [ "$ARCH" = "x86" ]; then
		cp $MODPATH/bin/x86/AppOpt $MODPATH
	elif [ "$ARCH" = "x64" ]; then
		cp $MODPATH/bin/x86_64/AppOpt -v $MODPATH
	else
		abort "! Unsupported platform: $ARCH"
	fi
	ui_print "- Device platform: $ARCH"
	rm -rf $MODPATH/bin
	[ -f $MODPATH/AppOpt ] && chmod a+x $MODPATH/AppOpt
	if ! $MODPATH/AppOpt -v; then
		abort "! 主程序验证失败，请检查模块zip文件是否损坏"
	fi
}
remove_sys_perf_config() {
	for SYSPERFCONFIG in $(ls /system/vendor/bin/msm_irqbalance); do
		[[ ! -d $MODPATH${SYSPERFCONFIG%/*} ]] && mkdir -p $MODPATH${SYSPERFCONFIG%/*}
		ui_print "- Remove :$SYSPERFCONFIG"
		touch $MODPATH$SYSPERFCONFIG
	done
	if [ -n "$(pm path com.xiaomi.joyose)" ] && [ -n "$(getprop ro.miui.ui.version.code)" ]; then
		pm disable --user 0 com.xiaomi.joyose/.smartop.SmartOpService
		echo 'pm enable com.xiaomi.joyose/.smartop.SmartOpService' >> $MODPATH/uninstall.sh
	fi
}
format_cpu_ranges() {
	[ -z "${1// /}" ] && { cat /sys/devices/system/cpu/present; return; }
	awk -v input="$1" 'BEGIN {
		n = split(input, arr, /[[:space:]]+/)
		j = 0
		for (i = 1; i <= n; i++) {
			if (arr[i] != "" && !seen[arr[i]]++) 
				nums[++j] = arr[i] + 0
		}
		n = j
		if (!n) exit
		for (i = 1; i < n; i++) {
			min = i
			for (j = i + 1; j <= n; j++)
				if (nums[j] < nums[min]) min = j
			if (min != i) {
				t = nums[i]
				nums[i] = nums[min]
				nums[min] = t
			}
		}
		start = last = nums[1]
		for (i = 2; i <= n; i++) {
			if (nums[i] == last + 1) {
				last = nums[i]
				continue
			}
			printf "%s%s", sep, (start == last ? start : start "-" last)
			sep = ","
			start = last = nums[i]
		}
		printf "%s", sep
		printf (start == last ? start : start "-" last)
	}'
}
sorted_groups=$(
	for policy in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -d "$policy" ] || continue
		cpus=$(cat "$policy/related_cpus" 2>/dev/null)
		freq=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null)
		[ -z "$cpus" ] || [ -z "$freq" ] && continue
		echo "$freq:$cpus"
	done | sort -n -t: -k1,1 | awk -F: '
	$1 == prev { cores = cores " " $2; next }
	prev != "" { print prev ":" cores; cores = "" }
	{ prev = $1; cores = $2 }
	END { if (prev != "") print prev ":" cores }'
)
eval "$(echo "$sorted_groups" | awk -F: '
BEGIN {
	e_core = ""; p_core = ""; hp_core = ""
	e_core_freq = 0; p_core_freq = 0; hp_core_freq = 0
	total_groups = 0
}
{
	freq_arr[NR] = $1
	cpus_arr[NR] = $2
	total_groups = NR
}
END {
	if (total_groups == 0) {
		print "e_core=\"\"; e_core_freq=0; p_core=\"\"; p_core_freq=0; hp_core=\"\"; hp_core_freq=0; total_groups=0;"
		exit
	}
	e_core = cpus_arr[1]
	e_core_freq = freq_arr[1]
	if (total_groups >= 2) {
		hp_core = cpus_arr[total_groups]
		hp_core_freq = freq_arr[total_groups]
	}
	if (total_groups >= 3) {
		p_core = ""
		p_core_freq = 0
		for (i = 2; i < total_groups; i++) {
			p_core = p_core (p_core == "" ? "" : " ") cpus_arr[i]
			if (freq_arr[i] > p_core_freq) p_core_freq = freq_arr[i]
		}
	}
	printf "e_core=\"%s\"; e_core_freq=%d; ", e_core, e_core_freq
	printf "p_core=\"%s\"; p_core_freq=%d; ", p_core, p_core_freq
	printf "hp_core=\"%s\"; hp_core_freq=%d; ", hp_core, hp_core_freq
	printf "total_groups=%d;", total_groups
}')"
all_core="$(cat /sys/devices/system/cpu/present)"
choose_mode() {
	ui_print "********************************************"
	ui_print "- 选择模式："
	ui_print "按音量+ Mode1:包含App线程"
	ui_print "按音量- Mode2:包含App+Game线程"
	ui_print "********************************************"
	choice=""
	while [ -z "$choice" ]; do
		event=$(getevent -lqt 2>&1 | head -1)
		if echo "$event" | grep -q "KEY_VOLUMEUP"; then
			choice="app"
			ui_print "- 已选择App模式"
		elif echo "$event" | grep -q "KEY_VOLUMEDOWN"; then
			choice="game"
			ui_print "- 已选择Mix模式"
		fi
		sleep 0.1
	done

	TIME_AREA=$(getprop persist.sys.timezone)
	[ -z "$TIME_AREA" ] && TIME_AREA="UTC"
	UTC_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	if [ "$choice" = "game" ]; then
		MODE_VAL="mix"
		MODE_NAME="Mix"
	else
		MODE_VAL="app"
		MODE_NAME="App"
	fi

	cat > "$MODPATH/config.txt" << configEOF
mode=$MODE_VAL
time_area=$TIME_AREA
time=$UTC_TIME
configEOF

	sed -i "/^description=/ s/^description=.*/description=彗星线程分配 $MODE_NAME/" "$MODPATH/module.prop"
	ui_print "- 模式: $MODE_NAME | 时区: $TIME_AREA"
}
module_instructions() {
	ui_print "********************************************"
	ui_print "线程规则配置文件路径为："
	ui_print "/data/adb/modules/AppOpt/applist.conf"
	ui_print "------------------------------------------"
	ui_print "修改与添加规则无需重启，即时生效"
	ui_print "********************************************"
	cores=$(for cpus in /sys/devices/system/cpu/cpufreq/*/related_cpus; do 
		[ -f "$cpus" ] && cat "$cpus" | wc -w
	done | paste -sd+)
	ui_print "当前$(getprop ro.soc.model)设备为$(nproc)核CPU，规格是：$cores"
	ui_print "可用CPU范围：$all_core"
	ui_print "------------------------------------------"
	ui_print "更多规则使用说明请参考："
	ui_print "http://AppOpt.suto.top"
	ui_print "秋山羽桜的TG频道"
	ui_print "https://t.me/simokiochannel"
	ui_print "********************************************"
}
check_magisk_version
check_soc_model
check_required_files
extract_bin
remove_sys_perf_config
choose_mode
module_instructions
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/*.sh $MODPATH/AppOpt" 0 2000 0755 0755 u:object_r:magisk_file:s0