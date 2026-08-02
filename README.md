# Comet-Thread-Opt

基于 [AkiAppOpt](https://github.com/AkiHaza/AkiAppOpt) 的 Android 应用线程 CPU 亲和性配置模块。

## 自动适配

仓库已将原 `Common` 与 `8G3` 两个模块合并为 `module/`：

- 安装时读取 `ro.soc.model`、`ro.board.platform` 和 `ro.hardware`。
- 检测到 `SM8650` 或 `pineapple` 时，在 `confige.txt` 写入 `8G3=on`。
- 其他 SoC 写入 `8G3=off`，使用 Common 语义核心规则。
- 音量上选择 App 模式，音量下选择 App+Game 的 Mix 模式。
- 安装后点击 Magisk 模块操作按钮即可按设备类型和模式更新规则。

Common 规则中的旧核心占位符会转换为 AkiAppOpt 原生支持的 `e-core`、`p-core`、`hp-core`，不再保存或读取具体核心簇编号。

## 目录

```text
module/              统一 Magisk 模块
update/              在线更新元数据
.github/workflows/   使用 AkiAppOpt 源码构建并打包模块
```

## 规则类型

- App：日常应用线程规则。
- Game：游戏线程规则，仅在 Mix 模式下追加。
- 8G3：针对 Snapdragon 8 Gen 3 的固定核心编号规则。
- Common：使用语义核心的通用规则，理论上支持多种 SoC。

规则文件修改后由 AkiAppOpt 热加载，无需重启。

## 其他事项

- [SutoLiu 酷安主页](http://www.coolapk.com/u/1842370)
- [作者酷安主页](http://www.coolapk.com/u/27195819)
- [Telegram](https://t.me/RealSimokio)

提交适配时请附上应用或游戏包名、实时线程信息及帧率记录。
