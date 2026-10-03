# DSH 新远程访问方案评估（2026-10-03）

最新实施覆盖本文选型阶段：用户授权同 Desktop Host 专用接入与 RustDesk 清理，入口已部署，试行已退役。当前方法和待验收范围见[专用部署](desktop-remote-20261003.md)；以下为原调研时点，不能直接复活旧远控。

最新需求更正：用户确认 RustDesk 连通正常，但明确只要 DSH，选择“必须保留官方桌面客户端，先验证专用远程接入”。下文整机远控优先是历史选型，不是现行建议；当前路线及边界见[仅访问 DSH](remote-dsh-only-20261003.md)。没有据此自动恢复旧 Web、停用 RustDesk 或发布新入口。

## 范围与证据等级

用户本轮要求：“想想, 查查, 有没有全新的更合适的远程访问方案”。本文只做官方文档调研，未安装软件、未开放端口、未恢复旧 Web/控制台/看门狗/Tailscale Serve，也未重启或变更现用 DSH。主 agent 的只读系统检查确认本机为 Windows 11 家庭版中文版。当前 DSH 部署见 [current-deployment.md](current-deployment.md)。

核心方向是远程控制同一台 Windows 上已经运行的官方 Desktop，而不是再运行一个 DSH 后端或同步两套会话。下述“同屏方案”描述架构，不是已完成手机/iPad 实测；触控、中文输入、断网恢复、锁屏和后台切换都仍需验收。

## 结论

1. 若优先保留私有覆盖网及真正的移动端应用，先验证 **RustDesk + Tailscale 的受控 IP 直连**。它改变的是远控层，不给 DSH 添加远程插件；但要新增高权限远控服务，且不能忽略直连的加密和默认公共服务器行为。
2. 若优先减少自建组件并愿意依赖 Google，可把 **Chrome Remote Desktop** 作为独立试用候选。它不依赖旧 DSH Web/Tailscale Serve，不过 iPad 的当前可证路径包含网页加主屏，不能宣称彻底绕开 Safari；Google 网络在本机和手机网络下也未验证。
3. **Windows App + 原生 RDP** 因本机家庭版不能提供官方 RDP Host，本轮不选；不安装 RDP Wrapper 或修改系统授权组件。**Sunshine + Moonlight** 更偏高帧率串流，作为扩展候选而非聊天维护首选。

按“保留官方桌面、减少自用维护、覆盖 iPad 和手机”的目标，建议先验收 RustDesk 私有直连。它让远端看到电脑上的同一份界面，不需要再实现 DSH 的会话副本和思考状态同步；这是架构上的减少，不是已经证明网络不会断线。代价是画面传输、手机小屏操作和整台电脑的远控权限。若主要需求是在手机长时间打字聊天，屏幕远控可能不合适，不能把这个建议替代为移动聊天界面的承诺。

| 方案 | DSH 运行方式 | 本轮判断 |
|---|---|---|
| RustDesk + 私有 Tailscale | 接手现有 Windows 桌面及其 DSH，保持一个执行实例 | 优先试用，先验收中文输入、断线及权限 |
| Chrome Remote Desktop | 同屏远控，增加 Google 账户和网络依赖 | 不希望使用 Tailscale 时的备选；iPad 网页路线仍需测试 |
| 官方 Web + 受保护反向代理 | 另行选择 Web 作为应用入口，不自动接手 Desktop Host | 需要原生移动聊天布局时再评估，不恢复旧自用插件 |

## 官方 DSH：新反向代理支持不是现用桌面的手机配对

