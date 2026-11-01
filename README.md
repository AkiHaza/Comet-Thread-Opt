# Comet-Thread-Opt

基于 [AkiAppOpt](https://github.com/AkiHaza/AkiAppOpt) 的 Android 应用线程 CPU 亲和性配置模块。

## 自动适配

仓库已将原 `Common` 与 `8G3` 两个模块合并为 `module/`：

- 安装时读取 `ro.soc.model`、`ro.board.platform` 和 `ro.hardware`。
- 检测到 `SM8650` 或 `pineapple` 时，在 `confige.txt` 写入 `8G3=on`。
- 其他 SoC 写入 `8G3=off`，使用 Common 语义核心规则。
- 音量上选择 App 模式，音量下选择 App+Game 的 Mix 模式。
- 安装后点击 Magisk 模块操作按钮即可按设备类型和模式更新规则，下载内容原样写入 `applist.conf`。

模块 ID 为 `AppOpt`，安装目录为 `/data/adb/modules/AppOpt`；运行时 cpuset 目录保持 `/dev/cpuset/AkiAppOpt`。设备配置 `confige.txt` 由安装脚本自动生成。首次从旧版升级时完整保留现有规则；已有默认规则基线后，后续升级使用三方合并更新默认规则，同时保留用户的新增、修改和删除。

## 目录

```text
module/                    统一 Magisk 模块
module/AppOpt.c             同步的 AkiAppOpt 源码
module/bin/arm64-v8a/       ARM64 成品
module/bin/armeabi-v7a/     ARM32 成品
module/bin/x86_64/          x86-64 成品
module/bin/SHA256SUMS       成品 SHA256 校验清单
module/config_merge.awk     升级时的规则三方合并
update/                    在线更新元数据
.github/workflows/         校验成品、检查脚本并打包模块
```

## 源码与成品

- 源码同步自 `AkiHaza/AkiAppOpt` 的 `Dev` 分支提交 `73620e2a677cadf1f3d4ebab2ba97ec797a35ff4`，与本次 1.2.0 成品对应，保留在 `module/AppOpt.c` 供源码追溯。
- 运行程序使用用户提供的 `AppOpt-Aki-1.2.0(207-73620e2)-207.zip` 中的成品，版本为 `Aki-1.2.0(207-73620e2)`，版本码为 `207`。
- 压缩包中的 ARM32 目录 `armabi-v7a` 映射到本仓库既有的 `armeabi-v7a` 目录，程序内容保持不变。模块仍沿用 `AppOpt` 标识。
- CI 使用 `module/bin/SHA256SUMS` 校验三种架构的成品，并对模块脚本执行 `sh -n` 语法检查；校验通过后按原目录结构打包，不重新编译程序。源码仅保留在仓库中，不进入安装包。
- 启动脚本同步上游 watchdog、服务锁和有界日志支持，包含 KernelSU late-load 的实例清理与恢复。

## 规则类型

- App：日常应用线程规则。
- Game：游戏线程规则，仅在 Mix 模式下追加。
- 8G3：针对 Snapdragon 8 Gen 3 的固定核心编号规则。
- Common：通用规则会从远端原样写入配置文件，理论上支持多种 SoC。

规则文件修改后由 AkiAppOpt 热加载，无需重启。

## 其他事项

- [SutoLiu 酷安主页](http://www.coolapk.com/u/1842370)
- [作者酷安主页](http://www.coolapk.com/u/27195819)
- [Telegram](https://t.me/RealSimokio)

提交适配时请附上应用或游戏包名、实时线程信息及帧率记录。
