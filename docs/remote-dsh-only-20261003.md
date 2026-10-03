# 仅远程访问 DSH（2026-10-03）

本文保留接缝调研阶段证据。随后用户授权正式接入与清理，同 Host 扩展已部署，真实 HTTPS 隔离 26 项及正式只读 38 项通过；实际 Safari/iPad/手机验收仍单列。当前操作只见[专用部署](desktop-remote-20261003.md)，下文“尚未部署”是原调查时点而非现状。

用户纠正为手机/iPad 只访问 DSH，并明确选择“必须保留官方桌面客户端，先验证专用远程接入”。本文记录源码调查；未修改正式 Desktop/profile、退役入口或 RustDesk。官网入口从 [DeepSeek 正式页面](https://www.deepseek.com/zh/harness/)核对；`harness.deepseek.com` 本轮无法访问。

## 可选路线

本轮优先验证 **官方 Desktop 的同一 Host → 专用受控入口 → 手机/iPad 浏览器**。它是待验证的正规 Host 扩展路线，尚非现成远程功能。Tailscale Serve 可把服务限于 tailnet；本机代理的 Host、cookie、WS 行为仍须验收。[官方 Serve](https://tailscale.com/docs/features/tailscale-serve)。

| 版本/入口 | 官方证据与限制 |
|---|---|
| 现用 `0.2.0-rc.2` | 已有 Web、`--trusted-host` 和鉴权，可作为 HTTPS 根路径反代候选；无 `--public-url`。[固定 Web 源码][rc2] |
| 新发布 `0.2.1-alpha.1` | GitHub 于 `2026-10-03T06:42:19Z` 发布预览版；npm `alpha` 指向它，`latest/next` 仍是 rc.2。新增 `--public-url` 和子路径反代地址声明，无须为根路径方案盲目升级。[发布][release]、[npm][npm] |
| 官方 master | `07:04:57Z` 复查与 alpha 标签同为 `5badb15009ae1756c3afe0ae0cef1faafc290ccc`；新参数不增加隧道、鉴权或 Desktop 配对。[固定部署说明][deploy] |
| 现用 Desktop 同 Host | 未找到成品手机接入入口，但共享前端具有普通浏览器启动分支，Host 保留认证 HTTP 页面。下述接缝可在隔离实例验证；不读取正式 IPC 凭证。[Desktop][desktop]、[启动源码][boot] |

## 保留 Desktop 的最小验证接缝

1. 用官方 `createPluginProfile`/`initProfile` 在隔离 home 初始化；默认 bundle 就是 base + web-app。以真正的 `profile: 'desktop'` 和随包安装锚点运行，保留 Desktop 条件组合；仅共享 Web 名称不能替代实际 Host 验收。[初始化][init]。
2. 同一隔离 Host 通过公开 `ctx.connection.authenticatedUrl()` 生成受限启动链接，第二浏览器由现有 frontend-static 根页面完成原生 token→cookie 交换。不得再挂第二个静态 fallback，也不另启后端。[Host API][host-api]、[页面][static]。
3. `dshDesktopBoot` 缺失时前端走普通 Web；目录选择有 Host 回退，Browser 页有 iframe 回退。手机不具备 Electron 原生桥，Desktop 账号/充值设置页会跳过。[启动][boot]、[目录][picker]、[Browser][browser]、[账号][account]。
4. 先证明两个客户端看到同一 Host/会话及持续事件；再验证指定外部 authority。`trustedHosts` 须在启动前正规配置，未找到动态添加 API；扩展只能向已授权本地界面提供链接，不能新增匿名发凭证接口。[Host API][host-api]。

## 鉴权与传输

根页面交换启动令牌为绑定 hostname/port 的签名 cookie；RPC/WS 均须认证。cookie 为 HttpOnly、SameSite=Strict，默认 30 天，后端不加 Secure。代理须保留浏览器 Host/Origin，并在 HTTPS 外侧补 Secure；子路径还须剥前缀、改 cookie Path、规范尾斜杠。`--trusted-host` 只准入，`--public-url` 只声明地址。[认证][auth]、[反代][deploy]。

实时通道为 `/api/remote.mux` WebSocket，普通 RPC 用 HTTP POST；所核对契约未承诺 WS 失败自动退回 SSE。必须验证 Upgrade、持续连接和断线恢复。[Gateway][gateway]。入口仅呈现 DSH，但认证用户仍拥有该 Host 的操作权限，包括现有文件及命令能力。[认证][auth]。

## 状态与尚待验证

本机隔离实测：签名安装版 rc.2 的原生 Desktop 配置组合，两个独立 Chromium 客户端在同一 Host 通过 23 项检查，包括移动 context 中文 prompt、可见 reasoning、共同完成、主动断开 WS 后原生自动恢复、刷新持久化、匿名/错误 Origin 拒绝。只用本地 LlmAdapter，没有真实模型调用；正式五份 profile 哈希不变。可重跑方法见[脚本说明](../scripts/README.md#desktop-同-host-的第二浏览器隔离验证)，具体成功及失败记录见[维护记录](maintenance.md#2026-10-03-仅访问-dsh-的同-host-接缝验证)。这证明原生接缝可用，不等同正式远程入口已经上线。

隔离运行尚不能证明正式 Electron 双客户端可用；仍须核对 Desktop 生命周期、动态端口、原生桥缺失、现用插件及移动端恢复。独立 Web Host 是另一条需用户重选的路线，不能自动接手 Desktop 实时任务；已有写句柄可拒绝续跑。[会话契约][session]。

官方有 Safari 输入修复记录，同时明确自动覆盖不等同真 Safari 验收。[Safari 记录][safari]。随后仍须验证 HTTPS 登录、无凭证/错误 Origin 拒绝、中文输入、同会话观察、前后台及断网恢复。以上是源码接缝，不是正式手机验收通过；关键接缝在 rc.2 与 alpha 逐字一致，无须先升级。

[rc2]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/bundle/web-app/src/startup.ts
[release]: https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.2.1-alpha.1
[npm]: https://registry.npmjs.org/@deepseek-ai%2fdsh
[deploy]: https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/docs/user/guide/public-deployments.md
[desktop]: https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/apps/desktop/README.md
[auth]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/connection/README.md
[gateway]: https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/api/gateway/README.md
[session]: https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/packages/api/session-controller/README.md
[safari]: https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/.agents/notes/archived/bug-fix/2026-08-13-safari-textarea-soft-wrap-reflow.md
[boot]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/apps/web/src/main.ts
[init]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/apps/desktop/src/project-manager.ts
[host-api]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/connection/src/rpc-host.ts
[static]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/host/frontend-static/src/index.ts
[picker]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/ui-directory-picker-native/src/client/index.ts
[browser]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/ui-sidebar-browser/src/client/index.ts
[account]: https://github.com/deepseek-ai/deepseek-harness/blob/639ed015397290b3745d163aafe02ffee4aa3f84/packages/client/ui-settings-account/src/client/index.ts
