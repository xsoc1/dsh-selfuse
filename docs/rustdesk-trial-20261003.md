# RustDesk + Tailscale 私有直连试行

2026-10-03 最新状态：用户明确要求仅访问 DSH 并授权清理。RustDesk 四条专属规则在 Persistent/ActiveStore 都为零，程序、原生配置、本轮独有缓存均可恢复归档；三份脚本和模板移到 `retired/rustdesk-trial-20261003`。以下为历史记录，不继续执行旧安装命令。当前接入/退役方法见[专用部署](desktop-remote-20261003.md)。

最新结果覆盖下方准备阶段：四条 ActiveStore 规则精确匹配，存在一条许可移动连接、无非预期连接、无服务；用户回复“正常”，确认连接和输入。随后用户明确“我只要远程dsh的访问”，整机远控不满足需求，此试行不再是最终方案。当前改验证[保留 Desktop 的 DSH 专用接入](remote-dsh-only-20261003.md)，没有自动卸载或关闭仍在使用的 RustDesk。

## 范围与当前结果

用户要求“试行一下首选的这套方案”，选择“先用 iPad”。只试行控制同一 Windows 上的官方 DeepSeek Harness Desktop，不另开 DSH Web Host。旧 Serve、远程插件、控制台和看门狗继续退役，现有 DSH 程序、插件、配置及会话不改。手机是第二个验收对象，本轮未观察到它在线。

2026-10-03 已完成官方下载、摘要/签名核验、F 盘解包和配置暂存。最初 23 项检查后的“原生配置准备”结论被用户报错推翻：文件实际在 Codex 私有 AppData 缓存。修复后用户原生管理员命令已记录真实配置的句柄路径及初始化时间，但三条限制规则又报“地址前缀无效”，目前只创建了一条 AllowDirect。最新修复替换 NetSecurity 拒绝的 IPv6 `::/0`，允许安全补齐缺失规则，并处理原生空 Package 读回；双 PowerShell 回归通过。完整管理员写入及移动连接仍待重跑命令。自动执行 RustDesk 被工具策略拒绝后没有换执行通道规避；旧 UAC 请求未成功启动，不能称远控已验收。

## 固定软件与配置

