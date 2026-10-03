# 当前部署与配置来源（2026-10-03）

## 当前界面验收结论

最新远程反馈：用户在清除遗留强制 DERP、恢复 iPad 直连后确认“效果非常好”，并授权把这套同 Host 方案上云。iPad 使用改善按实际反馈确认，下面“尚待反馈”属于先前时点；手机与长期换网仍未独立验收。此次发布仅同步源码/方法/匿名模板，不上传真实 profile/state/凭据，不重启现行 Desktop。最终提交与远端读回见最新 maintenance。

十个保留包已由 CLI 安装，F 盘外置 link 目录的依赖连接已补齐。2026-10-03 用户正常退出后，只更新已通过 Windows 隔离验收的 memory-panel 包；旧包完整归档、五份 profile 文件哈希不变。新正式实例 PID 32384 的只读验收通过：九个 Host 激活、五个 Client 行和资源正常。用户起初报告仅见皮肤中心，在明确“设置 → 内置插件”的页内标签位置后回复“有了”；按实际反馈记录面板已找到，不等同正式保存或模型验收。11 项源码回归及隔离三面板/记忆保存读回通过。方法见 [安装与运行验收](../scripts/README.md)。本仓源码 pin 为已发布的 [42d47032d3d](https://github.com/xsoc1/deepseek-harness/commit/42d47032d3da839f088142c4b439f95128973a21)，包括退役、保留包源码及原生记忆修复；发布前文档 43/43、暂存空白及正常提交/push 类型检查通过。以下旧日期记录是阶段证据，不替代本结论。

## 部署关系和历史阶段

晚间稳定性修复：用户确认 iPad 打开页面仍跳重连。管理员核实并清除旧 `TS_DEBUG_ALWAYS_USE_DERP=1`，只备份/修改该服务环境行，原 Serve 与 DSH 配置保留；正常停止卡住的 Tailscale 经精确服务链恢复，最终服务/Backend Running、HTTPS200、原映射和无Funnel成立。iPad 恢复直连，实测从467–1671 ms改善到3–65 ms；两个移动尺寸90秒零断开、正式44项新实例复检通过。真实iPad长期稳定和手机仍待反馈，不能用电脑探针代替。接手重连先读[连接稳定性](desktop-remote-20261003.md#连接稳定性与旧调试项)及最新maintenance，旧强制DERP不作为常态优化。

当前授权覆盖下方历史扫码记录：用户“还是使用旧的授权方案: 在tailnet内就直接能够访问”，正常退出后切换 relay 0.2.0 的显式 `authorizationMode: tailnet`。在现有私网 Serve 内打开固定 HTTPS 根地址即可，无浏览器凭据/二维码登录；所有经 Tailscale 网络策略准入、能到达入口的设备拥有现有 Host 的会话、文件、命令和模型权限。中继仍只监听 loopback、拒绝 Funnel/错误 Host/Origin，原生签名 cookie 在服务端内存自动取得/刷新，不写入新 state 或返回浏览器，Desktop 本地鉴权保留。四份核心 profile 文件哈希不变，patch 仅变远程插件的授权字段；旧包/profile 可恢复备份。新实例 44 项只读、15 项回归、直接/外链无凭据 Chrome 首登及原生隔离通过；实际手机/iPad 人类验收仍待反馈。方法见[专用部署](desktop-remote-20261003.md#当前模式tailnet-直接访问)，本轮未推送。

移动最新反馈：用户先报告“出现了, 手机还没做”，随后明确“实时显示，已经结束”，确认先前实例的 iPad 实际输入/同步、实时显示及正常结束。手机随后报告 Google 智能镜头扫码到 Chrome 后提示 DSH authentication required；跨站首登 Strict cookie 问题已复现并修复，用户“已退出”后安装 relay 0.1.1，五份 profile 哈希未变。新实例的直接/合成外链 Chrome HTTPS 首登通过、二维码已刷新；实际手机与本次重启后的 iPad 尚待用户验收。账户加浏览器认证仍非逐设备配对，详情见[专用部署](desktop-remote-20261003.md#手机首连与独立验收)。

远程最新部署：用户授权接入同一 Desktop Host 并清理 RustDesk，正常退出后新增独立 `@dsh-selfuse/desktop-remote`。Serve 443 → `127.0.0.1:17893` → 同进程动态 Host；官方 ASAR/WSL fork未改，不另起服务。新实例十个自用 Host（既有九个 + relay）、五个 Client 正常；38 项只读、26 项真实 HTTPS 隔离流式检查通过。真 Safari/iPad/手机反馈仍单独确认。RustDesk 四规则和原生/缓存配置已退役并可恢复归档，Tailscale保留。方法见[专用部署](desktop-remote-20261003.md)，此前[接缝研究](remote-dsh-only-20261003.md)为阶段证据。

本机入口已切换为官方 Windows Desktop `0.2.0-rc.2`。程序位于 `F:\Apps\DeepSeekHarness`，真实用户数据仍位于 `C:\Users\HuangZY\.dsh`；安装到 F 盘不意味着用户数据也在 F 盘。桌面 profile 为 `C:\Users\HuangZY\.dsh\profiles\desktop`，与 WSL profile 独立。2026-10-02 13:28 完成十个保留包的官方 CLI 安装，原官方 bundle 保留；产物/受限配置备份在 `F:\Apps\DeepSeekHarnessPlugins\selfuse-20261002-rc2-final`，部署方法见 [安装器](../scripts/README.md)。正式图形/模型验收仍与 CLI、隔离 Host 和源码测试分开记录。迁移时加了 Windows 排除端口所需的动态 loopback 端口补丁，并将新会话初始预设设为官方 `standard`；运行期间设置后来发生变化，保留现状，不把它恢复成旧模板或保证预设一直锁定为 standard。可重建模板见 [Desktop patch](../config/desktop/cordis.patch.yml)。

此前自动化启动 Desktop 时，将标准输出/错误输出接到 `F:\Apps\DeepSeekHarnessRuntimeLogs` 中的持久文件；该实例完成 18 次更新检查且没有 `EPIPE`，后来在系统重启时段退出。2026-10-02 的只读现场检查表明，当前进程于 10 月 1 日 22:30 启动；F 盘重定向日志属于更早实例，不能用于计算当前程序的检查次数。没有修改官方二进制，也不把进程存在或短时无弹窗当成完整验收。详细时间线与后续验收见 [维护记录](maintenance.md)。

| 用途 | 当前本机位置与状态 |
|---|---|
| 官方桌面程序 | `F:\Apps\DeepSeekHarness`；Host 启动后监听 `127.0.0.1` 的系统分配端口 |
| 桌面用户数据 | `C:\Users\HuangZY\.dsh`；`profiles/desktop` 不装旧远程 UI 和图形控制台 |
| 当前桌面工作区 | 原生 `F:\tools`，标题 `tools (Windows)`；旧工作区与会话关联原样保留 |
| Windows 旧会话归档 | `F:\tools\dsh-retired-20260930\windows-sessions-legacy`；229 个压缩会话文件，共 264825963 字节；桌面活动 `sessions` 目录已重新建立 |
| WSL 旧会话 | `/home/huangzy/.dsh/sessions` 原样保留；旧 Web profile 移到 `/home/huangzy/.dsh/retired/web-profile-20260930` |
| DSH 远程入口 | 旧 `443 → 127.0.0.1:3080` 继续退役；新 Serve 443 指向随 Desktop Host 启停的 loopback 17893 relay，原生认证保留 |
| DSH 后台管理 | `dsh-watchdog` 和 `dsh-watchdog-ensure` 计划任务已移除，XML 备份在 `F:\tools\dsh-retired-20260930`；图形控制台与旧管理脚本不再部署 |
| 开发源码 | WSL `/home/huangzy/tools/deepseek-harness-current` 仅供源码维护，不是当前桌面程序；原生适配与退役源码已发布并由本仓 pin 固定 |
| 退役源码归档 | WSL `/home/huangzy/tools/dsh-retired-20261001/source-packages`；八个退役旧包完整移出构建树，195 个跟踪文件哈希一致；F 盘 `dsh-retired-20261001` 保存清单与日志 |
| 原生 UI 精简归档 | WSL `/home/huangzy/tools/dsh-retired-20261001/native-ui-packages`；设置/社区/skins/all 四包归档，46 个跟踪文件哈希一致；候选配置独立加载 Git 图和皮肤中心，真实 Desktop 未改 |
| 条件插件及闲置 SDK 归档 | WSL `/home/huangzy/tools/dsh-retired-20261001/conditional-packages`；SSH、任务板、MinerU、旧 ClientRuntime/ApiProxy 完整归档，764 个文件/链接记录逐项一致；原生 SSH 与计划任务优先 |

旧报错 `Unknown agent preset: wsl-router-standard` 来自导入的历史会话：官方桌面版不注册自用 WSL 预设。按用户选择，旧 Windows 副本已归档，追加式日志没有改写，新会话采用官方 `standard`。此前 Windows Desktop 在 WSL UNC 工作区新建文件报硬链接 `ENOTSUP`，不能靠对话结束就认定文件工具正常。用户本轮选择原生 F 盘工作区并退出程序后，先备份 `workspace.json`，再新增 `F:\tools` 工作区并更新设备本地导航选择；没有把旧会话重映射或搬移到 F 盘。

真实桌面会话 `session-44a94132-2ad7-414f-8c79-0506c5510bc6` 的头部为 `cwd: F:\tools`、`agentPreset: standard`，模型实际调用 `write → read → edit → read`，四份工具结果均非错误，整轮为 `completed`；没有以 bash 或 `run_code` 代替。安装包内 Win32 文件系统另通过八项检查，包括原子新建、编辑、过期版本拒绝和不覆盖保护。旧三个工作区及其会话关联与备份逐项相同。临时调试入口已关闭，验收脚本和结果在 `F:\tools\dsh-retired-20260930\native-workspace` 可恢复归档；第三方插件仍未安装、未验收。具体方法见 [后续修复验收](maintenance.md#2026-09-30-继续修复原生-f-盘工作区与源码门禁)。

2026-10-01 阶段快照：本仓 `vendor/deepseek-harness` 当时锁定此前的 `c9896317dd6`，退役与接口修复尚未提交、推送。旧 `config/`、`plugins/`、`community-plugins/` 是历史资料，不能覆盖真实 Desktop profile。当日后续修复通过 24 项定向回归、类型检查、构建、文档门禁 43/43 和文档测试 21/21；卫生门禁为 12/18，完整构建后全仓 lint 仍有 269 个错误和 1 个警告，发布被阻止。SSH/任务板缺失构建配置、仍依赖旧 Client API，整仓构建通过不等于冻结 bundle 已重建或 Desktop 已启用第三方插件。当时未改动或重新验收真实桌面实例与会话。细节见[接口修复记录](maintenance.md#2026-10-01-继续修复请求校验与真实服务回归)。

旧[升级说明](upgrade-0.2.0-rc.1.md)和 [Safari/Tailscale 手册](safari-tailnet.md)记录历史链路，不再是当前部署操作指引；桌面端决策与回退见[迁移评估](desktop-migration-0.2.0-rc.2.md)。任何将来发布仍须先通过全部要求。

2026-10-01 用户随后批准旧 UI/兼容包精简，并明确选择“归档三个条件项，优先原生功能”。当前开发树已移出 SSH、任务板、MinerU 及不再使用的两个 SDK；皮肤中心恢复固定上游源码并改接原生 ConfigForms，Git 图谱、皮肤中心和通知实际重建，隐私插件也改接严格 Host 构建。Git 工作流另完成真实 TS/bundle 与原生工具执行回归。所有改动仍在开发候选，真实 Desktop 未安装这些包。完整检查与未完成项以[本轮维护记录](maintenance.md#2026-10-01-条件插件归档与可重建源码收尾)为准；前文数值属于之前的验收快照，不代表本轮最终结果。范围、清单及回退见[精简说明](plugin-retirement-20261001.md)。

同日“继续维护”后，backup 也迁为严格 Host/Client 源码与原生 bundle，修复恢复时误删归档、Git 换远端的 lease、大列表截断及符号链接下载；皮肤中心收紧 CSS 声明后补齐六个缺失目录控件样式。真实 Desktop profile 的两份文件哈希与保护清单一致，lockfile 仍不存在；源码和隔离测试不是已安装插件验收。最新检查及剩余发布阻塞见[后续维护记录](maintenance.md#2026-10-01-继续维护备份包和样式声明)。

同日用户输入“xiu”后，候选 memory-panel 已迁为真实严格 TS 和原生 RPC/设置界面，不再依赖旧 `/memory/api/*`。该面板只供人浏览、搜索和创建本地 Markdown，不是给模型注入记忆的系统，也没有装入真实 Desktop。该批检查是历史阶段结果，见[记忆面板修复记录](maintenance.md#2026-10-01-xiu记忆面板原生适配)，不代表后续最终验收。

2026-10-02 用户要求完成全部任务，批准归档 undo、保留 backup 与官方原生恢复；undo 完整移至 `/home/huangzy/tools/dsh-retired-20261001/undo-retirement/undo`，36 个文件/链接记录、869861 字节逐项一致，快照数据未删除。候选保留包已可重建，退役移动端加载恢复官方 rc.2 方式。全量单元测试、构建、lint、文档及构建产物回放分别通过；卫生门禁的共享 mount 分类仍待人工确认，补跑的官方客户端分层检查有 82 项失败，因此完整发布未通过。9 个保留 Host 条目已在签名安装版的隔离 F 盘 profile 激活，记忆文件与 Windows tar 备份/校验/恢复预览通过；不是正式 Desktop 图形或模型验收。真实 profile 未安装候选包，本轮未重启或改会话；00:35 实际 patch 在程序运行中变化，作者未确认，已保留新状态而非恢复旧哈希。package.json 不变，lockfile 仍不存在。未发布或更新子模块 pin；最新证据见[完成任务记录](maintenance.md#2026-10-02-完成全部任务进行中)。

后续 82 项客户端分层错误已归零，597 文件/9518 项 GUI 单元与 Client 类型检查通过；10 个保留包也经真实嵌套 npm 链路重建。全量单元复跑 39211 项通过，之后的字典所有权合并保持 6 字典/242 键值逐项不变，本地化检查也通过；最终 GUI/类型检查和浏览器回放仍在运行，共享导出分类待人工确认。因此仍未提交、推送或更新子模块 pin。正式 Desktop 和模型验收未被隔离 Host 测试替代；详细最新状态见上面的维护记录。

12:30 后续：用户已单独批准 `mountOnce` 共享 peer 分类，并正常退出 Desktop，实际进程为 0。四份插件 manifest 按原有依赖策略修正，48 项回归通过；字典合并后的 GUI/类型/lint 通过。浏览器失败定位为缺失 WebKit/字体依赖及旧 Chromium 字体缓存，隔离缓存后三项布局原断言通过；完整固定产物复检仍未完成。真实 profile 尚未安装候选包，配置哈希未变，lockfile 不存在；不将当前候选和正式部署混为一谈。

13:30 当前状态覆盖前文历史快照：71 项总门禁、最终完整浏览器 lane 与全仓 lint 通过，后续测试修复的相关回归和分层检查也通过。正式 CLI 已安装十包并保留 11 个 bundle 层，profile 有 lock，用户设置正文和会话未改写；新 Desktop 实例用部署目录持久日志启动，初次更新检查无 EPIPE/插件启动错误。正式 UI 面板验收请求等待用户反馈，真实模型未重新测试。源码/管理仓尚未提交或推送、旧子模块 pin 尚未变，不能宣称云端已经同步。
