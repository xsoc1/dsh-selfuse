# scripts

管理脚本规范源（从 `F:\tools\deepseek-harness\` 复制而来）。

| 文件 | 作用 |
|---|---|
| `dsh-control.ps1` | dsh 启停/状态/UI/日志 CLI |
| `dsh-control-gui.ps1` | WinForms 图形控制台（状态轮询、按钮命令） |
| `run-dsh-web.ps1` | 启动 dsh web（WSL 网关、trusted-host、日志） |
| `dsh-watchdog.ps1` | 看门狗：探活/重启/心跳 |
| `ensure-dsh-watchdog.ps1` | 计划任务兜底 |
| `make-dsh-icon.ps1` | 生成图标工具 |

> 当前这些文件同时存在于运行目录 `deepseek-harness/`。
> 迁移后本目录是规范源，`install.ps1` 负责同步/包装到运行目录。