先从 [DeepSeek 官网 Harness 页面](https://www.deepseek.com/zh/harness/)进入开发者文档，官网仍分别提供桌面下载和 `npx @deepseek-ai/dsh web` 启动路径。本轮查询到的官方 master 为 [`da00f7f5358f`](https://github.com/deepseek-ai/deepseek-harness/commit/da00f7f5358f2949383b35c14f548bc20187d80c)，提交时间 `2026-10-02T23:44:05Z`；本仓已部署源码 pin 和 `current-deployment.md` 记录的 rc.2 安装不是这个 master。GitHub Releases 列表首项为预发布 `dsh-v0.2.0-rc.2`，`releases/latest` 返回 404，因此不能从该接口推断官网安装器已包含 master 的新功能。[官方发布列表](https://github.com/deepseek-ai/deepseek-harness/releases)。

该 master 已增加 `--public-url` 和正式的反向代理部署说明：它公布浏览器访问地址，`--trusted-host` 另行准入；代理负责外部 TLS、保留 Host、WebSocket upgrade、挂载前缀和 cookie 路径/安全属性。`--public-url` 本身既不是隧道，也不是认证。本轮已发布的本地 pin 没有这个参数，不修改现用版本或把示例当作可直接运行的安装指令。[固定提交的部署手册](https://github.com/deepseek-ai/deepseek-harness/blob/da00f7f5358f2949383b35c14f548bc20187d80c/docs/user/guide/public-deployments.md)、[固定提交的 Web 说明](https://github.com/deepseek-ai/deepseek-harness/blob/da00f7f5358f2949383b35c14f548bc20187d80c/packages/bundle/web-app/README.md)。

官方 Desktop 加载 `dsh-app://app/` 打包页面，向自身认证 Host 转发请求；Desktop 独占其 profile，CLI 不能启动它。查阅本轮官方说明和 Desktop Host 启动源码，没有找到现用 Desktop 的受支持手机配对/外部客户端入口；这不证明未来不会提供。不能从“Desktop 内部也是 Web 应用”推断“把动态端口转发出去即可完整支持 iPad”。[固定提交的 Desktop 说明](https://github.com/deepseek-ai/deepseek-harness/blob/da00f7f5358f2949383b35c14f548bc20187d80c/apps/desktop/README.md)、[Desktop Host 启动](https://github.com/deepseek-ai/deepseek-harness/blob/da00f7f5358f2949383b35c14f548bc20187d80c/apps/desktop-host/src/index.ts)。

如果将来重选 Web 路径，应先在独立 home/profile 验证官方前端及认证，然后决定唯一执行 Host 和会话数据迁移；共享磁盘上的历史数据不等于两个进程共享实时任务状态。不能让另一个 Web 实例读到历史便声称它接手了正在运行的 Desktop，也不使用 Desktop profile 启动第二个后端。

Cloudflare Tunnel 能通过出站连接提供 Web 入口，Access 可增加身份准入，但它仍要部署 HTTP 应用和鉴权、依赖 Cloudflare；官方明确 WebSocket 可能因网络更新被终止，并有空闲超时。因此只更换隧道不能保证修复旧客户端状态同步或重连问题，本轮不把它作为首选，更不开放匿名公网入口。[Tunnel 官方说明](https://developers.cloudflare.com/tunnel/)、[Access Web 应用](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/)、[WebSocket 官方限制](https://developers.cloudflare.com/network/websockets/)。

## RustDesk：原生远控客户端与私有覆盖网

官方客户端支持 Windows、Android 和 iOS；iOS 可以作为控制端，但不能作为被远程控制的目标。官方提供 iPhone/iPad App Store 入口，Android 文档列出鼠标/触控模式。这适用于 iPad/手机接手 Windows 桌面，不是控制 iPad 本身。[客户端文档](https://rustdesk.com/docs/en/client/)、[官方 Android 指南](https://rustdesk.com/docs/en/client/android/)、[官方 iOS 产品页](https://apps.apple.com/us/app/rustdesk-remote-desktop/id1581225015)。

官方提供“Enable direct IP access”；默认关闭，默认直连接收端口为 `21118`。Tailscale 官方已有 RustDesk 直连指南：控制端输入被控机器的 tailnet IP，不必另建 RustDesk ID/中继服务器，指南也列出 iOS 和 Android。它与旧的 Tailscale Serve → DSH Web 不同：这里传递的是远控画面和输入，没有 DSH HTTP 反向代理。本轮只是核对支持文档，尚未本机验证。[Tailscale 官方 RustDesk 指南](https://tailscale.com/docs/solutions/access-remote-desktops-with-rustdesk)、[高级设置](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/)、[官方直连 FAQ](https://github.com/rustdesk/rustdesk/wiki/FAQ#i-only-use-rustdesk-for-a-few-devices-on-my-local-network-with-no-internet-connectivity-can-i-still-use-rustdesk-with-direct-ip-access)。

安全上有两个不能略过的事实：官方 FAQ 警告 direct-IP 不提供自身加密保障，不能把它宣传成 RustDesk 自带端到端加密；官方客户端文档又说明普通启动会连接公共服务器。若采用私有直连方案，应由加密覆盖网保护传输，并同时限制 Windows 防火墙和 tailnet 授权设备；不允许公网/LAN 旁路访问，也不能把“无需自建中继”说成“默认没有公共注册”。部署前还须实查当前版本的加密标识、监听接口和对外连接行为。[直连 FAQ](https://github.com/rustdesk/rustdesk/wiki/FAQ#i-only-use-rustdesk-for-a-few-devices-on-my-local-network-with-no-internet-connectivity-can-i-still-use-rustdesk-with-direct-ip-access)、[客户端默认行为](https://rustdesk.com/docs/en/client/)。

若改用完整自建 RustDesk Server OSS，`hbbs` 管理 ID/会合/信令，`hbbr` 负责不能直连时的中继；OSS 服务端免费开源，但自建主机、网络和升级由自己维护，集中 OIDC/2FA/管理控制台等属于 Pro 对比范围。这比只给自己的三台设备远控新增更多运维责任，不建议一开始就上。[Server OSS 官方说明](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/)。

## Chrome Remote Desktop：更少自建组件，但增加 Google 依赖

Google 官网说明可以远程运行另一台电脑的应用；Windows Host 可作为后台服务关联 Google 账户，不必对公网暴露一个 DSH HTTP 入口。官方 Windows 服务示例允许目标机器只有出站互联网可达，不要求直接互联网入站地址；该示例是云 VM 文档，不能据此保证本地家庭网络一定连通。[产品官网](https://remotedesktop.google.com/)、[Google 官方 Windows 服务部署文档](https://docs.cloud.google.com/architecture/chrome-desktop-remote-windows-compute-engine)。

官方 iOS/iPadOS 帮助明确写出浏览器访问 `remotedesktop.google.com/access` 并添加到主屏、PIN、虚拟触控板及 Windows 触摸模式，也称远程会话完全加密；Android 有独立使用指南。该 iOS 页面仍包含“打开 App”文案，但本轮未读到历史 App Store 链接的现行产品页，所以**不保证现在仍可新装原生 iOS App**，应以官方网页路径作为可证候选。添加主屏仍是网页，不等于避开 WebKit。[iOS/iPadOS 官方指南](https://support.google.com/chrome/answer/1649523?co=GENIE.Platform%3DiOS&hl=en)、[Android 官方指南](https://support.google.com/chrome/answer/1649523?co=GENIE.Platform%3DAndroid&hl=en)。

Google 文档要求互联网可达，列出出站 UDP、入站 UDP 响应、HTTPS `443` 和 STUN `3478` 等网络路径。仅证明 Google 登录页面可打开，或某个代理出口正常，不能证明远控媒体链路通畅；现有链式代理/移动网络下的行为尚未知。账户身份、服务注册和连接协商还依赖 Google，不是完全自托管方案。[官方网络排错](https://support.google.com/chrome/answer/1649523?co=GENIE.Platform%3DiOS&hl=en)、[账户授权和后台服务](https://docs.cloud.google.com/architecture/chrome-desktop-remote-windows-compute-engine)。

应选择自己的“Remote Access”后台 Host，而非给第三人的一次性“Remote Support”分享码。任何远控授权都可能访问整台电脑的应用、文件、邮箱和历史，并不局限于 DSH；Google 帮助页也明确指出这一权限范围。需要强账户认证、独立 PIN、控制移动端登录状态，避免在不可信设备保持连接。[Google 官方访问说明](https://support.google.com/chrome/answer/1649523?co=GENIE.Platform%3DiOS&hl=en)。

## 为什么本机不选 RDP，为什么串流只作备选

微软 Windows App 支持 iOS/iPadOS 和 Android 连接远程 PC，但官方 RDP 被控端要求受支持的 Windows 专业/企业/教育版；家庭版不能充当原生 RDP Host。不能混淆“家庭版可以运行客户端”和“家庭版可以被 RDP 连接”。此外，Windows App 的 Web 路径不能作为直接连接自己 PC 的浏览器版来推介。[Windows App 支持矩阵](https://learn.microsoft.com/en-us/windows-app/get-started-connect-devices-desktops-apps)、[微软启用远程桌面指南](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/remote-desktop-allow-access)、[Tailscale 官方 RDP 先决条件](https://tailscale.com/docs/solutions/access-remote-desktops-using-windows-rdp)。

即使将来合法升级到 Pro，RDP 也是 Windows 登录会话机制，不是简单镜像。必须验证同一 Windows 账户能否恢复既有 DSH 实例、断开是否保留任务及本地桌面影响；不得另建账户、另起 DSH Host 后假称为同一个应用会话。[微软 Windows 会话机制](https://learn.microsoft.com/en-us/windows/win32/termserv/terminal-services-sessions)。

Moonlight 官方支持 iOS/Android，免费开源；Sunshine 带有 Desktop 串流入口，官方指南也给出 Tailscale 路径和触摸/键盘操作。不过 Moonlight 指南强调直接连接，对中继带宽不作可靠承诺；Sunshine 的 Windows 捕获还涉及显示 GPU/显示器。这是视频桌面串流路线，增加编码、画面和输入链路，不是单纯文本远程 UI。[Moonlight 官网](https://moonlight-stream.org/)、[官方设置指南](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide)、[Sunshine Windows 捕获说明](https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2getting__started.html)。

## 启动试用前的验收设计

任何方案先征求部署方向，不恢复退役组件。第一轮只用可恢复的远控层配置，保持 DSH 的官方安装、profile、会话和插件不变。试用时记录：

- 从 iPad 和手机分别输入不同的测试文字，确认电脑收到并在同一 DSH 实例完成；不能用电脑重复输入冒充远程送达。
- 观察思考/工具输出/完成显示，断网再连接后确认仍是同一 Windows 桌面和会话。
- 检查中文输入、粘贴、长对话阅读、授权弹窗及手机横竖屏；远控画面不自动获得原生聊天页面的移动排版。
- 分别测试外部 Wi-Fi、蜂窝网络、前后台切换和锁屏恢复，不以本地网络或一个 ping 代替验收。
- 先完成每台移动设备的连通、输入和结果观察，再做 30 分钟连接及多次断网恢复；停用客户端不应停止电脑上的 DSH 任务。所有时间和结果在执行后记录，本轮没有执行这些测试。
- 记录只在私有覆盖网可访问的安全边界，或 Google 路径的账户/媒体连接边界；不能因为使用 VPN 就跳过远控本身的权限审查。

电脑睡眠/关机的可达性另行解决。Tailscale 官方说明其本身不能直接唤醒睡眠/关闭设备；通常需要同一局域网的常在线节点发送 WoL，且主板/网卡本来就支持。不得为了远控自动关闭锁屏、自动登录或全局禁止睡眠；是否增加唤醒设备应单独决定。[Tailscale 官方 WoL 说明](https://tailscale.com/blog/wake-on-lan-tailscale-upsnap)。

本文结果是方案调研和边界清单，不是当前远程功能已恢复或端到端测试通过。对应对话、只读核查和文档变更见 [维护记录](maintenance.md#2026-10-03-新远程访问方案调研)。
