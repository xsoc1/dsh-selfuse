# 官方 0.2.0-rc.2 与桌面版迁移评估（2026-09-29）

本页区分官网声明、本机实测和仍待验证的迁移步骤。官方信息来自 [DeepSeek 下载页](https://www.deepseek.com/download/)及其链接的 [Harness 架构文档](https://deepseek-harness.github.io/deepseek-harness/en/reference/#desktop-application)，不是第三方 Orb 分叉。下载页称桌面端已发布、支持后台运行和本地文件读写，仍在持续迭代；官网提供 Windows 与 Apple 芯片 macOS 13+ 下载。本机读取官方 [Windows 更新源](https://download.deepseek.com/dsh-desk/feeds/win-x64/nightly.yml)为 `0.2.0-rc.2`。官网功能介绍不构成现有插件、WSL 会话或 iPad 远程链路的迁移保证。

## 2026-09-30 最终本机决策

用户先要求兼顾 iPad 和手机，随后明确放弃 DSH 远程插件，并选择归档旧 Windows 会话、从官方 `standard` 新建桌面会话。因此下文 2026-09-29“继续保留 WSL Web/Tailnet”的判断仅是当时评估，不再是当前部署。现状和准确路径以 [当前部署](current-deployment.md) 为准。

旧桌面会话报 `Unknown agent preset: wsl-router-standard`：实际日志存有该旧预设 ID，官方 Desktop 随包 registry 只提供 `standard`、`ptc`、`minimal`、`cordis`，不会扫描旧 `.agent-presets`。没有改写追加式会话日志；用户正常退出程序后，把 Windows 会话目录整体移至 `F:\tools\dsh-retired-20260930\windows-sessions-legacy`，229 个压缩会话文件共 264825963 字节。WSL 原会话保留；旧 Web profile 移至 `/home/huangzy/.dsh/retired/web-profile-20260930`。真实 Desktop patch 保留动态 loopback 端口，并把 `selectedDefault` 改为 `standard`。重启后新建的 v4 会话日志为 `agentPreset: standard`，Host 监听本机动态端口；未进行真实模型请求。

两项 DSH 看门狗计划任务已删除，其 XML 保存在上述 F 盘归档目录；Tailscale Serve 唯一的 `443 → 127.0.0.1:3080` 规则已清空，Tailscale 应用未卸载。WSL fork 的远程插件、控制台源码和装配引用已在本地删除，本仓的控制台与管理脚本快照也已删除；这些源码改动尚未发布。Desktop 内部 Web Host 仍是官方窗口运行所需，不能随远程功能一起删掉。

## 已完成的本机实践

- 官方 `deepseek-ai/deepseek-harness` `master` 核对为 `639ed015397290b3745d163aafe02ffee4aa3f84`，合入隔离 WSL 工作树；自用构建提交为 `a096be31e89`，最终含迁移记录的 pin 为 `c9896317dd6`。`pnpm install --frozen-lockfile`、完整构建、定向测试和隔离临时 `DSH_HOME` Web 启动通过；完整文档门禁 43/43。自用 `@dsh-selfuse/content-risk-guard` 的 `lib` 原先未纳入官方构建，现由 `build:selfuse` 在 Web 打包前构建，避免新版本导入失败。外部 prompt optimizer `0.7.6`、memory `0.6.0-selfuse.1` 在隔离 profile 能启用；现役 Web profile 仍有这两个版本。
- 官方 Windows 安装包从 `download.deepseek.com` 下载；SHA512 与官方更新源一致，Authenticode 状态为 `Valid`，签名主体为 Hangzhou DeepSeek Artificial Intelligence Co., Ltd.。2026-09-29 最初安装到 `C:\Users\HuangZY\AppData\Local\Programs\DeepSeek Harness`，注册显示版本与随包 `dsh.cmd --version` 均为 `0.2.0-rc.2`；2026-09-30 按用户要求改装到 `F:\Apps\DeepSeekHarness`。首次在临时 Windows `DSH_HOME` 隐蔽启动后，Desktop profile 初始化；程序退出后，随包 CLI 可以操作该 profile。真实 Windows 用户 profile 未迁入 WSL 数据。
- 从 WSL UNC 路径直接安装 tarball 时，随包 CLI 将路径错误解析为 `C:\wsl.localhost\...` 并报文件不存在；把经 SHA-256 核对的 tarball 复制到临时 Windows home 后，以本地绝对路径成功安装，`plugin --profile desktop list` 列出提示词优化器 `0.7.6` 和灵枢记忆 `0.6.0-selfuse.1`。这证明安装与 profile 记录，不证明 GUI 插件激活；隐蔽启动期间未观察到端口 `19387` 监听，尚未完成实际窗口、会话或模型请求测试。
- 停止旧 WSL Web 后，将现役 profile 五个顶层文件备份至 `/home/huangzy/.dsh/maintenance-backups/upgrade-rc2-20260929-GADMK1`，非强制刷新 profile，切换 `/home/huangzy/tools/deepseek-harness-current` 到 `/home/huangzy/tools/deepseek-harness-upgrade-20260929` 并重启。活跃进程 cwd、CLI 版本均为 rc.2；Windows 本机和 Tailnet HTTPS 的带令牌页面均 HTTP 200，watchdog 正在运行。未进行真实模型请求、iPad Safari 会话同步和桌面 GUI 验收。
- Windows `dsh-control.ps1 start` 在服务已 HTTP 200 时因缓存旧启动令牌误报超时；现役脚本与本仓快照均改为每次探测读取最新令牌，复测 `start` 立即报告就绪。它仅修复控制脚本的判定，不代表移动端链路已验收。

### 2026-09-30 Windows 安装位置调整

用户明确要求桌面版不要安装到 C 盘。确认程序未运行、F 盘空间充足、原安装包签名仍有效后，用同一个官方安装包执行 `/S /currentuser /D=F:\Apps\DeepSeekHarness`（`/D` 必须是最后一个参数；此路径不含空格）。安装器退出码为 0，并自行移除了旧 C 盘程序目录。随后核对卸载注册表 `InstallLocation`、开始菜单快捷方式目标和工作目录均为 `F:\Apps\DeepSeekHarness`；新 EXE 的签名为 `Valid`，从 F 盘启动的四个进程均指向该路径，隔离 `DSH_HOME=F:\Apps\DeepSeekHarnessSmoke` 成功创建 `profiles` 与 `storages`。这只验证启动和目录写入，不是 GUI/插件/会话端到端验收。

先前由本项目在 C 盘临时目录创建的约 131 MB 桌面测试 home 已完整移到 `F:\Apps\DeepSeekHarnessPriorSmoke` 留存，没有删除其中测试 profile、报告或 tarball。安装器与此次操作没有迁移或删除用户的真实 `.dsh`、会话和 WSL Web 数据；Windows 用户配置或将来的更新缓存仍可能位于 C 盘，不能宣称“所有数据都在 F 盘”。如需重装，先检查现有进程、安装包签名、目标路径和数据位置，再以同样参数安装并重新核对注册表、快捷方式及实际进程路径，不要直接复制程序目录代替安装。

### 2026-09-30 桌面端无法启动：Windows 排除默认端口

用户提供 “DeepSeek Harness is unavailable” 截图。最初迁盘测试只核对进程和 profile 目录创建，**未核对 Host 是否就绪，结论不足**。本次以“启动后是否新建 `crash-*-host.log`”作为回归信号：默认 profile 连续两次产生同样报告，独立空白 profile 也产生报告；报告明确指出必需 `webserver` 监听 `127.0.0.1:19387` 时 `EACCES`，后续多个插件只是等待该服务。普通 Node 程序监听 `19387`、`19388` 同样 `EACCES`；Windows `netsh interface ipv4/ipv6 show excludedportrange protocol=tcp` 显示 `19362–19461` 为排除段，且未见占用 `19387` 的监听进程。因此根因是本机端口排除与官方桌面端默认 `19387` 冲突，不是安装在 F 盘、用户会话或第三方插件本身。

官方桌面 Host 支持通过 profile `webserver.config.port` 覆盖端口，WebServer 也允许 `port: 0` 请求系统分配可用端口。先在隔离 F 盘 profile 验证零端口：无新崩溃报告，并看到 loopback 监听；再把真实 `C:\Users\HuangZY\.dsh\profiles\desktop\cordis.patch.yml` 备份到 `F:\Apps\DeepSeekHarnessConfigBackups\cordis.patch.yml.before-port-20260930`，仅加入 [本仓模板](../config/desktop/cordis.patch.yml)中的 `webserver` 行。profile patch 会替换整段配置，因此除 `host: 127.0.0.1` 和 `port: 0` 外保留官方的 gzip、级别 1 和阈值 1024 字节。未删 Windows 端口排除、未改防火墙或 Tailscale，也未禁用插件。

真实 profile 启动后无新崩溃报告、进程实际位于 F 盘、动态 loopback 端口监听；未认证的 HEAD 请求返回 401，窗口标题为 `DeepSeek Harness`，用户确认“正常启动了”。动态端口每次可不同，不应把实测端口写死。以上证明此次启动故障已消除；仍未做模型请求、插件实际功能和 WSL 会话迁移验收。

## 有用功能能否全量迁移

| 功能 | 官方桌面端与本机现状 | 迁移判断 |
|---|---|
| 原生窗口、后台任务、本地文件读写 | 官网明确提供；真实 profile 的窗口已可启动，用户确认看见，仍未做文件读写实测 | 可作为 Windows 本地入口试用，须继续测试原生文件操作 |
| Web 对话界面、普通会话 | 架构文档称桌面端包含完整 Web 应用；Desktop Host 默认端口 `19387` | 界面有移植基础；同一账号不等于自动继承 WSL 的会话数据 |
| 插件、主题、自用风险防护、第三方记忆和提示词优化 | Desktop 使用独立 `$DSH_HOME/profiles/desktop`、锁文件和启用选择；临时 Windows profile 已安装两种外部插件，但未验证激活 | 需按 Windows 运行时逐个安装、配置和验证；WSL 编译产物及绝对路径不能直接当成桌面插件验收 |
| WSL 工作区与已有会话/凭据 | 活跃数据在 `/home/huangzy/.dsh`，Desktop 默认在 Windows 用户上下文；官方仅保证同一个 Harness home 的产品数据可共享 | 不做整目录复制或路径替换；先验证跨系统文件访问、会话导出/读回及敏感数据边界 |
| Tailnet/iPad/手机入口与远程会话同步 | 用户最终放弃 DSH 远程插件；Serve 映射已清空，旧 WSL Web profile 已归档 | 不再列入当前验收；Tailscale 本身保留供其他用途 |
| Windows 图形控制台与 watchdog | 独立 WinForms 控制台与两项看门狗任务已退役，Desktop 自己管理窗口和内部 Host | 不再部署旧控制台或调度器 |

官方架构文档说公开 CLI 不管理 Desktop profile；本机随包 rc.2 CLI 实测接受 `--profile desktop` 参数，但在桌面首次初始化前拒绝操作，初始化后可安装和列出插件。两者应分别理解为“公开通用 CLI”和“桌面随包 CLI”，不能用后者的参数支持推断桌面迁移已完成。

用户于 2026-09-30 问“是否一定要保留 Web Host 才能远程”。当时的判断是：远程访问需要服务处理页面、API 和 WebSocket，但不一定是原 WSL Web；Desktop 动态端口与 Electron 私有认证通道也不能直接当成 iPad 入口。随后用户决定放弃远程插件，因此现已停用 WSL Web 和 DSH 的 Tailscale Serve 映射；官方 Desktop 的内部 Web Host 仍为本机窗口运行所需。若未来重新启用远程，必须重新设计并验证入口和认证，不能照搬历史链路。

## 下一轮验收与回退

在可见桌面窗口中，以非敏感工作区逐项验收实际文件读写、完整模型对话、会话结束态和退出后重开；若将来需要第三方插件，须单独安装到真实 Desktop profile 并验证。临时 profile 的 CLI 安装记录不能替代这些检查。iPad/手机不再是本次验收对象，且不得因 Desktop 内部 Host 存在就宣称可远程访问。

历史 WSL 回退目标仍保留在 `/home/huangzy/tools/deepseek-harness-upgrade-20260928`；若有意识地恢复旧 Web，应先审查安全配置、服务暴露和归档 profile，不能让旧看门狗或 Serve 自动复活。当前桌面端的回退只涉及已备份的 `cordis.patch.yml` 与 F 盘旧会话归档：必须先正常退出 Desktop，逐项恢复，不要覆盖新会话。此次远程退役不撤销历史上未配对设备可访问受信 Tailnet `/api` 的风险记录。
