## 8.0

- 合并 Common 与 8G3 为单一自动适配模块。
- 安装与 Action 共用 SoC/核数检测：仅 SM8650/pineapple 且 CPU 编号为 0–7 的八核版本启用 8G3，其他核心版本或无法确认时使用 Common。
- Action 实时复核设备后下载 8G3 或 Common 配置，保留 App/Mix 模式，更新成功后记录检测结果，旧标记无法绕过八核限制。
- Common 规则下载后原样写入 `applist.conf`，不再执行核心编号转换。
- 同步 AkiAppOpt `Aki-1.2.0(207-73620e2)` 三架构成品。
- 同步实例锁、崩溃退避重启和有界日志，保留 KernelSU late-load、显式配置路径和配置热加载支持。
- 模块 ID 和安装目录保持 `AppOpt`，cpuset 目录使用 `/dev/cpuset/AkiAppOpt`。
- 首次升级时完整保留现有 `applist.conf`；建立默认规则基线后，三方合并保留用户增删改。
