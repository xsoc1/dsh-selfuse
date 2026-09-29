# 当前部署与配置来源（2026-09-29）

本仓是云端索引与 Windows 管理源码快照，不是当前 DSH 的 `DSH_HOME`。锁定的 [`vendor/deepseek-harness`](../vendor/deepseek-harness) 子模块是官方 `0.2.0-rc.2` 修订 `639ed015397290b3745d163aafe02ffee4aa3f84` 加自用层的提交 `c9896317dd6eb599ebd9ab5855fa50badba4034d`。本机于 2026-09-29 单独切换 `/home/huangzy/tools/deepseek-harness-current` 并重启；活跃进程工作目录和 CLI 版本均已核对，云端提交本身不会替换本机运行文件。

| 用途 | 当前本机位置 | 云端来源 |
|---|---|---|
| Web 运行源码 | WSL `/home/huangzy/tools/deepseek-harness-current` → `/home/huangzy/tools/deepseek-harness-upgrade-20260929` | 锁定的 Harness 子模块与活跃工作树同一提交 |
| 活跃用户数据与 Web profile | WSL `/home/huangzy/.dsh` | 不整目录上传；模板、生成器和安装脚本在子模块 `config/selfuse/`、`scripts/selfuse/` |
| Windows 启动、看门狗、控制命令 | `F:\tools\deepseek-harness` | 本仓 `scripts/` 快照及子模块 `scripts/selfuse/management/` |
| WinForms 控制台 | `F:\tools\deepseek-harness\packages\selfuse\control-gui` | 本仓 `console/` 源码快照及子模块同路径 |
| Tailscale Serve | Windows 系统服务、Tailnet 配置 | [Safari/Tailscale 手册](safari-tailnet.md)；不上传服务凭据 |
| 官方 Windows Desktop | `C:\Users\HuangZY\AppData\Local\Programs\DeepSeek Harness`；与 WSL Web 不共用 profile | [桌面版迁移评估](desktop-migration-0.2.0-rc.2.md)；已安装，隔离 profile 可管理两个外部插件，GUI 和会话迁移未验收 |

Web 清单由子模块 `config/selfuse/profiles.build.yml` 和 `scripts/selfuse/generate-profile.mjs` 生成，并保留通过原生 CLI 显式安装的插件。`config/selfuse/settings.yaml`、`config/selfuse/remote-desktop.md` 与 `scripts/selfuse/install.mjs` 描述默认设置和安装流程。[rc.1 升级说明](upgrade-0.2.0-rc.1.md)锁定第三方包及本地隐私补丁，[rc.2 评估](desktop-migration-0.2.0-rc.2.md)记录本次切换与桌面版限制。2026-09-29 切换前备份五个现役 Web profile 顶层文件至 `/home/huangzy/.dsh/maintenance-backups/upgrade-rc2-20260929-GADMK1`，再执行非强制 `install.mjs --dsh-home /home/huangzy/.dsh`；生成器保留原生 CLI 显式安装的四个外部依赖，既有预设和 skills 未覆盖。未整目录重装现用 `DSH_HOME`。

本仓根目录的 `install.ps1`、`scripts/update-dsh.ps1`、旧 `config/`、`plugins/`、`community-plugins/` 的旧快照和历史 [方案](PLAN.md)/[架构](architecture.md) 源于早期 Windows 部署，不能直接覆盖 WSL 运行配置。本次新增的 `community-plugins/patches/` 仅保存新版灵枢隐私补丁，不会自动安装。尤其不要把旧 Windows profile 复制到 WSL `DSH_HOME`。老工作树 `F:\tools\dsh-local` 有用户未提交内容，应独立保留。

云端不包含 API Key、登录状态、Tailnet 凭据、会话日志、记忆、模型、个人壁纸或构建的 EXE；因此 clone 后不是无凭据的一键复刻。本机插件中若有仅存本地的第三方包或手工安装项，应在部署前逐项核对实际 `dsh plugin --profile web list` 与生成清单，不能仅凭本仓历史 manifest 判定活跃状态。

只读核对建议：检查 `git submodule status vendor/deepseek-harness`、WSL `readlink -f /home/huangzy/tools/deepseek-harness-current`、`git -C <解析后的源码目录> rev-parse HEAD`、本机带令牌 Web URL 的 HTTP 状态，以及 Windows `tailscale serve status --json`。本次本机与 Tailnet 带令牌访问均返回 HTTP 200，watchdog 状态为运行中；远程端会话同步仍需 iPad Safari 实测。启动日志仍警告受信 Tailnet 主机的普通 `/api` 对未配对设备开放，这是既有 `requirePairingForLan: false` 的安全取舍，不等于公网 Funnel。
