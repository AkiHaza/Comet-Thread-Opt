## 8.0

- 合并 Common 与 8G3 为单一自动适配模块。
- 安装时识别 SM8650/pineapple，并在 `confige.txt` 写入 `8G3=on/off`。
- Action 根据 SoC 标记下载 8G3 或 Common 配置，并保留 App/Mix 模式。
- Common 规则下载后原样写入 `applist.conf`，不再执行核心编号转换。
- 移植 AkiAppOpt 的 PID 防重复启动、显式配置路径和配置热加载支持。
- 模块 ID 和安装目录保持 `AppOpt`，cpuset 目录使用 `/dev/cpuset/AkiAppOpt`。
- 更新模块时保留用户已有的 `applist.conf`。
