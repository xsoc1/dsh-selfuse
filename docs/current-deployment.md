# 当前部署与配置来源（2026-09-29）

本仓是云端索引与 Windows 管理源码快照，不是当前 DSH 的 `DSH_HOME`。锁定的 [`vendor/deepseek-harness`](../vendor/deepseek-harness) 子模块是官方 `0.2.0-rc.1` 加自用层的提交 `bcf8c14b1927fb1ee3701e5e3852ff2c3ef25249`。本机于 2026-09-29 单独切换 `/home/huangzy/tools/deepseek-harness-current` 并重启；子模块提交、活跃链接和活跃进程仍须分别核对，云端提交本身不会替换本机运行文件。

| 用途 | 当前本机位置 | 云端来源 |
|---|---|---|
| Web 运行源码 | WSL `/home/huangzy/tools/deepseek-harness-current` → `/home/huangzy/tools/deepseek-harness-upgrade-20260928` | 锁定的 Harness 子模块与活跃工作树同一提交 |
| 活跃用户数据与 Web profile | WSL `/home/huangzy/.dsh` | 不整目录上传；模板、生成器和安装脚本在子模块 `config/selfuse/`、`scripts/selfuse/` |
| Windows 启动、看门狗、控制命令 | `F:\tools\deepseek-harness` | 本仓 `scripts/` 快照及子模块 `scripts/selfuse/management/` |
| WinForms 控制台 | `F:\tools\deepseek-harness\packages\selfuse\control-gui` | 本仓 `console/` 源码快照及子模块同路径 |
| Tailscale Serve | Windows 系统服务、Tailnet 配置 | [Safari/Tailscale 手册](safari-tailnet.md)；不上传服务凭据 |

Web 清单由子模块 `config/selfuse/profiles.build.yml` 和 `scripts/selfuse/generate-profile.mjs` 生成，并保留通过原生 CLI 显式安装的插件。`config/selfuse/settings.yaml`、`config/selfuse/remote-desktop.md` 与 `scripts/selfuse/install.mjs` 描述默认设置和安装流程。[升级说明](upgrade-0.2.0-rc.1.md)锁定了官方修订、第三方版本、本地隐私补丁、隔离测试及切换前检查。部署前先比较运行中的 `~/.dsh`，保留用户数据和 CLI 显式插件；可先在锁定的 Harness 工作树执行 `node scripts/selfuse/install.mjs --dry-run --dsh-home /home/huangzy/.dsh`，审查预览后再决定是否应用。本次只通过原生 CLI 更新两个外部插件，未整目录重装现用 `DSH_HOME`。

本仓根目录的 `install.ps1`、`scripts/update-dsh.ps1`、旧 `config/`、`plugins/`、`community-plugins/` 的旧快照和历史 [方案](PLAN.md)/[架构](architecture.md) 源于早期 Windows 部署，不能直接覆盖 WSL 运行配置。本次新增的 `community-plugins/patches/` 仅保存新版灵枢隐私补丁，不会自动安装。尤其不要把旧 Windows profile 复制到 WSL `DSH_HOME`。老工作树 `F:\tools\dsh-local` 有用户未提交内容，应独立保留。

云端不包含 API Key、登录状态、Tailnet 凭据、会话日志、记忆、模型、个人壁纸或构建的 EXE；因此 clone 后不是无凭据的一键复刻。本机插件中若有仅存本地的第三方包或手工安装项，应在部署前逐项核对实际 `dsh plugin --profile web list` 与生成清单，不能仅凭本仓历史 manifest 判定活跃状态。

只读核对建议：检查 `git submodule status vendor/deepseek-harness`、WSL `readlink -f /home/huangzy/tools/deepseek-harness-current`、`git -C <解析后的源码目录> rev-parse HEAD`、本机 `http://127.0.0.1:3080/` 的 HTTP 状态，以及 Windows `tailscale serve status --json`。远程端是否停止重连，最终仍需 iPad Safari 实测。
