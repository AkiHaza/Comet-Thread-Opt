SKIPUNZIP=0

check_magisk_version() {
    ui_print "- Magisk version: $MAGISK_VER_CODE"
    ui_print "- Module version: $(grep_prop version "$TMPDIR/module.prop")"
    ui_print "- Module versionCode: $(grep_prop versionCode "$TMPDIR/module.prop")"
    ui_print "********************************************"
    ui_print "- $(grep_prop description "$TMPDIR/module.prop")"
    if [ "$MAGISK_VER_CODE" -lt 20400 ]; then
        ui_print "********************************************"
        ui_print "! 请安装 Magisk v20.4+ (20400+)"
        abort "********************************************"
    fi
}

check_required_files() {
    for REQUIRED_FILE in /sys/devices/system/cpu/present /proc/loadavg; do
        if [ ! -e "$REQUIRED_FILE" ]; then
            ui_print "********************************************"
            ui_print "! $REQUIRED_FILE 文件不存在"
            abort "! 请联系模块作者"
        fi
    done
}

extract_bin() {
    ui_print "********************************************"
    case "$ARCH" in
        arm) SOURCE_BIN="$MODPATH/bin/armeabi-v7a/AppOpt" ;;
        arm64) SOURCE_BIN="$MODPATH/bin/arm64-v8a/AppOpt" ;;
        x64) SOURCE_BIN="$MODPATH/bin/x86_64/AppOpt" ;;
        *) abort "! Unsupported platform: $ARCH" ;;
    esac

    ui_print "- Device platform: $ARCH"
    [ -f "$SOURCE_BIN" ] || abort "! 当前架构缺少 AppOpt 二进制文件"
    cp "$SOURCE_BIN" "$MODPATH/AppOpt"
    rm -rf "$MODPATH/bin"
    chmod a+x "$MODPATH/AppOpt"
    "$MODPATH/AppOpt" -v || abort "! 主程序验证失败，请检查模块 zip 文件是否损坏"
}

remove_sys_perf_config() {
    for SYSPERFCONFIG in /system/vendor/bin/msm_irqbalance; do
        [ -e "$SYSPERFCONFIG" ] || continue
        [ -d "$MODPATH${SYSPERFCONFIG%/*}" ] || mkdir -p "$MODPATH${SYSPERFCONFIG%/*}"
        ui_print "- Remove: $SYSPERFCONFIG"
        touch "$MODPATH$SYSPERFCONFIG"
    done

    if [ -n "$(pm path com.xiaomi.joyose)" ] && [ -n "$(getprop ro.miui.ui.version.code)" ]; then
        pm disable --user 0 com.xiaomi.joyose/.smartop.SmartOpService
        echo 'pm enable com.xiaomi.joyose/.smartop.SmartOpService' >> "$MODPATH/uninstall.sh"
    fi
}

detect_soc_profile() {
    SOC_MODEL=$(getprop ro.soc.model)
    SOC_PLATFORM=$(getprop ro.board.platform)
    SOC_HARDWARE=$(getprop ro.hardware)
    SOC_ID=$(printf '%s %s %s' "$SOC_MODEL" "$SOC_PLATFORM" "$SOC_HARDWARE" | tr '[:upper:]' '[:lower:]')

    case "$SOC_ID" in
        *sm8650*|*pineapple*)
            SOC_8G3=on
            PROFILE_NAME=8G3
            ;;
        *)
            SOC_8G3=off
            PROFILE_NAME=Common
            ;;
    esac

    ui_print "********************************************"
    ui_print "- SoC model: ${SOC_MODEL:-unknown}"
    ui_print "- SoC platform: ${SOC_PLATFORM:-unknown}"
    ui_print "- Thread profile: $PROFILE_NAME"
}

choose_mode() {
    ui_print "********************************************"
    ui_print "- 选择模式："
    ui_print "按音量+ Mode1: App线程"
    ui_print "按音量- Mode2: App+Game线程"
    ui_print "********************************************"

    MODE_VAL=""
    while [ -z "$MODE_VAL" ]; do
        EVENT=$(getevent -lqt 2>&1 | head -1)
        if echo "$EVENT" | grep -q "KEY_VOLUMEUP"; then
            MODE_VAL=app
            MODE_NAME=App
        elif echo "$EVENT" | grep -q "KEY_VOLUMEDOWN"; then
            MODE_VAL=mix
            MODE_NAME=Mix
        fi
        sleep 0.1
    done

    TIME_AREA=$(getprop persist.sys.timezone)
    [ -n "$TIME_AREA" ] || TIME_AREA=UTC
    UTC_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$MODPATH/confige.txt" << configEOF
mode=$MODE_VAL
8G3=$SOC_8G3
soc_model=$SOC_MODEL
soc_platform=$SOC_PLATFORM
time_area=$TIME_AREA
time=$UTC_TIME
configEOF

    sed -i "/^description=/ s|^description=.*|description=彗星线程分配 $PROFILE_NAME $MODE_NAME|" "$MODPATH/module.prop"
    ui_print "- 已选择: $PROFILE_NAME / $MODE_NAME"
}

preserve_existing_rules() {
    OLD_RULES=/data/adb/modules/AppOpt/applist.conf
    if [ -f "$OLD_RULES" ]; then
        mv "$MODPATH/applist.conf" "$MODPATH/applist.conf.bak"
        cp "$OLD_RULES" "$MODPATH/applist.conf"
        ui_print "- 已保留现有 applist.conf"
    fi
}

module_instructions() {
    ui_print "********************************************"
    ui_print "线程规则: /data/adb/modules/AppOpt/applist.conf"
    ui_print "设备配置: /data/adb/modules/AppOpt/confige.txt"
    ui_print "cpuset目录: /dev/cpuset/AkiAppOpt"
    ui_print "修改规则无需重启，AkiAppOpt 会自动热加载"
    ui_print "安装后可点击模块操作按钮更新对应配置"
    ui_print "重启后需运行action"
    ui_print "更多说明: http://AppOpt.suto.top"
    ui_print "********************************************"
}

check_magisk_version
check_required_files
extract_bin
remove_sys_perf_config
detect_soc_profile
choose_mode
preserve_existing_rules
module_instructions

set_perm_recursive "$MODPATH" 0 0 0755 0644
for SCRIPT in "$MODPATH"/*.sh; do
    [ -f "$SCRIPT" ] && set_perm "$SCRIPT" 0 2000 0755 u:object_r:magisk_file:s0
done
set_perm "$MODPATH/AppOpt" 0 2000 0755 u:object_r:magisk_file:s0
