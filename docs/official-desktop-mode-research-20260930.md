# 官方 Desktop 原生模式与旧配置适配依据（2026-09-30）

范围：只核对 DeepSeek 官方文档和 `deepseek-ai/deepseek-harness` 上游提交 [`639ed0153972`](https://github.com/deepseek-ai/deepseek-harness/tree/639ed015397290b3745d163aafe02ffee4aa3f84) 的源码；下文的“建议”是依据源码作出的迁移判断，不代表官方提供了自动迁移工具。本页不验证本机 Desktop 的实际会话、模型、插件或 iPad 访问。

## 最接近官方原生的组成

官方 Desktop 是 Electron 容器，启动随包的 Desktop Host 和完整 Web 应用；窗口加载打包页面，Host 处理认证后的 API 和 WebSocket。它使用保留的 `$DSH_HOME/profiles/desktop`，由 Desktop 初始化并管理，和 Web 的 `profiles/web` 分开。两者在**同一个** Harness home 下可以共享受支持的会话等产品数据，但执行包、插件启用选择与锁文件各自独立。Desktop 首次建档采用官方 Web 模板的内建 bundles，插件经桌面内的 Web Plugin Manager 和随包 pnpm 管理。因此，最原生的基线是官方 Desktop 安装包、自身 `desktop` profile、官方内建预设与桌面插件管理；旧自用控制台不属于这个启动链。[官方架构](https://deepseek-harness.github.io/deepseek-harness/en/reference/#desktop-application)；[Desktop 说明](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/apps/desktop/README.md)；[Desktop profile 初始化源码](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/apps/desktop/src/project-manager.ts)。

官方 Web bundle 默认预设为 `standard`，另外随包声明 `ptc`、`minimal`、`cordis`。Windows 下 `standard` 使用官方 `tool-pwsh` 行。建议新会话先使用 `standard`，只在证明功能确有需要后安装额外插件或修改预设。[Web bundle 说明](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/bundle/web-app/README.md)；[默认预设配置](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/bundle/web-app/cordis.patch.yml)；[`standard` 声明](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/bundle/web-app/presets/standard.patch.yml)。

## 截图所示 `Unknown agent preset: wsl-router-standard`

官方会话会持久记录所用预设 ID；恢复时按当前进程的同名声明重新组合工具和提示词。新版注册表只接受 Cordis 中的 `@deepseek-ai/dsh-agent-preset` 声明，不扫描旧 `$DSH_HOME/.agent-presets/` 目录；缺少声明时，源码抛出 `agent-preset/not-found`，消息正是 `Unknown agent preset: <ID>`。这能解释截图，但仅凭截图无法断定报错会话的存储位置或配置来源。[预设注册表说明](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/preset/agent-preset-registry/README.md)；[查找与报错源码](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/preset/agent-preset-registry/src/index.ts)；[会话预设投影](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/preset/agent-preset-registry/src/session.ts)。

上游 `PresetDefinition` 只有 `id`、显示字段、`order` 和 `plugins`，没有别名或继承字段。若需让旧会话继续使用原 ID，原生扩展方式是在**实际运行的 profile** 里增加 ID 恰为 `wsl-router-standard` 的声明，并明确写出它的插件组合；不能假设给 `standard` 换个名字就自动保留旧工具行为。若只要求读取历史，可先核对冷读是否工作，再决定是否添加兼容声明。不要直接改写旧会话日志中的预设 ID；日志中的 ID 是模型当时工具和提示词组合的持久事实。[声明类型](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/preset/agent-preset-registry/src/definition.ts)；[注册表与恢复限制](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/preset/agent-preset-registry/README.md)；[会话元数据说明](https://deepseek-harness.github.io/deepseek-harness/en/reference/subsystems/persistence)。

## 本地窗口与远程入口

Desktop Host 是桌面窗口的内部组成：上游默认 `19387`，通过 `webserver.config.port` 可覆盖；Web 默认 `3080`。Desktop Host 向 Electron 报告 `127.0.0.1` 的认证 URL。Web Server 接受 `port: 0` 由系统分配端口；其自身没有 TLS 或认证，安全策略由上层 Connection 等插件提供。由此推断：桌面端正常启动不需要另一个 `dsh web` 进程，但当前 iPad/Tailnet 若仍指向 WSL Web，就需要保留该远程入口，直到新的可认证入口完成实际端到端验证。[Desktop 说明](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/apps/desktop/README.md)；[Desktop Host 启动源码](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/apps/desktop-host/src/index.ts)；[官方 HTTP Server 参考](https://deepseek-harness.github.io/deepseek-harness/en/reference/subsystems/web-server)；[Web bundle 访问说明](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/bundle/web-app/README.md)。

## 对清理工作的具体边界

依据上述官方组成，旧 `dsh` WinForms 控制台、其轮询和专属计划任务不是官方 Desktop 的依赖，适合在确认替代的启动、退出、故障查看方式后退役。旧 WSL Web 与 Tailscale 转发是否退役是另一个运行结果：它当前承担的 iPad 入口和会话数据不能从 Desktop 窗口可用直接推断已被替代。旧 `.agent-presets/` 目录不能修复新版 Desktop 的未知预设错误；应核对报错所用的 home/profile，并在该 profile 添加声明或选择不再恢复那些旧会话。[官方 Desktop profile 与 Host](https://deepseek-harness.github.io/deepseek-harness/en/reference/#desktop-application)；[预设注册表](https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/preset/agent-preset-registry/README.md)。
