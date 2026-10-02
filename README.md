# dsh-selfuse

DeepSeek Harness 自用部署的管理仓。本机入口现为安装在 F 盘的官方 Windows Desktop `0.2.0-rc.2`；旧 WSL Web 与 Tailscale 远程入口已退役，控制台源码和管理脚本已从本仓移除。Windows 旧会话归档在 F 盘，WSL 原会话保留。当前部署见 [部署说明](docs/current-deployment.md)，历史迁移过程见 [桌面版评估](docs/desktop-migration-0.2.0-rc.2.md)。

桌面端默认端口冲突通过独立的 [Desktop profile 模板](config/desktop/cordis.patch.yml) 修复；初始化使用官方 `standard`，之后保留用户预设选择。WSL fork 仅供开发，不再作为运行服务。源码退役与原生适配已发布到 [fork 固定提交](https://github.com/xsoc1/deepseek-harness/commit/42d47032d3da839f088142c4b439f95128973a21)，本仓 `vendor/deepseek-harness` pin 对齐该提交；云端源码、官方签名程序、现用配置及功能验收分别记录，不能相互替代。

## 从云端取回

```powershell
git clone --recurse-submodules https://github.com/xsoc1/dsh-selfuse.git
cd dsh-selfuse
git submodule status vendor/deepseek-harness
```

完整的当前目录关系和验收边界见 [当前部署说明](docs/current-deployment.md)；旧远程链路仅作为历史记录保留在 [Safari/Tailscale 手册](docs/safari-tailnet.md)。组件索引见 [manifest.json](manifest.json)，历次维护见 [docs/maintenance.md](docs/maintenance.md)。

`install.ps1`、旧 `config/` 和旧 `plugins/` 属于早期部署快照，不应覆盖 Desktop `DSH_HOME`。当前 Desktop profile 先以官方 bundle 为基线，只合并必要的本机补丁；API Key、登录凭据、会话、记忆和模型文件不入库。

本地开发层的旧设置/社区/skins/all 已按用户选择归档；SSH、任务板、MinerU、undo 与闲置 SDK 随后也获准归档，优先官方原生功能。正式 Desktop 已通过官方 CLI 安装十个保留包，并补齐 F 盘外置依赖和原生记忆目录解析。2026-10-03 正常退出后更新记忆包，旧包可恢复、五份 profile 配置哈希不变；新实例九个 Host 激活、五个 Client 资源通过，用户确认设置面板已找到。隔离记忆保存读回通过，正式模型和 GitHub HTTPS 备份恢复未重新验收。重建方法见[安装与运行验收](scripts/README.md)，归档和证据见[原生 UI 精简](docs/plugin-retirement-20261001.md)及[维护记录](docs/maintenance.md)。
