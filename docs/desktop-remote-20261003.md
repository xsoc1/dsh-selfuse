# 官方 Desktop 同 Host 专用远程接入

最新实际反馈（2026-10-03）：用户在直连修复后确认“效果非常好, 就按这个方案上云”，发布后补充“手机我已验收”。据此接受当前 iPad 与手机实际验收；长期换网及其他模型/备份操作仍分开记录，不补造具体测试过程。当前 tailnet 模式及正常直连尝试为现用方案，源码、匿名模板、诊断/回退和退役方法已发布；历史扫码/远控章节仅供追溯，发布证据另见 maintenance。

## 当前模式：tailnet 直接访问

用户最新明确“还是使用旧的授权方案: 在tailnet内就直接能够访问”，随后回复“已退出”。现用扩展 **0.2.0**，配置显式 `authorizationMode: tailnet`；此选择覆盖下方历史 owner-browser/扫码记录。

手机/iPad 连接当前 tailnet 后，直接打开私有 state/connect.html 中的固定 HTTPS 根地址即可。无需登录 token、二维码交换或浏览器 cookie；可收藏该根地址，重启 Desktop 不改变访问地址。可选二维码只编码固定地址，不是授权凭据。Desktop 仍须运行；不是远控整机，也不是独立后台 Web Host。

权限边界是 Tailscale 网络规则允许连接此入口的设备，不再要求同一 owner 登录账户。它们拥有当前 DSH 的会话、文件、命令及模型权限，没有用户间文件隔离或逐设备审批。Tagged 设备不依赖用户登录头。不要把不受信任的设备/分享对象放进该访问范围。本机进程和本机 Serve 在信任边界内；loopback 转发头不是独立的进程身份认证。