下载 [RustDesk 1.5.0 官方 MSI](https://github.com/rustdesk/rustdesk/releases/tag/1.5.0)，发布于 `2026-09-30T16:11:03Z`。资产 SHA-256 为 `624fe792ab1d76b35134dab84bff97a6bcd14043ffd090a2c6a2800f77580495`，本地一致；Authenticode 为 Valid、签名主体 PURSLANE。只执行 MSI administrative extraction（`msiexec /a ... TARGETDIR=... /qn /norestart /L*v ...`），退出 0；没有普通安装到 C 盘 Program Files 或安装系统服务。

程序在 `F:\Apps\RustDeskTrial\app\RustDesk.exe`，版本信息 `1.5.0+68`。exe 与核心库签名 Valid，二者摘要固定在脚本中；原包和提取日志保留。配置先暂存 `F:\Apps\RustDeskTrial\staged\RustDesk2.toml`，Firewall 命令再初始化 `%APPDATA%\RustDesk\config\RustDesk2.toml` 的真实位置；程序放 F 盘不表示原生用户配置也在 F 盘。真实地址、DSH 配置保护哈希和状态仅在私有 F 盘目录，不提交到 Git。

最初对逻辑 AppData 路径的 Test-Path、TOML 解析和两种 PowerShell 检查都继承同一重定向，不能证明普通 RustDesk 能读取。文件句柄显示实际位置为 `OpenAI.Codex_…\LocalCache\Roaming\RustDesk`；[Microsoft 的 MSIX 文件系统说明](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)解释了私有目录优先的合并视图。缓存副本保留为失败证据，不作为部署入口。现用脚本按实际句柄路径拒绝重定向，不能只依赖进程的 package identity：本机子进程 API 未报告身份，仍实际继承了文件重定向。

归档模板 [rustdesk-trial.toml](../retired/rustdesk-trial-20261003/config/remote/rustdesk-trial.toml) 曾开启 TCP `21118` 直连；白名单只填本账户 iOS/Android 设备的单个 IPv4，不采用整个 tailnet。使用 `approve-mode=password`、10 位临时密码；原生 `password-click` 是“密码或点击”二选一，不是两者同时要求。用户从电脑窗口取得密码，仅在设备之间使用，不发给 agent 或写进文档。

只开放画面、键鼠、剪贴板；关闭文件传输、终端、隧道、远程重启、摄像头、音频、打印、录制、输入封锁和远程改配置。没有永久密码、服务、开机任务或虚拟显示驱动；无服务版不保证控制 UAC/管理员窗口、注销后的登录界面和休眠电脑。

这是整机桌面远控，不是仅授权 DSH 窗口；控制端能看到 Windows 屏幕和使用已开放的剪贴板，验收时只放测试内容。移动端 App 的公共服务默认配置未由本轮核验，不能把电脑端的配置/规则说成所有设备都已禁止公共注册。

ID/relay/API 地址配置为 loopback 未使用端口 `127.0.0.1:9`，不依赖公共 ID 注册/中继。固定源码的 `get_rendezvous_servers()` 在该选项非空时仅返回自定义地址。`stop-service` 保持 N：若改为 Y，源码会连直连接收器一并关闭。来源：[配置实现](https://github.com/rustdesk/hbb_common/blob/229b904508364c8997aad0fb5af57effac859f60/src/config.rs)、[直连接收器](https://github.com/rustdesk/rustdesk/blob/1.5.0/src/rendezvous_mediator.rs)、[原生设置](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/)。没有真的在 loopback 建服务器，公共服务可能显示未就绪；实际无公共连接仍需运行时观察，不凭配置宣称已验证。

## 防火墙：权限未完成前不开程序

源码直接监听通配地址，不能假称只绑定 Tailscale。当前三种 Windows 防火墙 profile 均启用、默认入站 Block；既有较宽 WSL 入站规则保持不动。脚本只新增四条 RustDesk 程序专属规则：

1. AllowDirect：Tailscale 接口、电脑 tailnet IPv4、移动白名单、TCP `21118`。
2. BlockOtherSources：阻止该程序接受白名单以外来源，含全部 IPv6。
3. BlockOtherDestinations：阻止通过电脑 tailnet IPv4 以外地址接收入站，含全部 IPv6。
4. BlockPublicOutbound：阻止向移动白名单、电脑自身和 `127.0.0.1` 以外地址出站，含全部 IPv6。

三条 Block 与精确 Allow 配合，避免既有宽松 Allow 覆盖边界。IPv4 使用补集闭区间；全部 IPv6 分成不相交的 `::/1`、`8000::/1`，保持原有覆盖范围。本机 New-NetFirewallRule 提供器拒绝原 `::/0`，COM setter 接受并不表示提供器会接受。原生回归通过 [Microsoft 文档注明只读的 SystemDefaults](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule?view=windowsserver2025-ps#-policystore) 重放实际规则：旧写法为 0x80070057，拆分后通过地址校验再得到访问拒绝 5；这是写入前校验，不是实际策略提交证明。

成功标准是四条规则均从 ActiveStore 读回并核对程序、profile、动作、接口、地址、双向端口、服务及无 Package 限制。Windows 对普通 exe 返回空 Package，不能错误要求它一定为字符串 Any。不改系统默认规则、Tailscale 全局 ACL 或其他程序。

从 **Windows 开始菜单** 打开当前账户的“Windows PowerShell（管理员）”，不要使用 Codex 内嵌终端，执行以下命令并确认正常 UAC：

```powershell
& 'F:\tools\dsh-selfuse-sync-20260928\scripts\rustdesk-trial.ps1' -Action Firewall
```

命令先从受限 F 盘暂存文件初始化缺失的真实配置，使用 CreateNew 防止覆盖竞态；已有配置只检查，不覆盖不兼容值。写后核对物理路径并记录摘要/时间。RustDesk 必须正常退出，再处理规则：逐条验证已有规则的精确名称、归属及全部约束，任何碰撞均不改动；先暂时禁用本次精确 Allow，补齐/启用三条 Block，最后才恢复 Allow。不删除已有规则，不要求用户先清空或扩大范围；前次只创建 Allow 的情况直接重跑同一命令即可。

每次原生命令显式 ErrorAction Stop，失败记录具体规则/读回步骤并保持 FirewallApplied=false；安全归属匹配时禁用本次 Allow，不继续创建后续规则。已创建的 Block 保留，重跑只补缺项。必须看到 `Firewall action completed: Firewall` 才开启 RustDesk。失败记录在私有 last-error.json。最早 UAC 请求失败的具体原因仍未知；此前 FileNotFound 是 AppData 重定向，本次 0x80070057 是 `::/0` 提供器不接受，分别记录。

RustDesk 官方 FAQ 警告 direct-IP 不能当作自身加密保证；这里依赖 [Tailscale 私有覆盖网](https://tailscale.com/docs/solutions/access-remote-desktops-with-rustdesk)。不改用 LAN/公网地址试连，不开 Funnel、路由器映射或公共中继兜底。Tailscale 自身 direct/DERP 与 RustDesk 中继不同，本轮未改其网络策略。

## iPad 验收

权限和规则通过后，由用户手动打开 `F:\Apps\RustDeskTrial\app\RustDesk.exe`，另正常打开原来的官方 DSH Desktop。电脑须已登录、联网且不休眠。不能用另一执行通道绕过本轮的自动启动拒绝。

1. iPad 保持 Tailscale 在线，安装并打开 [RustDesk 官方 iPad 客户端](https://apps.apple.com/app/id1581225015)。
2. 在远程地址输入电脑的 tailnet IPv4，默认端口 `21118`；本机实际地址在私有 `trial-state.json`，不要填 RustDesk 数字 ID。输入电脑 RustDesk 窗口显示的临时密码。
3. 看到同一 Windows 桌面后，在 DSH 新会话仅从 iPad 输入唯一测试文字，例如“只回复 IPAD-REMOTE-20261003-OK，不执行工具”，电脑不要重复输入。
4. 核对运行开始、结束和最终回复；通过 RustDesk 剪贴板功能粘贴中文，检查字符完整，再断开、重连同一桌面。
5. 回报“连上/无法连接/密码错误”，截图遮住密码和身份。之后补外网切换、至少 30 分钟运行及 Android 验收。

电脑只读诊断也从 Windows 开始菜单的普通 PowerShell 执行；Codex 环境可能继续优先读取旧缓存，脚本会明确拒绝这类“原生验收”：

```powershell
& 'F:\tools\dsh-selfuse-sync-20260928\scripts\rustdesk-trial.ps1' -Action Verify
```

核对二进制与关键配置、真实规则、移动在线、所属进程/21118 监听、允许设备已建立连接、异常出站、服务数量和五份 DSH 配置哈希。未就绪退出 2；即使退出 0，也不等于密码认证、显示/输入和模型验收。ActualMobileAcceptance 仍为 pending，实际反馈另记维护手册。

## 重建、回退与发布边界

新电脑先核验固定资产并提取到同一受限 F 盘位置，再运行 `-Action Prepare`；遇到已有 RustDesk 配置、进程、服务或 trial state 会拒绝，须先单独检查/备份，不自动重置。准备前私有目录 ACL 仅当前用户、SYSTEM 和 Administrators 可访问。

回退先正常退出 RustDesk，再从 Windows 原生管理员 PowerShell 执行 `-Action RemoveFirewall`，只移除程序路径和归属匹配的四条规则。之后普通用户执行 `-Action ArchiveConfig`，仅当 NativeRootCreated 证明整目录由本次原生初始化创建时，将其移到 F 盘恢复目录；原生根预先存在时拒绝归档整目录，保留既有数据。没有原生初始化证据的旧缓存也不冒充真实目录处理。不递归删除，不卸载 Tailscale，不改 DSH、会话或旧 Web 归档。

脚本/模板/文档只准备在本地管理仓，没有提交/push、改变 Harness gitlink、安装 DSH 新插件或宣称云端同步。pwsh 与 Windows PowerShell 5.1 各 57 项通过，覆盖纯地址/规则/配置负例、实际重定向拒绝、F 盘隔离 fixture 中的原生配置写入路径、NetSecurity 提供器只读地址校验及实际规则的空 Package。真实修复流程另以隔离模拟规则库验证清洁创建、部分规则、重复应用、失败即止、安全重试、读回失败、归属/约束冲突及运行中拒绝；模拟不等于管理员实际提交。

原先“23 项、TOML 37 options、三主体 ACL”仅证明缓存副本，并非原生配置。用户新命令已持久记录真实原生初始化；Codex 内 Verify 仍明确拒绝被重定向的旧文件，不用缓存代替实际新配置。本轮不写 DSH profile、原生 RustDesk 配置或活动规则，五份 DSH 配置复核不变。四条实际防火墙及 iPad/Android 仍待重跑命令和移动验收。私有 `F:\Apps\RustDeskTrial\iPad-start.md` 给出本机真实连接地址，不入库。
