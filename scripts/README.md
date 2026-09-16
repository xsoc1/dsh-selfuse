# Windows 管理脚本快照

`dsh-control.ps1`、`run-dsh-web.ps1`、`dsh-watchdog.ps1`、`ensure-dsh-watchdog.ps1` 及 VBS 入口镜像了当前 Windows `F:\tools\deepseek-harness` 中的运行脚本。图形控制台源码位于 [`../console/`](../console/README-selfuse.md)；实际运行中的脚本仍由 Windows Harness 工作树提供，改动本目录不会自动部署。

`run-dsh-web.ps1` 在 Tailscale 启动时不可用的情况下，会从活跃 WSL `settings.yaml` 的 `remote-web-ui.publicBaseUrl` 读取严格限定的 HTTPS `*.ts.net` 根域名，作为 DSH 的 `--trusted-host` 兜底；Tailscale 恢复后不会再因启动顺序造成远程 WebSocket 403。回归检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-dsh-web.test.ps1
```

这些脚本包含本机的 WSL 发行版名、用户目录和 `F:` 路径。迁移到新机器前必须调整路径并在隔离环境验证；不要直接从仓库 clone 运行启动脚本。旧 `update-dsh.ps1` 没有随本次同步，仍是历史脚本；它的应用动作不适用于当前升级工作树。当前只读更新预检在控制台中，源码更新须走审核后的维护流程。