中继仍检查 loopback、精确 Host/转发 Host、HTTPS、Serve 覆盖的单个源地址（100.64.0.0/10 或 fd7a:115c:a1e0::/48）、无 Funnel，以及正确 Origin。依据[固定 1.102.4 源码](https://github.com/tailscale/tailscale/blob/v1.102.4/ipn/ipnlocal/serve.go#L996-L1033)，Serve 覆盖源地址并清除冒用身份头，tagged 节点不带用户头，因此本模式不以 ownerLogin 限制成员。仅私网 Serve 和网络策略仍是外部请求的入网边界，没有新增公网/局域网监听。

准入后中继经公开 `ctx.connection.authenticatedUrl()` 调原生 loopback 认证，取得原生签名 cookie，只在内存缓存、到期前刷新，HTTP/RPC/mux 上游携带；不写 state、不返回给浏览器。Native 认证失败时 503，不回退匿名。浏览器旧 cookie 不影响准入，旧含 token 的根链接在准入后跳到干净根地址。原生 Desktop 本地 index/RPC/mux 仍要求凭据，未改 Connection 全局鉴权或官方 ASAR。

已有安装切换：正常退出并确认零进程，用随包 Electron Node（`--expose-internals`）执行 `scripts/desktop-remote-mode.mjs tailnet`。Helper 在受限部署根备份旧 plugin、五份 profile 和私有配置；只更新独立 payload 与远程 patch 的 mode/owner 字段，四份核心配置哈希不变、其他 patch 行语义原样保留。保留现有 CLI link、trustedHosts、Serve 端口和映射。新的空目录安装须显式 `desktop-remote.mjs install --tailnet`；默认仍为兼容 owner-browser，避免无意扩大授权。

本次备份为 `F:\Apps\DeepSeekHarnessRemote\mode-before-ob056v`。回退需正常退出，再执行 `desktop-remote-mode.mjs owner-browser`（重新取得当前 owner 身份并备份），或精确恢复本次备份中远程 payload/授权字段；其他用户配置有更新时不要整份覆盖。原二维码登录的跨站过渡修复保留在 legacy 分支中。此扩展独立归管理仓持有，无对应 fork 包需要覆盖，未触及 WSL/官方源码。

本轮结果：15 项回归、原生 CLI/激活及无浏览器凭据的隔离认证通过；正式新实例 44 项只读、全新 Chrome context 直接/合成外链打开固定根地址均通过，未存储原生 auth cookie，刷新/重连正常。手机与 iPad 实机及真实新消息/流式完成仍待用户验收，不用合成外链或移动视口代替。具体失败与结果在 maintenance；未推送。

## 连接稳定性与旧调试项

用户报告“经常跳重新连接”，确认 iPad 在打开页面时仍跳。2026-10-03 晚间先发现 Desktop 未运行、两个本地端口拒绝连接、HTTPS 502；原因未知，不能据此解释所有间歇重连。启动原程序后，两种移动尺寸 Chromium 连续 90 秒无断开，iPad 实机仍报重连，因此不按电脑侧成功结案。

管理员只读原生路径检查发现遗留 `TS_DEBUG_ALWAYS_USE_DERP=1`，iPad 无直连，五次 DERP(nue) 延迟为 467–1671 ms。此开关来自旧 Web 排错，不是常态优化。精确备份并移除后，原有 Tailscale/Serve/DSH 身份保留，iPad 直连存在，十次探测为 3–65 ms。直接连接通常延迟更低，条件受 NAT/UDP 限制，不能保证换网后永久直连；参见[官方连接类型](https://tailscale.com/docs/reference/connection-types)。本次证明了旧开关阻止直连及移除后的质量改善，没有证明它是所有重连的唯一原因。

备份在受限部署根 `tailscale-before-direct-20261003-213954`，原文件只有该开关，移除后为空文件；不包含需要保留的其他设置。服务正常停止卡住，单独恢复脚本校验签名、Stop Pending、服务 PID 和直接子进程，仅回收停止中的 Tailscale；原正常重启 helper 随后完成启动。最初 Serve 读回处于初始化时点、恢复 helper 也因另一个 helper 已启动而未走完其最终等待，不能把两份初始 false 收据改称成功。最终以服务 Running、Backend Running/健康无告警、原 `443 → loopback 17893` 映射、无 Funnel、实际 HTTPS 200 及管理员新读回 forcedDerp=false 为准。后续脚本已收紧停止等待和有界读取，并处理并发恢复状态。

维护顺序：先查当前 state 的 PID/端口和实际进程；用 `verify-desktop-remote-stability.mjs --seconds=90` 记录前台 mux 断开/恢复事件与只读 RPC 时间，不采集帧/会话内容。再核对实际移动端和网络路径；一次 ping 不是应用验收。此轮重新启动的 Host PID 34256，未改官方 ASAR、Desktop profile 或会话；电脑侧修复后再测 90 秒无重连，iPad/手机长期前后台/换网仍待实际确认。回退只在管理员正常停止 Tailscale 后恢复本次 env 备份、保留文件 ACL，再启动核验；不要整份回滚 DSH profile、重建旧 WSL 服务或开启 Funnel。

## 方案和权限

用户明确“我只要远程dsh的访问”，选择“必须保留官方桌面客户端，先验证专用远程接入”，随后授权“接入, 然后把之前失败方案的遗留清理一下”并确认“已退出”。本轮正式安装小型 Host 扩展，不是第二个 DSH 服务或远程桌面。

移动浏览器 → Tailscale Serve 私网 HTTPS 443 → loopback relay 17893 → 当前 Desktop 动态 Web 端口 → 同一原生 Connection、前端、会话及工具。Relay 与 Desktop Host 同进程/生命周期，只绑定 `127.0.0.1`；退出 Desktop 后没有可用远程后端，不支持关机、休眠后的访问。

仅呈现 DSH 不等于只读或文件隔离；当前 tailnet 准入客户端拥有该 Host 的现有文件、命令及模型权限。原有模型、预设、权限、插件和 QQ 配置保留。没有开放整机画面控制、键鼠、匿名发凭证接口、旧 WSL 服务或看门狗。

## 来源与安全

源码归本管理仓 `plugins/desktop-remote`，零 npm 运行时依赖；部署归 `scripts/desktop-remote.mjs`。这是独立管理层扩展，使用已核对的官方 rc.2 公共 Host API；未修改官方 ASAR 或 WSL fork、复制前端、另挂静态 fallback。manifest 单列该组件，不冒充 fork 中的官方包。

[Serve 文档](https://tailscale.com/docs/features/tailscale-serve)和[所用 1.102.4 源码](https://github.com/tailscale/tailscale/blob/v1.102.4/ipn/ipnlocal/serve.go)表明，TCP target 保留浏览器 Host，设置转发 Host/Proto/真实源地址，并清理输入身份字段。当前 tailnet 模式采用上文入网边界，网络规则准入设备直接进入；可回退的 owner-browser 模式另外限定精确账户并要求浏览器凭据。

仅在官方 `connection.trustedHosts` 中加入该精确 authority，保留其他配置。上游仍由原生 token→签名 cookie 交换处理、RPC/mux 保持原生鉴权；当前 tailnet 模式的凭据只在中继内存内使用。原生默认为 HttpOnly、SameSite Strict、30 天；legacy 模式才会把加 Secure 的 cookie 发到浏览器。Funnel 未启用。

0.1.1 修复浏览器跨站首登：仅在顶层 GET 导航携带单个 token、原生回复 `303 ./` 且签发原生 HttpOnly/Strict cookie 后，relay 返回受 CSP nonce 限制的最小同源文档，再导航到无 token 的根地址。保留 Secure/HttpOnly/Strict、签名和 audience；错误 token、匿名访问、其他重定向以及非浏览器导航的 303 不改。文档 no-store、no-referrer，HTML 不重复凭据，也不向 JavaScript暴露 cookie。此处没有新增设备配对或匿名登录接口。

## 部署和首次登录

当前官方程序 `F:\Apps\DeepSeekHarness` 为 `0.2.0-rc.2`；扩展独立部署在 `F:\Apps\DeepSeekHarnessRemote\plugin`，真实 profile 为 `C:\Users\HuangZY\.dsh\profiles\desktop`。新部署目录只允许当前用户、Administrators、SYSTEM 访问。

1. 正常退出 Desktop；先运行单位、原生 CLI 和 HTTPS 隔离检查。安装器拒绝重复覆盖部署目录，已有安装不能盲目再次执行 install。
2. 新空目录以随包 Electron Node 模式执行 `scripts/desktop-remote.mjs install --tailnet`；已有安装用上文 mode helper。先备份并哈希读回五份 profile 文件，再直接执行随包 `dsh-desktop-host/lib/cli.js` 的 `plugin --profile desktop add link:...`（带 `--expose-internals`），不用 CMD/.cmd。旧 patch 行逐项比较，仅新增 trust 和扩展行。
3. Serve 原无配置时才运行 `tailscale serve --bg --https=443 --yes http://127.0.0.1:17893`；已有其他映射时停止讨论，不全局 reset。正常启动 Desktop前移除 `ELECTRON_RUN_AS_NODE`，stdout/stderr 接受限持久日志。
4. 当前 tailnet 模式在私有 `state/connection.json` 保存 mode/端口/固定地址，不保存登录 token；`state/connect.html` 说明固定入口。退出时清除这两份状态。Legacy 模式才保存启动登录链接。不提交实际身份、token、私有地址或日志。
5. iPad/手机先连接当前 tailnet，直接打开固定 HTTPS 根地址并收藏；无需 token 或浏览器 cookie。当前模式不应再提示要求重开 dsh web 登录 URL。

可选扫码：固定 [qrcode 8.2](https://pypi.org/project/qrcode/8.2/) 在 F 盘 qr-helper，用既有 Python/Pillow 本地生成 `state/login-qr.png`，不调用在线 QR 服务。当前图片仅编码固定根地址，不是凭据，Desktop 重启无需换码；更改入口域名后才须重生成。Legacy 启动凭据二维码须重启后更新。命令见 scripts/README，Host 不依赖二维码工具。

人工验收只在移动端发唯一标记，电脑不重复输入；核对两端同一消息、实时思考和共同结束。Safari 前后台/换网、iPad、手机各自验收，Chromium 视口不能代替它们。

## 已执行检查

| 层 | 结果 | 边界 |
|---|---|---|
| Relay 单位测试 | 10/10：legacy 传输/登录、tailnet 准入/拒绝、无浏览器 cookie 的 HTTP/mux、凭据缓存并发/到期/关闭/失败 | 模拟 Serve/上游；与既有验收器合计 15 项 |
| 原生 CLI 隔离 | 5 项通过，实际 link 包激活、动态端口、旧配置保留、实际原生服务器端认证、退出清状态；mode AST 来回切换保留无关行 | 模拟私网 carrier，不是手机/真实 Serve |
| 真实 HTTPS 隔离 | 26 项通过，移动 prompt、可见 reasoning、共同完成、WS 重连/刷新 | 纯本地模型和独立 home，不是真 Electron 窗口/Safari |
| 正式只读 | 当前 44 项：保留包激活/资源、无浏览器凭据的 HTTPS/RPC/mux，原生 loopback index/RPC/mux 401、错误 Origin 403，两个移动视口各 15 秒稳定/主动重连/无凭据刷新 | 0.1 模式的 38 项为历史；未发模型请求，不代替手机 |
| 实际 iPad | 用户先确认消息出现，再明确“实时显示，已经结束” | 先前 0.1.0 实例通过；当前 0.2.0 tailnet 模式未重复实机验收 |

首轮把异步初始化放在 ctx.effect，读取时 state 尚未产生而失败；改异步 apply 并同步注册 disposer 后通过真实 Host/HTTPS。失败 fixture 保留，未写正式 profile。受限证据在 `F:\tools\dsh-remote-validation-20261003` 和部署根 `live-acceptance.json`；本轮没有提交/push。

## 手机首连与独立验收

当前结论：用户已明确“手机我已验收”，手机实际验收按人类反馈通过；下方旧扫码失败和待反馈是历史时点，不代表当前仍未验收。长期前后台/换网未独立确认。

当前 0.2.0 首连：手机/iPad 连接 Tailscale 后直接打开固定 HTTPS 根地址，不扫码登录；只在移动端发送唯一验收消息，PC 不重复。以下为 0.1 owner-browser 模式的历史排错，不是当前操作步骤。

用户随后要求“弄一下手机端接入”。本轮核对已登记的 Android 手机在线且为同一 Tailscale 账户；正式 Serve、同 Host relay 和当前启动链接有效，匿名访问 401、令牌交换 303，cookie 含 Secure。仅刷新受限本机二维码，不修改已经通过 iPad 验收的 Host/profile、trust 或身份范围。

1. 手机保持现有 Tailscale 连接，无需 RustDesk 或另一个 DSH 后端。
2. 扫描当前 `state/login-qr.png`，将链接交给系统浏览器打开。该图片含当前启动凭据，只用于自己的设备；电脑重启后重新生成，不能提交/公开分享。
3. 只在手机发送唯一“远程验收-手机”，电脑不重复发送。分别确认电脑收到同一消息、手机实时显示、正常结束。
4. 首登成功后收藏不含 token 的 HTTPS 根地址；电脑 Desktop 保持运行。

手机在线不等于 DSH 已验收。用户已反馈“你这个授权不是授权的设备, Google智能镜头扫描以后chrome是打不开的”，手机首连失败，不再仅记为未执行。复检时 Desktop 存活、Android 在线、电脑侧匿名 HTTPS 401、当前启动链接 303 且 cookie 含 Secure；这些结果不覆盖 Google Lens 到真实 Android Chrome 的路径。目前没有该手机的具体错误/请求记录，不能认定 Lens 改写链接、DNS、TLS 或身份校验为根因。

下一步：请用户提供 Chrome 错误截图/原文，遮住地址栏 `token=` 后的凭据；可将扫码所得完整网址复制到 Chrome 地址栏直接访问，以与 Lens 的打开动作作人工对照。该对照仍待用户执行，不能称为修复成功。取得实际错误后再沿手机 DNS/TLS、原生登录、mux 和会话状态分层定位；保持 iPad 已通过的配置，不放宽身份/Origin 检查或重启服务来猜原因。

最新进展覆盖上段等待状态：用户给出 `dsh web authentication required; reopen the URL printed by dsh web`。`verify-desktop-remote-login.mjs` 在现用 HTTPS 的全新 Chrome context 复现直接链接 303→200、合成外链 303→401，CDP 明确报告 `SchemefulSameSiteStrict`；cookie 已存储且同一 context 再直接导航可得到 200，因此该复现排除了无效 token 和错误 audience。这是跨站首登同类问题的证据，仍不能声称已观测 Google Lens 实机行为。

先新增失败回归，再实现上述 0.1.1 同源过渡；9 项单位/验收器回归通过，临时源 relay 加实际原生认证/Chrome 的直接与合成外链场景都为 200、无 Strict 拦截。用户随后“已退出”，核对 Desktop 零进程、部署 ACL、备份旧插件并逐项读回哈希后替换四份 payload；五份 profile 配置哈希完全不变，官方 exe 签名仍为 Valid。备份在 `F:\Apps\DeepSeekHarnessRemote\plugin-before-login-fix-20261003-165408`。新正式实例的直接和合成外链 Chrome HTTPS 首登均通过；登录二维码已按新启动重新生成。实际手机及重启后 iPad 仍待用户验收，本轮未推送。

后续插件更新方法：正常退出并确认零进程；在受限部署根下新建唯一备份目录，复制旧 plugin 并核对原文件摘要；只将本仓 plugin 的 index/package/test/README payload 复制到现有外置 link 目录并与源哈希比较。保持原 CLI link、profile/trust/Serve 不变；启动前移除 `ELECTRON_RUN_AS_NODE`、使用受限持久 stdout/stderr，先执行登录及正式只读检查，再刷新私有 QR。安装器 `install` 仍拒绝覆盖已有部署，不能为更新再次执行 install。失败时正常退出后从本次备份恢复 payload，不覆盖用户配置。

新正式实例的 `verify-desktop-remote-live.mjs` 再次 38 项通过：保留包激活/资源、匿名 index/RPC/mux 401、外部 Origin 403、两个移动视口各 15 秒稳定/主动重连/刷新均成立。受限 live-acceptance.json 绑定本次 PID，不复用旧实例结果；不发送模型请求，不替代实际手机结果。

## RustDesk 清理和恢复

实际移动反馈：用户先回复“出现了, 手机还没做”，随后对实时显示/正常结束问题明确回复“实时显示，已经结束”。iPad 本轮实际输入/同步、实时思考/回复与正常结束通过人类确认；手机未执行，不能称全部移动验收完成。

工具内 UAC 确实启动，但仍继承 MSIX AppData 重定向，句柄检查拒绝清理、四规则保持原样；没有把提权启动当作完成。用户随后从开始菜单的原生管理员 PowerShell 执行清理并回复“已清理”。

读回 retirement 为 completed；PersistentStore/ActiveStore 四条专属规则均为零，RustDesk 进程/服务零，原试行根不存在。程序、原生配置及材料移动到受限 `F:\tools\dsh-retired-20261003\rustdesk-trial-20261003-160233`。MSIX 私有缓存仅有一个 TOML、摘要与试行 staging 完全相同，仅把该确属本轮目录移动到归档的 codex-private-config；不动其他 AppData 或 Tailscale。

三份试行/清理脚本和模板逐文件哈希一致，保留布局移到本仓 `retired/rustdesk-trial-20261003`，退出活跃 scripts/config。历史调研保留，不作为当前指引。移动设备的 RustDesk App 不在电脑权限范围，是否卸载由用户处理。

回退新入口：正常退出 Desktop并备份当前 profile；确认 Serve 仍为本扩展的精确映射，只关闭该 HTTPS 443 映射，不全局 reset。用官方 CLI移除 `@dsh-selfuse/desktop-remote`，从当前 patch 只移除新增扩展行与 authority（原来已存在则保留）。参照 profile-before/manifest.json；运行期间用户有新配置时，不用整个旧备份覆盖。扩展目录可恢复归档，会话/记忆/账号数据不删除，RustDesk 归档不自动恢复规则或安装服务。
