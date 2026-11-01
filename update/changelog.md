## 8.0

- 合并 Common 与 8G3 为单一自动适配模块。
- 安装时识别 SM8650/pineapple，并在 `confige.txt` 写入 `8G3=on/off`。
- Action 根据 SoC 标记下载 8G3 或 Common 配置，并保留 App/Mix 模式。
- Common 规则下载后原样写入 `applist.conf`，不再执行核心编号转换。
- 同步 AkiAppOpt `Aki-1.2.0(207-73620e2)` 三架构成品。
- 同步实例锁、崩溃退避重启和有界日志，保留 KernelSU late-load、显式配置路径和配置热加载支持。
- 模块 ID 和安装目录保持 `AppOpt`，cpuset 目录使用 `/dev/cpuset/AkiAppOpt`。
- 首次升级时完整保留现有 `applist.conf`；建立默认规则基线后，三方合并保留用户增删改。
