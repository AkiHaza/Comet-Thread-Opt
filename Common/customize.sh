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
	ui_print "按音量+ Mode1 App线程"
	ui_print "按音量- Mode2 App+Game线程"
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
	ui_print "风凌惜桜的TG频道"
	ui_print "https://t.me/simokiochannel"
	ui_print "********************************************"
}
add_default_rules() {
common_rules="
#通讯
# 微信
com.tencent.mm{RenderThread}=$(format_cpu_ranges "$p_core")
com.tencent.mm{com.tencent.mm}=$(format_cpu_ranges "$p_core")
com.tencent.mm{default_matrix_}=$(format_cpu_ranges "$p_core")
com.tencent.mm{binder:*}=$(format_cpu_ranges "$p_core")
com.tencent.mm=$(format_cpu_ranges "$e_core $p_core")

# QQ
com.tencent.mobileqq{RenderThread}=$(format_cpu_ranges "$p_core")
com.tencent.mobileqq{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
com.tencent.mobileqq{encent.mobileqq}=$(format_cpu_ranges "$p_core")
com.tencent.mobileqq=$(format_cpu_ranges "$e_core $p_core")

# TIM
com.tencent.tim{com.tencent.tim}=$(format_cpu_ranges "$p_core")
com.tencent.tim{RenderThread}=$(format_cpu_ranges "$p_core")
com.tencent.tim{HeapTaskDaemon}=$(format_cpu_ranges "$p_core")
com.tencent.tim=$(format_cpu_ranges "$e_core $p_core")

# Nekogram
tw.nekomimi.nekogram{RenderThread}=$(format_cpu_ranges "$p_core")
tw.nekomimi.nekogram{files_database_}=$(format_cpu_ranges "$p_core")
tw.nekomimi.nekogram{searchQueue}=$(format_cpu_ranges "$p_core")
tw.nekomimi.nekogram{komimi.nekogram}=$(format_cpu_ranges "$p_core")
tw.nekomimi.nekogram=$(format_cpu_ranges "$e_core $p_core")

# telegram
org.telegram.group{Thread-*}=$(format_cpu_ranges "$p_core")
org.telegram.group{RenderThread}=$(format_cpu_ranges "$p_core")
org.telegram.group{.telegram.group}=$(format_cpu_ranges "$p_core")
org.telegram.group=$(format_cpu_ranges "$e_core $p_core")
org.telegram.messenger{Thread-*}=$(format_cpu_ranges "$p_core")
org.telegram.messenger{RenderThread}=$(format_cpu_ranges "$p_core")
org.telegram.messenger{egram.messenger}=$(format_cpu_ranges "$p_core")
org.telegram.messenger=$(format_cpu_ranges "$e_core $p_core")

# Nagram X
nu.gpu.nagram{Thread-*}=$(format_cpu_ranges "$p_core")
nu.gpu.nagram{RenderThread}=$(format_cpu_ranges "$p_core")
nu.gpu.nagram{nu.gpu.nagram}=$(format_cpu_ranges "$p_core")
nu.gpu.nagram=$(format_cpu_ranges "$e_core $p_core")

# Nagram
xyz.nextalone.nagram{RenderThread}=$(format_cpu_ranges "$p_core")
xyz.nextalone.nagram{extalone.nagram}=$(format_cpu_ranges "$p_core")
xyz.nextalone.nagram{stageQueue}=$(format_cpu_ranges "$p_core")
xyz.nextalone.nagram{Thread-*}=$(format_cpu_ranges "$p_core")
xyz.nextalone.nagram=$(format_cpu_ranges "$e_core $p_core")

# Ayugram
com.radolyn.ayugram{RenderThread}=$(format_cpu_ranges "$p_core")
com.radolyn.ayugram{radolyn.ayugram}=$(format_cpu_ranges "$p_core")
com.radolyn.ayugram{SpoilerEffectBi}=$(format_cpu_ranges "$p_core")
com.radolyn.ayugram{Thread-*}=$(format_cpu_ranges "$p_core")
com.radolyn.ayugram=$(format_cpu_ranges "$e_core $p_core")

# 钉钉
com.alibaba.android.rimet{RenderThread}=$(format_cpu_ranges "$p_core")
com.alibaba.android.rimet{a.android.rimet}=$(format_cpu_ranges "$p_core")
com.alibaba.android.rimet{Doraemon-Proces}=$(format_cpu_ranges "$p_core")
com.alibaba.android.rimet=$(format_cpu_ranges "$e_core $p_core")

#购物
# 淘宝
com.taobao.taobao{WeexJSBridgeTh}=$(format_cpu_ranges "$p_core")
com.taobao.taobao{HeapTaskDaemon}=$(format_cpu_ranges "$p_core")
com.taobao.taobao{m.taobao.taobao}=$(format_cpu_ranges "$p_core")
com.taobao.taobao{8RYPVI8EZKhJUU}=$(format_cpu_ranges "$p_core")
com.taobao.taobao=$(format_cpu_ranges "$e_core $p_core")

# 京东
com.jingdong.app.mall{RenderThread}=$(format_cpu_ranges "$p_core")
com.jingdong.app.mall{pool-15-thread-}=$(format_cpu_ranges "$p_core")
com.jingdong.app.mall{RunnerWrapper_8}=$(format_cpu_ranges "$p_core")
com.jingdong.app.mall{ngdong.app.mall}=$(format_cpu_ranges "$p_core")
com.jingdong.app.mall{JDFileDownloade}=$(format_cpu_ranges "$p_core")
com.jingdong.app.mall=$(format_cpu_ranges "$e_core $p_core")

# 拼多多
com.xunmeng.pinduoduo{RenderThread}=$(format_cpu_ranges "$p_core")
com.xunmeng.pinduoduo{Chat#Single-Syn}=$(format_cpu_ranges "$p_core")
com.xunmeng.pinduoduo{Startup#RTDispa}=$(format_cpu_ranges "$p_core")
com.xunmeng.pinduoduo{nmeng.pinduoduo}=$(format_cpu_ranges "$p_core")
com.xunmeng.pinduoduo=$(format_cpu_ranges "$e_core $p_core")

# 闲鱼
com.taobao.idlefish{RenderThread}=$(format_cpu_ranges "$p_core")
com.taobao.idlefish{1.ui}=$(format_cpu_ranges "$p_core")
com.taobao.idlefish{taobao.idlefish}=$(format_cpu_ranges "$p_core")
com.taobao.idlefish{1.raster}=$(format_cpu_ranges "$p_core")
com.taobao.idlefish=$(format_cpu_ranges "$e_core $p_core")

# 美团
com.sankuai.meituan{RenderThread}=$(format_cpu_ranges "$p_core")
com.sankuai.meituan{sankuai.meituan}=$(format_cpu_ranges "$p_core")
com.sankuai.meituan{TTE-keyAgreemen}=$(format_cpu_ranges "$p_core")
com.sankuai.meituan=$(format_cpu_ranges "$e_core $p_core")

# 支付宝
com.eg.android.AlipayGphone{RenderThread}=$(format_cpu_ranges "$p_core")
com.eg.android.AlipayGphone{crv-worker-thre}=$(format_cpu_ranges "$p_core")
com.eg.android.AlipayGphone{id.AlipayGphone}=$(format_cpu_ranges "$p_core")
com.eg.android.AlipayGphone=$(format_cpu_ranges "$e_core $p_core")

# 美团外卖
com.sankuai.meituan.takeoutnew{RenderThread}=$(format_cpu_ranges "$p_core")
com.sankuai.meituan.takeoutnew{tuan.takeoutnew}=$(format_cpu_ranges "$p_core")
com.sankuai.meituan.takeoutnew{J*}=$(format_cpu_ranges "$p_core")
com.sankuai.meituan.takeoutnew=$(format_cpu_ranges "$e_core $p_core")

# 饿了么
me.ele{me.ele}=$(format_cpu_ranges "$hp_core")
me.ele{dp2ndk}=$(format_cpu_ranges "$p_core")
me.ele{Xxdn-Worker}=$(format_cpu_ranges "$p_core")
me.ele{1.raster}=$(format_cpu_ranges "$p_core")
me.ele{2.raster}=$(format_cpu_ranges "$p_core")
me.ele=$(format_cpu_ranges "$e_core $p_core")

#娱乐社媒
# 哔哩哔哩
tv.danmaku.bili{RenderThread}=$(format_cpu_ranges "$p_core")
tv.danmaku.bili{Thread*}=$(format_cpu_ranges "$p_core")
tv.danmaku.bili{IJK_External_Re}=$(format_cpu_ranges "$p_core")
tv.danmaku.bili{tv.danmaku.bili}=$(format_cpu_ranges "$p_core")
tv.danmaku.bili{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
tv.danmaku.bili=$(format_cpu_ranges "$e_core $p_core")

# 哔哩哔哩Play
com.bilibili.app.in{RenderThread}=$(format_cpu_ranges "$p_core")
com.bilibili.app.in{Thread*}=$(format_cpu_ranges "$p_core")
com.bilibili.app.in{IJK_External_Re}=$(format_cpu_ranges "$p_core")
com.bilibili.app.in{*.app.in}=$(format_cpu_ranges "$p_core")
com.bilibili.app.in{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
com.bilibili.app.in=$(format_cpu_ranges "$e_core $p_core")

# piliplus
com.example.piliplus{Thread-*}=$(format_cpu_ranges "$p_core")
com.example.piliplus{xample.piliplus}=$(format_cpu_ranges "$p_core")
com.example.piliplus{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
com.example.piliplus{demux}=$(format_cpu_ranges "$p_core")
com.example.piliplus{1.raster}=$(format_cpu_ranges "$p_core")
com.example.piliplus=$(format_cpu_ranges "$e_core $p_core")

# 优乐享视频
com.yishu.ylxsp{com.yishu.ylxsp}=$(format_cpu_ranges "$p_core")
com.yishu.ylxsp{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
com.yishu.ylxsp{1.raster}=$(format_cpu_ranges "$p_core")
com.yishu.ylxsp=$(format_cpu_ranges "$e_core $p_core")

# 红果免费短剧
com.phoenix.read{om.phoenix.read}=$(format_cpu_ranges "$p_core")
com.phoenix.read{RenderThread}=$(format_cpu_ranges "$p_core")
com.phoenix.read{Thread*}=$(format_cpu_ranges "$p_core")
com.phoenix.read=$(format_cpu_ranges "$e_core $p_core")

# komikku
app.komikku.beta{pp.komikku.beta}=$(format_cpu_ranges "$p_core")
app.komikku.beta{*thread*}=$(format_cpu_ranges "$p_core")
app.komikku.beta{RenderThread}=$(format_cpu_ranges "$p_core")
app.komikku.beta{AsyncTask*}=$(format_cpu_ranges "$p_core")
app.komikku.beta{}=$(format_cpu_ranges "$e_core $p_core")

# kototoro
org.skepsun.kototoro{RenderThread}=$(format_cpu_ranges "$p_core")
org.skepsun.kototoro{kepsun.kototoro}=$(format_cpu_ranges "$p_core")
org.skepsun.kototoro{DefaultDispatch}=$(format_cpu_ranges "$p_core")
org.skepsun.kototoro=$(format_cpu_ranges "$e_core $p_core")

#Readest
com.bilingify.readest{lingify.readest}=$(format_cpu_ranges "$p_core")
com.bilingify.readest{RenderThread}=$(format_cpu_ranges "$p_core")
com.bilingify.readest{Chrome InProcGp}=$(format_cpu_ranges "$p_core")
com.bilingify.readest=$(format_cpu_ranges "$e_core $p_core")

# 快手
com.smile.gifmaker{RenderThread}=$(format_cpu_ranges "$p_core")
com.smile.gifmaker{smile.gifmaker}=$(format_cpu_ranges "$p_core")
com.smile.gifmaker{MediaCodec_*}=$(format_cpu_ranges "$p_core")
com.smile.gifmaker=$(format_cpu_ranges "$e_core $p_core")
com.kuaishou.nebula{RenderThread}=$(format_cpu_ranges "$p_core")
com.kuaishou.nebula{kuaishou.nebula}=$(format_cpu_ranges "$p_core")
com.kuaishou.nebula{thread*}=$(format_cpu_ranges "$p_core")
com.kuaishou.nebula{*ffmpeg*}=$(format_cpu_ranges "$p_core")
com.kuaishou.nebula=$(format_cpu_ranges "$e_core $p_core")

# 爱奇艺
com.qiyi.video{PLAYER_INFLATE_}=$(format_cpu_ranges "$p_core")
com.qiyi.video{RenderThread}=$(format_cpu_ranges "$p_core")
com.qiyi.video{DanmakuGLThread}=$(format_cpu_ranges "$p_core")
com.qiyi.video{com.qiyi.video}=$(format_cpu_ranges "$p_core")
com.qiyi.video{PumaPlyrVEgn}=$(format_cpu_ranges "$p_core")
com.qiyi.video=$(format_cpu_ranges "$e_core $p_core")

# 抖音 
com.ss.android.ugc.aweme{*Thread}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme{VDecod2-*}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme{HeapTaskDaemon}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme{danmaku-driver}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme{droid.ugc.aweme}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme{#pty-wqp-*}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme=$(format_cpu_ranges "$e_core $p_core")
com.ss.android.ugc.aweme.lite{*Thread}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme.lite{VDecod2-*}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme.lite{HeapTaskDaemon}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme.lite{danmaku-driver}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme.lite{droid.ugc.aweme}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme.lite{#pty-wqp-*}=$(format_cpu_ranges "$p_core")
com.ss.android.ugc.aweme.lite=$(format_cpu_ranges "$e_core $p_core")

# 抖音精选
com.ss.android.yumme.video{RenderThread}=$(format_cpu_ranges "$p_core")
com.ss.android.yumme.video{oid.yumme.video}=$(format_cpu_ranges "$p_core")
com.ss.android.yumme.video{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
com.ss.android.yumme.video{TRThread*}=$(format_cpu_ranges "$p_core")
com.ss.android.yumme.video{VDecod*}=$(format_cpu_ranges "$p_core")
com.ss.android.yumme.video=$(format_cpu_ranges "$e_core $p_core")

# 酷安
com.coolapk.market{RenderThread}=$(format_cpu_ranges "$p_core")
com.coolapk.market{Thread-*}=$(format_cpu_ranges "$p_core")
com.coolapk.market{binder:*}=$(format_cpu_ranges "$p_core")
com.coolapk.market{.coolapk.market}=$(format_cpu_ranges "$p_core")
com.coolapk.market=$(format_cpu_ranges "$e_core $p_core")

# NGA玩家社区
gov.pianzong.androidnga{zong.androidnga}=$(format_cpu_ranges "$p_core")
gov.pianzong.androidnga{RenderThread}=$(format_cpu_ranges "$p_core")
gov.pianzong.androidnga{Thread*}=$(format_cpu_ranges "$p_core")
gov.pianzong.androidnga=$(format_cpu_ranges "$p_core $e_core")

# 微博
com.sina.weibo{RenderThread}=$(format_cpu_ranges "$p_core")
com.sina.weibo{Thread-*}=$(format_cpu_ranges "$p_core")
com.sina.weibo{com.sina.weibo}=$(format_cpu_ranges "$p_core")
com.sina.weibo=$(format_cpu_ranges "$e_core $p_core")

# 小黑盒
com.max.xiaoheihe{RenderThread}=$(format_cpu_ranges "$p_core")
com.max.xiaoheihe{glide-animation}=$(format_cpu_ranges "$p_core")
com.max.xiaoheihe{m.max.xiaoheihe}=$(format_cpu_ranges "$p_core")
com.max.xiaoheihe=$(format_cpu_ranges "$e_core $p_core")

# 贴吧
com.baidu.tieba{RenderThread}=$(format_cpu_ranges "$p_core")
com.baidu.tieba{com.baidu.tieba}=$(format_cpu_ranges "$p_core")
com.baidu.tieba=$(format_cpu_ranges "$e_core $p_core")

# 知乎
com.zhihu.android{RenderThread}=$(format_cpu_ranges "$p_core")
com.zhihu.android{m.zhihu.android}=$(format_cpu_ranges "$p_core")
com.zhihu.android=$(format_cpu_ranges "$e_core $p_core")

# 悠悠有品
com.uu898.uuhavequality:core{8.uuhavequality}=$(format_cpu_ranges "$p_core")
com.uu898.uuhavequality:core{RenderThread}=$(format_cpu_ranges "$p_core")
com.uu898.uuhavequality:core{BR-LagTrace-Thr}=$(format_cpu_ranges "$p_core")
com.uu898.uuhavequality:core=$(format_cpu_ranges "$e_core $p_core")

# X
com.twitter.android{twitter.android}=$(format_cpu_ranges "$p_core")
com.twitter.android{RenderThread}=$(format_cpu_ranges "$p_core")
com.twitter.android{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
com.twitter.android=$(format_cpu_ranges "$e_core $p_core")

# YouTube
com.google.android.youtube{android.youtube}=$(format_cpu_ranges "$p_core")
com.google.android.youtube{RenderThread}=$(format_cpu_ranges "$p_core")
com.google.android.youtube{ExoPlayer:Playb}=$(format_cpu_ranges "$p_core")
com.google.android.youtube{MediaCodec_loop}=$(format_cpu_ranges "$p_core")
com.google.android.youtube=$(format_cpu_ranges "$e_core $p_core")

# Facebook
com.facebook.katana{facebook.katana}=$(format_cpu_ranges "$p_core")
com.facebook.katana{RenderThread}=$(format_cpu_ranges "$p_core")
com.facebook.katana{ComponentLavout}=$(format_cpu_ranges "$p_core")
com.facebook.katana=$(format_cpu_ranges "$e_core $p_core")

# Discord
com.discord{com.discord}=$(format_cpu_ranges "$p_core")
com.discord{pool-10-thread-*}=$(format_cpu_ranges "$p_core")
com.discord{RenderThread}=$(format_cpu_ranges "$p_core")
com.discord{mqt_js}=$(format_cpu_ranges "$p_core")
com.discord=$(format_cpu_ranges "$e_core $p_core")

# 动漫共和国
com.shizi.tool.p3{RenderThread}=$(format_cpu_ranges "$p_core")
com.shizi.tool.p3{imore.wallpaper}=$(format_cpu_ranges "$p_core")
com.shizi.tool.p3{glide-disk-cach}=$(format_cpu_ranges "$p_core")
com.shizi.tool.p3=$(format_cpu_ranges "$e_core $p_core")

#边缘视频
com.hjmore.wallpaper{imore.wallpaper}=$(format_cpu_ranges "$p_core")
com.hjmore.wallpaper{RenderThread}=$(format_cpu_ranges "$p_core")
com.hjmore.wallpaper{HeapTaskDaemon}=$(format_cpu_ranges "$p_core")
com.hjmore.wallpaper=$(format_cpu_ranges "$e_core $p_core")

# 网易云音乐
com.netease.cloudmusic{RenderThread}=$(format_cpu_ranges "$p_core")
com.netease.cloudmusic{ease.cloudmusic}=$(format_cpu_ranges "$p_core")
com.netease.cloudmusic{LooperTracer}=$(format_cpu_ranges "$p_core")
com.netease.cloudmusic=$(format_cpu_ranges "$e_core $p_core")

# 酷狗概念版
com.kugou.android.lite{ou.android.lite}=$(format_cpu_ranges "$p_core")
com.kugou.android.lite{RenderThread}=$(format_cpu_ranges "$p_core")
com.kugou.android.lite=$(format_cpu_ranges "$e_core $p_core")

# 酷我音乐
cn.kuwo.player{dMessageHandler}=$(format_cpu_ranges "$p_core")
cn.kuwo.player{RenderThread}=$(format_cpu_ranges "$p_core")
cn.kuwo.player{cdn.kuwo.cn*}=$(format_cpu_ranges "$p_core")
cn.kuwo.player{cn.kuwo.player}=$(format_cpu_ranges "$p_core")
cn.kuwo.player=$(format_cpu_ranges "$e_core $p_core")

# 汽水音乐
com.luna.music{*.music}=$(format_cpu_ranges "$p_core")
com.luna.music{RenderThread}=$(format_cpu_ranges "$p_core")
com.luna.music=$(format_cpu_ranges "$e_core $p_core")

# Salt Player
com.salt.music{com.salt.music}=$(format_cpu_ranges "$p_core")
com.salt.music{RenderThread}=$(format_cpu_ranges "$p_core")
com.salt.music=$(format_cpu_ranges "$e_core $p_core")

# 喜马拉雅
com.ximalaya.ting.android{ya.ting.android}=$(format_cpu_ranges "$p_core")
com.ximalaya.ting.android{RenderThread}=$(format_cpu_ranges "$p_core")
com.ximalaya.ting.android=$(format_cpu_ranges "$e_core $p_core")

# Apple Music
com.apple.android.music{*.music}=$(format_cpu_ranges "$p_core")
com.apple.android.music{RenderThread}=$(format_cpu_ranges "$p_core")
com.apple.android.music=$(format_cpu_ranges "$e_core $p_core")

# Lanerc
com.xuzly.hy.lanerc.app{Thread-*}=$(format_cpu_ranges "$p_core")
com.xuzly.hy.lanerc.app{1.ui}=$(format_cpu_ranges "$p_core")
com.xuzly.hy.lanerc.app{mpv/demux}=$(format_cpu_ranges "$p_core")
com.xuzly.hy.lanerc.app{1.raster}=$(format_cpu_ranges "$p_core")
com.xuzly.hy.lanerc.app=$(format_cpu_ranges "$e_core $p_core")

# 起点读书
com.qidian.QDReader{*.QDReader}=$(format_cpu_ranges "$p_core")
com.qidian.QDReader{RenderThread}=$(format_cpu_ranges "$p_core")
com.qidian.QDReader=$(format_cpu_ranges "$e_core $p_core")

# 番茄免费小说
com.dragon.read{RenderThread}=$(format_cpu_ranges "$p_core")
com.dragon.read{HeapTaskDaemon}=$(format_cpu_ranges "$p_core")
com.dragon.read{com.dragon.read}=$(format_cpu_ranges "$p_core")
com.dragon.read=$(format_cpu_ranges "$e_core $p_core")

# 七猫小说
com.kmxs.reader{*.reader}=$(format_cpu_ranges "$p_core")
com.kmxs.reader{RenderThread}=$(format_cpu_ranges "$p_core")
com.kmxs.reader=$(format_cpu_ranges "$e_core $p_core")

# 阅读(OSS)
io.legado.app.release{ado.app.release}=$(format_cpu_ranges "$p_core")
io.legado.app.release{RenderThread}=$(format_cpu_ranges "$p_core")
io.legado.app.release{binder*}=$(format_cpu_ranges "$p_core")
io.legado.app.release=$(format_cpu_ranges "$e_core $p_core")

#地图
# 高德地图  
com.autonavi.minimap{AJXBizCheck}=$(format_cpu_ranges "$p_core")  
com.autonavi.minimap{JavaScriptThrea}=$(format_cpu_ranges "$p_core")
com.autonavi.minimap{Map-Logical-0}=$(format_cpu_ranges "$p_core") 
com.autonavi.minimap{utonavi.minimap}=$(format_cpu_ranges "$p_core")
com.autonavi.minimap=$(format_cpu_ranges "$e_core $p_core")

# 百度地图  
com.baidu.BaiduMap{31.1_0223536945}=$(format_cpu_ranges "$p_core") 
com.baidu.BaiduMap{.31.1_062565145}=$(format_cpu_ranges "$p_core") 
com.baidu.BaiduMap{.baidu.BaiduMap}=$(format_cpu_ranges "$p_core") 
com.baidu.BaiduMap{*Thread}=$(format_cpu_ranges "$p_core") 
com.baidu.BaiduMap=$(format_cpu_ranges "$e_core $p_core")

#工具型
# 小猿搜题
com.fenbi.android.solar{i.android.solar}=$(format_cpu_ranges "$p_core")
com.fenbi.android.solar{RenderThread}=$(format_cpu_ranges "$p_core")
com.fenbi.android.solar{VizWebView}=$(format_cpu_ranges "$p_core")
com.fenbi.android.solar{Chrome_InProcGp}=$(format_cpu_ranges "$p_core")
com.fenbi.android.solar=$(format_cpu_ranges "$e_core $p_core")

# 快对AI
com.kuaiduizuoye.scan{aiduizuoye.scan}=$(format_cpu_ranges "$p_core")
com.kuaiduizuoye.scan{RenderThread}=$(format_cpu_ranges "$p_core")
com.kuaiduizuoye.scan{Chrome_IOThread}=$(format_cpu_ranges "$p_core")
com.kuaiduizuoye.scan=$(format_cpu_ranges "$e_core $p_core")

# 豆包
com.larus.nova{RenderThread}=$(format_cpu_ranges "$p_core")
com.larus.nova{com.larus.nova}=$(format_cpu_ranges "$p_core")
com.larus.nova{MediaLoad}=$(format_cpu_ranges "$p_core")
com.larus.nova=$(format_cpu_ranges "$e_core $p_core")

# 3Dmark
com.futuremark.dmandroid.application{Thread-??}=$(format_cpu_ranges "$hp_core")
com.futuremark.dmandroid.application{*binder}=$(format_cpu_ranges "$p_core")
com.futuremark.dmandroid.application=$(format_cpu_ranges "$e_core $p_core")

# chrome
com.android.chrome{RenderThread}=$(format_cpu_ranges "$p_core")
com.android.chrome{.android.chrome}=$(format_cpu_ranges "$p_core")
com.android.chrome=$(format_cpu_ranges "$e_core $p_core")

# via
mark.via{mark.via}=$(format_cpu_ranges "$p_core")
mark.via{RenderThread}=$(format_cpu_ranges "$p_core")
mark.via=$(format_cpu_ranges "$e_core $p_core")

# edge
com.microsoft.emmx{RenderThread}=$(format_cpu_ranges "$p_core")
com.microsoft.emmx{.microsoft.emmx}=$(format_cpu_ranges "$p_core")
com.microsoft.emmx{Thread-*}=$(format_cpu_ranges "$p_core")
com.microsoft.emmx{NetworkService}=$(format_cpu_ranges "$p_core")
com.microsoft.emmx{hwuiTask*}=$(format_cpu_ranges "$p_core")
com.microsoft.emmx=$(format_cpu_ranges "$e_core $p_core")

# 顺丰同城骑士
com.sfexpress.knight{fexpress.knight}=$(format_cpu_ranges "$p_core")
com.sfexpress.knight{RenderThread}=$(format_cpu_ranges "$p_core")
com.sfexpress.knight{binder}=$(format_cpu_ranges "$p_core")
com.sfexpress.knight=$(format_cpu_ranges "$e_core $p_core")

# 360极速浏览器
com.qihoo.contents{.qihoo.contents}=$(format_cpu_ranges "$p_core")
com.qihoo.contents{RenderThread}=$(format_cpu_ranges "$p_core")
com.qihoo.contents{Thread-*}=$(format_cpu_ranges "$p_core")
com.qihoo.contents{VizWebView}=$(format_cpu_ranges "$p_core")
com.qihoo.contents=$(format_cpu_ranges "$e_core $p_core")

# DeepSeek
com.deepseek.chat{m.deepseek.chat}=$(format_cpu_ranges "$p_core")
com.deepseek.chat{RenderThread}=$(format_cpu_ranges "$p_core")
com.deepseek.chat=$(format_cpu_ranges "$e_core $p_core")

# 铁路12306
com.MobileTicket{om.MobileTicket}=$(format_cpu_ranges "$p_core")
com.MobileTicket{RenderThread}=$(format_cpu_ranges "$p_core")
com.MobileTicket=$(format_cpu_ranges "$e_core $p_core")

# 同花顺
com.hexin.plat.android{in.plat.android}=$(format_cpu_ranges "$p_core")
com.hexin.plat.android{RenderThread}=$(format_cpu_ranges "$p_core")
com.hexin.plat.android{Thread*}=$(format_cpu_ranges "$p_core")
com.hexin.plat.android=$(format_cpu_ranges "$e_core $p_core")

# Breezy Weather
org.breezyweather{RenderThread}=$(format_cpu_ranges "$p_core")
org.breezyweather{g.breezyweather}=$(format_cpu_ranges "$p_core")
org.breezyweather{Binder:*}=$(format_cpu_ranges "$p_core")
org.breezyweather=$(format_cpu_ranges "$e_core $p_core")

# 今日水印相机
com.xhey.xcamera{om.xhey.xcamera}=$(format_cpu_ranges "$p_core")
com.xhey.xcamera{Algorithm-}=$(format_cpu_ranges "$p_core")
com.xhey.xcamera{RxCachedThreadS}=$(format_cpu_ranges "$hp_core")
com.xhey.xcamera=$(format_cpu_ranges "$e_core $p_core")

#玩机软件
# Noactive
cn.myflv.noactive{.myflv.noactive}=$(format_cpu_ranges "$p_core")
cn.myflv.noactive{RenderThread}=$(format_cpu_ranges "$p_core")
cn.myflv.noactive=$(format_cpu_ranges "$e_core $p_core")

#System
# 将QQ音乐主进程绑定e_core
com.tencent.qqmusic=$(format_cpu_ranges "$e_core")

# 将微信输入法进程绑定e_core
com.tencent.wetype:play=$(format_cpu_ranges "$e_core")

# 将酷狗音乐后台播放的子进程绑定e_core
com.kugou.android.support=$(format_cpu_ranges "$e_core")
com.kugou.android.message=$(format_cpu_ranges "$e_core")

# 将Push消息推送进程绑定e_core
com.tencent.mm:push=$(format_cpu_ranges "$e_core")
com.luna.music:push=$(format_cpu_ranges "$e_core")
com.ss.android.ugc.aweme.mobile:push=$(format_cpu_ranges "$e_core")
com.bilibili.app.in:pushservice=$(format_cpu_ranges "$e_core")
tv.danmaku.bilibilihd:pushservice=$(format_cpu_ranges "$e_core")
tv.danmaku.bili:pushservice=$(format_cpu_ranges "$e_core")
com.tencent.mobileqq:MSF=$(format_cpu_ranges "$e_core")
com.tencent.tim:MSF=$(format_cpu_ranges "$e_core")
com.alibaba.android.rimet:push=$(format_cpu_ranges "$e_core")

# 系统桌面
com.android.launcher{RenderThread}=$(format_cpu_ranges "$p_core")
com.android.launcher{*.launcher}=$(format_cpu_ranges "$p_core")
com.android.launcher{binder*}=$(format_cpu_ranges "$p_core")
com.android.launcher=$(format_cpu_ranges "$e_core $p_core")

# pixel启动器
com.google.android.apps.nexuslauncher{RenderThread}=$(format_cpu_ranges "$p_core")
com.google.android.apps.nexuslauncher{s.nexuslauncher}=$(format_cpu_ranges "$p_core")
com.google.android.apps.nexuslauncher{binder*}=$(format_cpu_ranges "$p_core")
com.google.android.apps.nexuslauncher=$(format_cpu_ranges "$e_core $p_core")

# launcher3
com.android.launcher3{RenderThread}=$(format_cpu_ranges "$p_core")
com.android.launcher3{*.launcher3}=$(format_cpu_ranges "$p_core")
com.android.launcher3{binder*}=$(format_cpu_ranges "$p_core")
com.android.launcher3=$(format_cpu_ranges "$e_core $p_core")

# oneuilauncher
com.sec.android.app.launcher{RenderThread}=$(format_cpu_ranges "$p_core")
com.sec.android.app.launcher{id.app.launcher}=$(format_cpu_ranges "$p_core")
com.sec.android.app.launcher{binder*}=$(format_cpu_ranges "$p_core")
com.sec.android.app.launcher=$(format_cpu_ranges "$e_core $p_core")

# flyme桌面
com.meizu.flyme.launcher{.flyme.launcher}=$(format_cpu_ranges "$p_core")
com.meizu.flyme.launcher{binder*}=$(format_cpu_ranges "$p_core")
com.meizu.flyme.launcher{RenderThread}=$(format_cpu_ranges "$p_core")
com.meizu.flyme.launcher=$(format_cpu_ranges "$e_core $p_core")

# MIUI桌面
com.miui.home{com.miui.home}=$(format_cpu_ranges "$p_core")
com.miui.home{RenderThread}=$(format_cpu_ranges "$hp_core")
com.miui.home{binder*}=$(format_cpu_ranges "$p_core")
com.miui.home=$(format_cpu_ranges "$e_core $p_core")
"

game_rules="
#Game
# 王者荣耀
com.tencent.tmgp.sgame{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.sgame{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.sgame{Thread*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.sgame{Job.worker*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.sgame{CoreThread}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.sgame=$(format_cpu_ranges "$e_core $p_core")
com.levelinfinite.sgameGlobal.midaspay{UnityMain}=$(format_cpu_ranges "$hp_core")
com.levelinfinite.sgameGlobal.midaspay{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.levelinfinite.sgameGlobal.midaspay{Thread*}=$(format_cpu_ranges "$p_core")
com.levelinfinite.sgameGlobal.midaspay{Job.worker*}=$(format_cpu_ranges "$p_core")
com.levelinfinite.sgameGlobal.midaspay{CoreThread}=$(format_cpu_ranges "$p_core")
com.levelinfinite.sgameGlobal.midaspay=$(format_cpu_ranges "$e_core $p_core")

# 和平精英
com.tencent.tmgp.pubgmhd{Thread-*}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.pubgmhd{RHIThread}=$(format_cpu_ranges "$p_core $hp_core")
com.tencent.tmgp.pubgmhd{TaskGraphNP*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.pubgmhd{RenderThread*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.pubgmhd=$(format_cpu_ranges "$e_core $p_core")

# PUBGM (GLO,GLOCE,TW)
com.tencent.ig{UEGameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.ig{RHIThread}=$(format_cpu_ranges "$p_core")
com.tencent.ig{TaskGraphNP*}=$(format_cpu_ranges "$p_core")
com.tencent.ig{MainThread-UE4}=$(format_cpu_ranges "$p_core")
com.tencent.ig=$(format_cpu_ranges "$e_core $p_core")
com.tencent.igce{UEGameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.igce{RHIThread}=$(format_cpu_ranges "$p_core")
com.tencent.igce{TaskGraphNP*}=$(format_cpu_ranges "$p_core")
com.tencent.igce{MainThread-UE4}=$(format_cpu_ranges "$p_core")
com.tencent.igce=$(format_cpu_ranges "$e_core $p_core")
com.rekoo.pubgm{UEGameThread}=$(format_cpu_ranges "$hp_core")
com.rekoo.pubgm{RHIThread}=$(format_cpu_ranges "$p_core")
com.rekoo.pubgm{TaskGraphNP*}=$(format_cpu_ranges "$p_core")
com.rekoo.pubgm{MainThread-UE4}=$(format_cpu_ranges "$p_core")
com.rekoo.pubgm=$(format_cpu_ranges "$e_core $p_core")

# 使命召唤手游
com.tencent.tmgp.cod{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.cod{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.cod{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.cod{Job.worker*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.cod{Audio*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.cod=$(format_cpu_ranges "$e_core $p_core")

# 英雄联盟
com.tencent.lolm{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.lolm{LogicThread}=$(format_cpu_ranges "$p_core")
com.tencent.lolm{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.lolm{NativeThread}=$(format_cpu_ranges "$p_core")
com.tencent.lolm=$(format_cpu_ranges "$e_core $p_core")

# 金铲铲之战
com.tencent.jkchess{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.jkchess{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.jkchess{LogicThread}=$(format_cpu_ranges "$p_core")
com.tencent.jkchess=$(format_cpu_ranges "$e_core $p_core")

# 明日方舟
com.hypergryph.arknights{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.hypergryph.arknights{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.hypergryph.arknights{Thread-*}=$(format_cpu_ranges "$p_core")
com.hypergryph.arknights{Job.worker*}=$(format_cpu_ranges "$p_core")
com.hypergryph.arknights{Audio*}=$(format_cpu_ranges "$e_core $p_core")
com.hypergryph.arknights=$(format_cpu_ranges "$p_core")
com.hypergryph.arknights.bilibili{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.hypergryph.arknights.bilibili{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.hypergryph.arknights.bilibili{Thread-*}=$(format_cpu_ranges "$p_core")
com.hypergryph.arknights.bilibili{Job.worker*}=$(format_cpu_ranges "$p_core")
com.hypergryph.arknights.bilibili{Audio*}=$(format_cpu_ranges "$e_core $p_core")
com.hypergryph.arknights.bilibili=$(format_cpu_ranges "$e_core $p_core")

# 原神
com.miHoYo.Yuanshen{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.miHoYo.Yuanshen{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.miHoYo.Yuanshen{Thread-*}=$(format_cpu_ranges "$p_core")
com.miHoYo.Yuanshen{Job.worker*}=$(format_cpu_ranges "$p_core")
com.miHoYo.Yuanshen=$(format_cpu_ranges "$e_core $p_core")
com.miHoYo.GenshinImpact{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.miHoYo.GenshinImpact{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.miHoYo.GenshinImpact{Thread-*}=$(format_cpu_ranges "$p_core")
com.miHoYo.GenshinImpact{Job.worker*}=$(format_cpu_ranges "$p_core")
com.miHoYo.GenshinImpact=$(format_cpu_ranges "$e_core $p_core")
com.miHoYo.ys.bilibili{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.miHoYo.ys.bilibili{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.miHoYo.ys.bilibili{Thread-*}=$(format_cpu_ranges "$p_core")
com.miHoYo.ys.bilibili{Job.worker*}=$(format_cpu_ranges "$p_core")
com.miHoYo.ys.bilibili=$(format_cpu_ranges "$e_core $p_core")
com.miHoYo.ys.mi{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.miHoYo.ys.mi{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.miHoYo.ys.mi{Thread-*}=$(format_cpu_ranges "$p_core")
com.miHoYo.ys.mi{Job.worker*}=$(format_cpu_ranges "$p_core")
com.miHoYo.ys.mi=$(format_cpu_ranges "$e_core $p_core")

# 崩坏:星穹铁道
com.miHoYo.hkrpg{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.miHoYo.hkrpg{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.miHoYo.hkrpg{Thread-*}=$(format_cpu_ranges "$p_core")
com.miHoYo.hkrpg{Job.worker*}=$(format_cpu_ranges "$p_core")
com.miHoYo.hkrpg=$(format_cpu_ranges "$e_core $p_core")
com.miHoYo.hkrpg.bilibili{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.miHoYo.hkrpg.bilibili{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.miHoYo.hkrpg.bilibili{Thread-*}=$(format_cpu_ranges "$p_core")
com.miHoYo.hkrpg.bilibili{Job.worker*}=$(format_cpu_ranges "$p_core")
com.miHoYo.hkrpg.bilibili=$(format_cpu_ranges "$e_core $p_core")
com.HoYoverse.hkrpgoversea{UnityMain*}=$(format_cpu_ranges "$hp_core")
com.HoYoverse.hkrpgoversea{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.HoYoverse.hkrpgoversea{Thread-*}=$(format_cpu_ranges "$p_core")
com.HoYoverse.hkrpgoversea{Job.worker*}=$(format_cpu_ranges "$p_core")
com.HoYoverse.hkrpgoversea=$(format_cpu_ranges "$e_core $p_core")

# 绝区零
com.miHoYo.Nap{UnityMain}=$(format_cpu_ranges "$hp_core")
com.miHoYo.Nap{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.miHoYo.Nap{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.miHoYo.Nap{NativeThread}=$(format_cpu_ranges "$p_core")
com.miHoYo.Nap{Thread-*}=$(format_cpu_ranges "$p_core")
com.miHoYo.Nap=$(format_cpu_ranges "$e_core $p_core")
com.HoYoverse.Nap{UnityMain}=$(format_cpu_ranges "$hp_core")
com.HoYoverse.Nap{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.HoYoverse.Nap{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.HoYoverse.Nap{NativeThread}=$(format_cpu_ranges "$p_core")
com.HoYoverse.Nap{Thread-*}=$(format_cpu_ranges "$p_core")
com.HoYoverse.Nap=$(format_cpu_ranges "$e_core $p_core")
com.mihoyo.nap.bilibili{UnityMain}=$(format_cpu_ranges "$hp_core")
com.mihoyo.nap.bilibili{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.mihoyo.nap.bilibili{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.mihoyo.nap.bilibili{NativeThread}=$(format_cpu_ranges "$p_core")
com.mihoyo.nap.bilibili{Thread-*}=$(format_cpu_ranges "$p_core")
com.mihoyo.nap.bilibili=$(format_cpu_ranges "$e_core $p_core")

# 鸣潮
com.kurogame.mingchao{GameThread}=$(format_cpu_ranges "$hp_core")
com.kurogame.mingchao{RHIThread}=$(format_cpu_ranges "$p_core")
com.kurogame.mingchao{RenderThread*}=$(format_cpu_ranges "$p_core")
com.kurogame.mingchao{NativeThread}=$(format_cpu_ranges "$p_core")
com.kurogame.mingchao=$(format_cpu_ranges "$e_core $p_core")

# CFM
com.tencent.tmgp.cf{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.cf{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.cf{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.cf=$(format_cpu_ranges "$e_core $p_core")

# 火影忍者
com.tencent.KiHan{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.KiHan{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.tencent.KiHan{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.tencent.KiHan=$(format_cpu_ranges "$e_core $p_core")

# 三角洲行动
com.tencent.tmgp.dfm{GameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.dfm{RenderThread}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.dfm{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.dfm{TaskGraphNP*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.dfm{NativeThread}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.dfm=$(format_cpu_ranges "$e_core $p_core")
com.proxima.dfm{GameThread}=$(format_cpu_ranges "$hp_core")
com.proxima.dfm{RenderThread}=$(format_cpu_ranges "$p_core")
com.proxima.dfm{Thread-*}=$(format_cpu_ranges "$p_core")
com.proxima.dfm{TaskGraphNP*}=$(format_cpu_ranges "$p_core")
com.proxima.dfm{NativeThread}=$(format_cpu_ranges "$p_core")
com.proxima.dfm=$(format_cpu_ranges "$e_core $p_core")

# 妮姬：新的希望
com.tencent.nikke{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.nikke{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.nikke{UnityChoreograp}=$(format_cpu_ranges "$p_core")
com.tencent.nikke=$(format_cpu_ranges "$e_core $p_core")

# NIKKE
com.gamamobi.nikke{UnityMain}=$(format_cpu_ranges "$hp_core")
com.gamamobi.nikke{Thread-*}=$(format_cpu_ranges "$p_core")
com.gamamobi.nikke{UnityChoreograp}=$(format_cpu_ranges "$p_core")
com.gamamobi.nikke{FMOD*}=$(format_cpu_ranges "$p_core")
com.gamamobi.nikke=$(format_cpu_ranges "$e_core $p_core")
com.proximabeta.nikke{UnityMain}=$(format_cpu_ranges "$hp_core")
com.proximabeta.nikke{Thread-*}=$(format_cpu_ranges "$p_core")
com.proximabeta.nikke{UnityChoreograp}=$(format_cpu_ranges "$p_core")
com.proximabeta.nikke{FMOD*}=$(format_cpu_ranges "$p_core")
com.proximabeta.nikke=$(format_cpu_ranges "$e_core $p_core")

# 荒野乱斗
com.tencent.tmgp.supercell.brawlstars{Mainloop}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.supercell.brawlstars{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.supercell.brawlstars=$(format_cpu_ranges "$e_core $p_core")

# 无畏契约
com.tencent.tmgp.codev{GameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.codev{RenderThread}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.codev{NativeThread}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.codev=$(format_cpu_ranges "$e_core $p_core")

# BlueArchive(GLO)
com.nexon.bluearchive{xon.bluearchive}=$(format_cpu_ranges "$hp_core")
com.nexon.bluearchive{UnityMain}=$(format_cpu_ranges "$p_core")
com.nexon.bluearchive{UnityGfxDeviceW10}=$(format_cpu_ranges "$p_core")
com.nexon.bluearchive{UnityChoreograp}=$(format_cpu_ranges "$p_core")
com.nexon.bluearchive=$(format_cpu_ranges "$e_core $p_core")

# 少女前线2:追放
com.Sunborn.SnqxExilium{UnityMain}=$(format_cpu_ranges "$hp_core")
com.Sunborn.SnqxExilium{UnityGfx*}=$(format_cpu_ranges "$p_core")
com.Sunborn.SnqxExilium{Job.[Ww]orker*}=$(format_cpu_ranges "$p_core")
com.Sunborn.SnqxExilium{Thread-*}=$(format_cpu_ranges "$p_core")
com.Sunborn.SnqxExilium=$(format_cpu_ranges "$e_core $p_core")

# DNF
com.tencent.tmgp.dnf{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.dnf{Thread-[0-9]*}=$(format_cpu_ranges "$e_core $p_core")
com.tencent.tmgp.dnf{UnityChoreograp}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.dnf{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.dnf=$(format_cpu_ranges "$e_core $p_core")

# 皇室战争
com.tencent.tmgp.supercell.clashroyale{Mainloop}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.supercell.clashroyale{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.supercell.clashroyale{FMOD_mixer_thre}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.supercell.clashroyale=$(format_cpu_ranges "$e_core $p_core")

# 荒野乱斗
com.tencent.tmgp.supercell.brawlstars{Mainloop}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.supercell.brawlstars{FMOD_mixer_thre}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.supercell.brawlstars{Thread-*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.supercell.brawlstars=$(format_cpu_ranges "$e_core $p_core")

# 尘白禁区
com.dragonli.projectsnow.lhm{RHIThread}=$(format_cpu_ranges "$hp_core")
com.dragonli.projectsnow.lhm{RenderThread*}=$(format_cpu_ranges "$p_core")
com.dragonli.projectsnow.lhm{GameThread}=$(format_cpu_ranges "$p_core")
com.dragonli.projectsnow.lhm=$(format_cpu_ranges "$e_core $p_core")

# 巅峰极速
com.netease.race{RHIThread}=$(format_cpu_ranges "$hp_core")
com.netease.race{GameThread}=$(format_cpu_ranges "$e_core $p_core")
com.netease.race{RenderThread}=$(format_cpu_ranges "$e_core $p_core")
com.netease.race{Thread-*}=$(format_cpu_ranges "$p_core")
com.netease.race=$(format_cpu_ranges "$e_core $p_core")

# qq飞车
com.tencent.tmgp.speedmobile{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.speedmobile{Thread-*}=$(format_cpu_ranges "$e_core $p_core")
com.tencent.tmgp.speedmobile{UnityGfxRenderS}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.speedmobile{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.speedmobile=$(format_cpu_ranges "$e_core $p_core")

# 雀魂
com.soulgamechst.majsoul{Thread-??}=$(format_cpu_ranges "$e_core")      #垃圾线程
com.soulgamechst.majsoul{UnityMain}=$(format_cpu_ranges "$hp_core")
com.soulgamechst.majsoul{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.soulgamechst.majsoul=$(format_cpu_ranges "$e_core $p_core")

# 崩坏3(官服)
com.miHoYo.enterprise.NGHSoD{UnityMain}=$(format_cpu_ranges "$hp_core")
com.miHoYo.enterprise.NGHSoD{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.miHoYo.enterprise.NGHSoD{NativeThread}=$(format_cpu_ranges "$p_core")
com.miHoYo.enterprise.NGHSoD=$(format_cpu_ranges "$e_core $p_core")

# 多乐够级(HW)
com.k7k7.goujihd.huawei{GLThread*}=$(format_cpu_ranges "$hp_core")
com.k7k7.goujihd.huawei{AudioTrack}=$(format_cpu_ranges "$p_core")
com.k7k7.goujihd.huawei{binder*}=$(format_cpu_ranges "$p_core")
com.k7k7.goujihd.huawei{Thread*}=$(format_cpu_ranges "$p_core")
com.k7k7.goujihd.huawei=$(format_cpu_ranges "$e_core $p_core")

# 暗区突围
com.tencent.mf.uam{GameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.mf.uam{RenderThread*}=$(format_cpu_ranges "$p_core")
com.tencent.mf.uam{RHIThread}=$(format_cpu_ranges "$p_core")
com.tencent.mf.uam{com.tencent.mf.uam}=$(format_cpu_ranges "$p_core")
com.tencent.mf.uam=$(format_cpu_ranges "$e_core $p_core")

# 枪火重生
com.duoyi.m2m1{UnityMain}=$(format_cpu_ranges "$hp_core")
com.duoyi.m2m1{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.duoyi.m2m1{Job.Worker}=$(format_cpu_ranges "$p_core")
com.duoyi.m2m1{NativeThread }=$(format_cpu_ranges "$p_core")
com.duoyi.m2m1{AudioTrack}=$(format_cpu_ranges "$p_core")
com.duoyi.m2m1=$(format_cpu_ranges "$e_core $p_core")

# 皇室战争 GLO
com.supercell.clashroyale{Mainloop}=$(format_cpu_ranges "$hp_core")
com.supercell.clashroyale{FMOD mixer thre}=$(format_cpu_ranges "$p_core")
com.supercell.clashroyale{Thread*}=$(format_cpu_ranges "$p_core")
com.supercell.clashroyale{Binder*}=$(format_cpu_ranges "$p_core")
com.supercell.clashroyale{AudioTrack}=$(format_cpu_ranges "$p_core")
com.supercell.clashroyale=$(format_cpu_ranges "$e_core $p_core")

# SMAPI Launcher(星露谷物语)
abc.ningban.gameloades{gban.gameloades}=$(format_cpu_ranges "$hp_core")
abc.ningban.gameloades{.NET_Long_Runni}=$(format_cpu_ranges "$p_core")
abc.ningban.gameloades{AudioTrack}=$(format_cpu_ranges "$p_core")
abc.ningban.gameloades{Thread-*}=$(format_cpu_ranges "$e_core") 
#垃圾线程
abc.ningban.gameloades=$(format_cpu_ranges "$e_core $p_core")

# 洛克王国
com.tencent.nrc{GameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.nrc{RHIThread}=$(format_cpu_ranges "$p_core")
com.tencent.nrc{RenderThread*}=$(format_cpu_ranges "$p_core")
com.tencent.nrc{TaskGraphHP*}=$(format_cpu_ranges "$p_core")
com.tencent.nrc=$(format_cpu_ranges "$e_core $p_core")

# 决胜巅峰
com.dfjz.moba.kuaishou{UnityMain}=$(format_cpu_ranges "$hp_core")
com.dfjz.moba.kuaishou{dfp-1-thread-4}=$(format_cpu_ranges "$p_core")
com.dfjz.moba.kuaishou{Thread*}=$(format_cpu_ranges "$p_core")
com.dfjz.moba.kuaishou{*Thread}=$(format_cpu_ranges "$p_core")
com.dfjz.moba.kuaishou=$(format_cpu_ranges "$e_core $p_core")

# 香肠派对
com.sofunny.sausage{UnityMain}=$(format_cpu_ranges "$hp_core")
com.sofunny.sausage{Thread*}=$(format_cpu_ranges "$p_core")
com.sofunny.sausage{Job.Worker*}=$(format_cpu_ranges "$hp_core")
com.sofunny.sausage=$(format_cpu_ranges "$e_core $p_core")

# 逆战:未来
com.tencent.tmgp.nz{GameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.nz{RenderThread}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.nz{TaskGraphNP}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.nz{Thread*}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.nz=$(format_cpu_ranges "$e_core $p_core")

# 明日方舟:终末地
com.hypergryph.endfield{UnityMain}=$(format_cpu_ranges "$hp_core")
com.hypergryph.endfield{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.hypergryph.endfield{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.hypergryph.endfield{Thread*}=$(format_cpu_ranges "$p_core")
com.hypergryph.endfield=$(format_cpu_ranges "$e_core $p_core")

# 战争雷霆
com.gaijingames.wtm{gaijingames.wtm}=$(format_cpu_ranges "$hp_core $p_core")
com.gaijingames.wtm{AudioTrack}=$(format_cpu_ranges "$p_core")
com.gaijingames.wtm=$(format_cpu_ranges "$e_core $p_core")

# 失控进化
com.tencent.rmcn{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.rmcn{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.tencent.rmcn{Thread*}=$(format_cpu_ranges "$p_core")
com.tencent.rmcn{AudioTrack}=$(format_cpu_ranges "$p_core")
com.tencent.rmcn=$(format_cpu_ranges "$e_core $p_core")

# 开门就是仙侠世界
com.LoongCharm.infinityworld{GLThread*}=$(format_cpu_ranges "$hp_core")
com.LoongCharm.infinityworld{V8 DefaultWorke}=$(format_cpu_ranges "$p_core")
com.LoongCharm.infinityworld{m.infinityworld}=$(format_cpu_ranges "$p_core")
com.LoongCharm.infinityworld=$(format_cpu_ranges "$e_core $p_core")

# 迷你世界(4399)
com.minitech.miniworld.m4399{Thread*}=$(format_cpu_ranges "$e_core")
com.minitech.miniworld.m4399{MiniRainbowMain}=$(format_cpu_ranges "$hp_core")
com.minitech.miniworld.m4399{MiniRenderThrea}=$(format_cpu_ranges "$p_core")
com.minitech.miniworld.m4399{miniworld.m4399}=$(format_cpu_ranges "$p_core")
com.minitech.miniworld.m4399=$(format_cpu_ranges "$e_core $p_core")

# 棕色尘埃2
com.neowizgames.game.browndust2{UnityMain}=$(format_cpu_ranges "$hp_core")
com.neowizgames.game.browndust2{Thread-*}=$(format_cpu_ranges "$p_core $hp_core")
com.neowizgames.game.browndust2{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.neowizgames.game.browndust2=$(format_cpu_ranges "$e_core $p_core")

# Roblox
com.roblox.client{Thread-*}=$(format_cpu_ranges "$hp_core")
com.roblox.client{RBX Worker A}=$(format_cpu_ranges "$p_core")
com.roblox.client{RBX Worker B}=$(format_cpu_ranges "$p_core")
com.roblox.client=$(format_cpu_ranges "$e_core $p_core")

# 妄想山海
com.tencent.tmgp.djsy{Thread-*}=$(format_cpu_ranges "$hp_core")
com.tencent.tmgp.djsy{ncent.tmgp.djsy}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.djsy{MainThread}=$(format_cpu_ranges "$p_core")
com.tencent.tmgp.djsy=$(format_cpu_ranges "$e_core $p_core")

# 鹅鸭杀
com.seayoo.ggd{UnityMain}=$(format_cpu_ranges "$hp_core")
com.seayoo.ggd{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.seayoo.ggd{liteav_audio_pr}=$(format_cpu_ranges "$p_core")
com.seayoo.ggd=$(format_cpu_ranges "$e_core $p_core")

# 洛克王国:世界
com.tencent.nrc{GameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.nrc{RHIThread}=$(format_cpu_ranges "$p_core")
com.tencent.nrc{RenderThread*}=$(format_cpu_ranges "$p_core")
com.tencent.nrc{TaskGraphHP*}=$(format_cpu_ranges "$p_core")
com.tencent.nrc=$(format_cpu_ranges "$e_core $p_core")

# 萤火突击
com.netease.yhtj{Game*}=$(format_cpu_ranges "$hp_core")
com.netease.yhtj{ALooperThread}=$(format_cpu_ranges "$p_core")
com.netease.yhtj{om.netease.yhtj}=$(format_cpu_ranges "$p_core")
com.netease.yhtj{MainThread*}=$(format_cpu_ranges "$p_core")
com.netease.yhtj=$(format_cpu_ranges "$e_core $p_core")

# 王者荣耀世界
com.tencent.ngr{GameThread}=$(format_cpu_ranges "$hp_core")
com.tencent.ngr{RHIThread}=$(format_cpu_ranges "$p_core")
com.tencent.ngr{RenderThread}=$(format_cpu_ranges "$p_core")
com.tencent.ngr{TaskGraphHP*}=$(format_cpu_ranges "$p_core")
com.tencent.ngr=$(format_cpu_ranges "$e_core $p_core")

# 异环
com.hottagames.yh.laohu{RHIThread}=$(format_cpu_ranges "$hp_core")
com.hottagames.yh.laohu{GameThread}=$(format_cpu_ranges "$p_core")
com.hottagames.yh.laohu{Render Thread}=$(format_cpu_ranges "$p_core")
com.hottagames.yh.laohu{Foregro-rker*}=$(format_cpu_ranges "$p_core")
com.hottagames.yh.laohu=$(format_cpu_ranges "$e_core $p_core")

# PlantsVsZombiesRH
com.LanPiaoPiao.PlantsVsZombiesRH{UnityMain}=$(format_cpu_ranges "$hp_core")
com.LanPiaoPiao.PlantsVsZombiesRH{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.LanPiaoPiao.PlantsVsZombiesRH{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.LanPiaoPiao.PlantsVsZombiesRH=$(format_cpu_ranges "$e_core $p_core")

# 魂斗罗:归来
com.tencent.shootgame{UnityMain}=$(format_cpu_ranges "$hp_core")
com.tencent.shootgame{UnityGfxDeviceW}=$(format_cpu_ranges "$p_core")
com.tencent.shootgame{Job.Worker*}=$(format_cpu_ranges "$p_core")
com.tencent.shootgame{Thread*}=$(format_cpu_ranges "$p_core")
com.tencent.shootgame=$(format_cpu_ranges "$e_core $p_core")
"

echo "$common_rules" >> $MODPATH/applist.conf
if [ "$MODE_VAL" = "mix" ]; then
	echo "$game_rules" >> $MODPATH/applist.conf
fi
if [ -f /data/adb/modules/AppOpt/applist.conf ]; then
	mv /data/adb/modules/AppOpt/applist.conf /data/adb/modules/AppOpt/applist.conf.bak
	cp -r $MODPATH/applist.conf /data/adb/modules/AppOpt/
fi
}
generate_cpuinfo() {
	ui_print "********************************************"
	ui_print "- 正在写入SOC信息"

	local val_hp=$(format_cpu_ranges "$hp_core")
	local val_e=$(format_cpu_ranges "$e_core")
	local val_ep=$(format_cpu_ranges "$e_core $p_core")
	local val_p=$(format_cpu_ranges "$p_core")
	local val_ph=$(format_cpu_ranges "$p_core $hp_core")

	cat >> "$MODPATH/config.txt" << cpuEOF
(format_cpu_ranges "\$hp_core")=$val_hp
(format_cpu_ranges "\$e_core")=$val_e
(format_cpu_ranges "\$e_core \$p_core")=$val_ep
(format_cpu_ranges "\$p_core")=$val_p
(format_cpu_ranges "\$p_core \$hp_core")=$val_ph
cpuEOF

	ui_print "- 已写入至: $MODPATH/config.txt"
}
check_magisk_version
check_required_files
extract_bin
remove_sys_perf_config
choose_mode
generate_cpuinfo
add_default_rules
module_instructions
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/*.sh $MODPATH/AppOpt" 0 2000 0755 0755 u:object_r:magisk_file:s0