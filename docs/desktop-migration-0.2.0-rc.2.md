# 官方 0.2.0-rc.2 与桌面版迁移评估（2026-09-29）

本页区分官网声明、本机实测和仍待验证的迁移步骤。官方信息来自 [DeepSeek 下载页](https://www.deepseek.com/download/)及其链接的 [Harness 架构文档](https://deepseek-harness.github.io/deepseek-harness/en/reference/#desktop-application)，不是第三方 Orb 分叉。下载页称桌面端已发布、支持后台运行和本地文件读写，仍在持续迭代；官网提供 Windows 与 Apple 芯片 macOS 13+ 下载。本机读取官方 [Windows 更新源](https://download.deepseek.com/dsh-desk/feeds/win-x64/nightly.yml)为 `0.2.0-rc.2`。官网功能介绍不构成现有插件、WSL 会话或 iPad 远程链路的迁移保证。

## 已完成的本机实践

- 官方 `deepseek-ai/deepseek-harness` `master` 核对为 `639ed015397290b3745d163aafe02ffee4aa3f84`，合入隔离 WSL 工作树；自用构建提交为 `a096be31e89`，最终含迁移记录的 pin 为 `c9896317dd6`。`pnpm install --frozen-lockfile`、完整构建、定向测试和隔离临时 `DSH_HOME` Web 启动通过；完整文档门禁 43/43。自用 `@dsh-selfuse/content-risk-guard` 的 `lib` 原先未纳入官方构建，现由 `build:selfuse` 在 Web 打包前构建，避免新版本导入失败。外部 prompt optimizer `0.7.6`、memory `0.6.0-selfuse.1` 在隔离 profile 能启用；现役 Web profile 仍有这两个版本。
- 官方 Windows 安装包从 `download.deepseek.com` 下载；SHA512 与官方更新源一致，Authenticode 状态为 `Valid`，签名主体为 Hangzhou DeepSeek Artificial Intelligence Co., Ltd.。已安装到 `C:\Users\HuangZY\AppData\Local\Programs\DeepSeek Harness`，注册显示版本与随包 `dsh.cmd --version` 均为 `0.2.0-rc.2`。首次在临时 Windows `DSH_HOME` 隐蔽启动后，Desktop profile 初始化；程序退出后，随包 CLI 可以操作该 profile。真实 Windows 用户 profile 未迁入 WSL 数据。
- 从 WSL UNC 路径直接安装 tarball 时，随包 CLI 将路径错误解析为 `C:\wsl.localhost\...` 并报文件不存在；把经 SHA-256 核对的 tarball 复制到临时 Windows home 后，以本地绝对路径成功安装，`plugin --profile desktop list` 列出提示词优化器 `0.7.6` 和灵枢记忆 `0.6.0-selfuse.1`。这证明安装与 profile 记录，不证明 GUI 插件激活；隐蔽启动期间未观察到端口 `19387` 监听，尚未完成实际窗口、会话或模型请求测试。
- 停止旧 WSL Web 后，将现役 profile 五个顶层文件备份至 `/home/huangzy/.dsh/maintenance-backups/upgrade-rc2-20260929-GADMK1`，非强制刷新 profile，切换 `/home/huangzy/tools/deepseek-harness-current` 到 `/home/huangzy/tools/deepseek-harness-upgrade-20260929` 并重启。活跃进程 cwd、CLI 版本均为 rc.2；Windows 本机和 Tailnet HTTPS 的带令牌页面均 HTTP 200，watchdog 正在运行。未进行真实模型请求、iPad Safari 会话同步和桌面 GUI 验收。
- Windows `dsh-control.ps1 start` 在服务已 HTTP 200 时因缓存旧启动令牌误报超时；现役脚本与本仓快照均改为每次探测读取最新令牌，复测 `start` 立即报告就绪。它仅修复控制脚本的判定，不代表移动端链路已验收。

## 有用功能能否全量迁移

| 功能 | 官方桌面端与本机现状 | 迁移判断 |
|---|---|
| 原生窗口、后台任务、本地文件读写 | 官网明确提供；已安装签名包并在临时 home 隐蔽启动，GUI 尚未操作 | 可作为 Windows 本地入口试用，须完成可见窗口和文件读写实测 |
| Web 对话界面、普通会话 | 架构文档称桌面端包含完整 Web 应用；Desktop Host 默认端口 `19387` | 界面有移植基础；同一账号不等于自动继承 WSL 的会话数据 |
| 插件、主题、自用风险防护、第三方记忆和提示词优化 | Desktop 使用独立 `$DSH_HOME/profiles/desktop`、锁文件和启用选择；临时 Windows profile 已安装两种外部插件，但未验证激活 | 需按 Windows 运行时逐个安装、配置和验证；WSL 编译产物及绝对路径不能直接当成桌面插件验收 |
| WSL 工作区与已有会话/凭据 | 活跃数据在 `/home/huangzy/.dsh`，Desktop 默认在 Windows 用户上下文；官方仅保证同一个 Harness home 的产品数据可共享 | 不做整目录复制或路径替换；先验证跨系统文件访问、会话导出/读回及敏感数据边界 |
| Tailnet/iPad 入口与远程会话同步 | 现役 Windows Serve 桥接 WSL Web；官网未承诺 Desktop Host 可以原样替换此链路 | 继续保留 WSL Web；只有 iPad 发消息、流式过程和结束态实测通过后才讨论退役 |
| Windows 图形控制台与 watchdog | 桌面版可替代部分本地启动/窗口体验，但现有控制台还管理 WSL、Tailscale 和看门狗 | 暂不删除；逐项替代并验证后再缩减 |

官方架构文档说公开 CLI 不管理 Desktop profile；本机随包 rc.2 CLI 实测接受 `--profile desktop` 参数，但在桌面首次初始化前拒绝操作，初始化后可安装和列出插件。两者应分别理解为“公开通用 CLI”和“桌面随包 CLI”，不能用后者的参数支持推断桌面迁移已完成。

## 下一轮验收与回退

在可见桌面窗口中，以非敏感工作区逐项验收插件激活、实际文件写入、会话结束态和退出后重开；需另用 iPad 验证远程端。临时 profile 的 CLI 安装记录不能替代这些检查，也不应直接覆盖默认 Windows 用户的 Desktop profile。如果任何环节缺失，桌面端与 WSL Web 并行，不关闭 Tailnet 服务。

WSL 回退目标仍保留在 `/home/huangzy/tools/deepseek-harness-upgrade-20260928`，备份目录保留上述五个 profile 文件。回退时先停止现役 Web，确认活跃链接确为 rc.2，再将链接指回旧目录；如生成 profile 与旧版不兼容，只恢复备份中的具体文件，避免覆盖会话、凭据和记忆。启动后重新核对进程 cwd、HTTP 200、插件导入与 Tailnet。当前日志仍提示 `remote-web-ui` 的 `/api` 对受信 Tailnet 主机不要求配对；这是既有私有 Tailnet 访问方案的安全取舍，不能描述为设备配对保护，更不能开启公网 Funnel 后照搬。
