# AGENTS.md — dsh-local 维护基线

本文件是 `xsoc1/dsh-selfuse` 管理仓的维护基线。任何 agent/human 进入本仓库先读本文件；每次变更后更新 `docs/maintenance.md` 中的维护记录。

## 工作方法

1. 进入仓库先读 `README.md`、`AGENTS.md`、`docs/current-deployment.md`；历史方案单独见 `docs/PLAN.md`。
2. 改动前先看 `manifest.json` 和活跃 Harness 工作树；区分云端快照、运行源码、用户配置与旧安装器。
3. 不把密钥/凭据/大模型二进制提交进 Git（见 `.gitignore`）。
4. 修改当前部署方法时，同步核对 fork 中的 `config/selfuse/`、`scripts/selfuse/` 和 `packages/selfuse/`，更新本仓 `manifest.json`、相关快照及 `docs/maintenance.md`。
5. 当前入口是官方 Windows Desktop `F:\Apps\DeepSeekHarness`；真实 profile 在 `C:\Users\HuangZY\.dsh\profiles\desktop`。自动化启动时用 `Start-Process -RedirectStandardOutput/-RedirectStandardError` 将两个输出流接到持久、仅当前用户/管理员/系统可访问的文件，并在启动者退出后核对更新轮询；单纯调用 Windows Shell 仍可能继承短命输出管道。WSL 源码链接仅供开发，旧 Web profile 已归档，Windows 旧会话在 F 盘归档。部署事实以 [当前部署](docs/current-deployment.md) 为准。
6. `F:\tools\dsh-local` 与 `F:\tools\deepseek-harness` 旧工作树有用户未提交改动；不覆盖、不批量清理。旧 `install.ps1` 不适用于当前 Desktop。
7. 子模块 pin、WSL 源码、Windows Desktop 程序、真实 Desktop profile 与用户数据是不同状态；版本升级须分别核验。发布前先通过全部文档门禁、构建、定向测试和隔离启动；第三方包只通过官方桌面随包 CLI 管理其独立 profile，不能把 WSL 插件安装记录当作桌面验收。
8. 文件工具验收同时核对执行世界与实际工作区。Windows Desktop 经 `\\wsl.localhost` 访问 WSL 不是 WSL 原生执行；现有真实日志已出现原子新建文件硬链接 `ENOTSUP`。Windows 原生工作区与 WSL 内部工作区分别验收，完整对话结束不代表每个工具调用成功。
9. 当前原生工作区是 `F:\tools`。正常退出后备份 workspace registry，再新增工作区并核验客户端导航；`defaultWorkspaceId` 不等于导航默认值。真实 `standard` 会话的四次文件调用通过，旧工作区与会话关联未改。验收和回退材料在 F 盘 `dsh-retired-20260930/native-workspace`，不能用退出码 0 的空输出代替实际探针结果。
10. 外置 F 盘 link 插件须验证实际运行依赖。部署根声明由官方安装提供的 peer，并逐包连接原生依赖，不复制 WSL/ASAR node_modules；实际九个 Host fiber 与客户端 boot graph 均须核验，profile bundle 能解析不是激活证明。
11. Electron Node 工具调用结束后，以 `Remove-Item Env:ELECTRON_RUN_AS_NODE` 移除该进程环境项再启动桌面窗口；本机 PowerShell 的 null setter 保留空变量，不能视为移除。记录实际实例、当前日志和人类界面反馈，不复用旧实例的成功证据。

## 2026-10-03 同 Host 专用接入与清理

发布触发：用户“效果非常好, 就按这个方案上云”，接受当前 iPad 使用改善并授权同步 `xsoc1/dsh-selfuse`；手机/长期换网另验。按 writing-for-agents 收敛现用与历史分支，发布前核对差异归属、敏感信息、模板/schema/文档链接、回归与原生隔离；普通快进推送后读回 ref/选定blob。只发布管理层独立扩展与方法，不改源码fork pin、官方ASAR或运行配置，不上传真实state/日志/会话。具体过程与提交见最新maintenance。

发布结果：同 Host 接入和直连维护已以 `fd4659bb5d87aaa1526f1d01a43bfe9c726998d4` 快进同步至 main，fetch ref 与全部35份发布blob一致，gitlink未变。本地复检通过不等于GitHub CI：本次API无workflow/check-run报告。完成状态另作文档提交；继续维护以当前部署/maintenance为准，不复用历史“候选”结论。

连接稳定性触发：用户“经常跳重新连接”，确认 iPad 打开页面仍跳。先核对现行 PID/端口，再用 90 秒只读 mux/RPC 探针与实际移动反馈对照，方法见[连接稳定性](docs/desktop-remote-20261003.md#连接稳定性与旧调试项)。本轮精确清除遗留强制 DERP 开关后 iPad 恢复直连、探测从 467–1671 ms 降为 3–65 ms；正常停止卡住的 Tailscale 已窄范围恢复，最终状态读回与初始失败收据分开记录。未改 Desktop profile/会话，不把电脑探针成功当作实机长期稳定。具体对话、备份和脚本失败见最新 maintenance。

授权最新变更：用户“还是使用旧的授权方案: 在tailnet内就直接能够访问”，并确认“已退出”。当前 relay 0.2.0 显式 tailnet 模式：固定根地址直接进入，Native cookie 只在上游中继内存使用，本地 Desktop 鉴权不变。读取[当前模式与切换](docs/desktop-remote-20261003.md#当前模式tailnet-直接访问)后再维护认证；使用正常退出、备份、AST 精确改远程行的 mode helper，保留 CLI link 和无关 profile。44 项新实例只读、15 项回归与原生隔离通过，不等于手机/iPad 人类验收。下方二维码记录为历史 owner-browser 模式，不能作为现行步骤。

用户最新授权“接入, 然后把之前失败方案的遗留清理一下”，随后“已退出”，完成原生管理员清理后回复“已清理”。当前仅在官方 Desktop 内新增 manager-owned `plugins/desktop-remote`；接手接入、认证、移动验收或回退时先读 [专用部署](docs/desktop-remote-20261003.md)。正式 38 项只读、真实 HTTPS 隔离 26 项通过；iPad 本轮已由用户确认，手机未验收。RustDesk 规则、原生目录和本轮缓存精确退役，源码在 `retired/rustdesk-trial-20261003`；历史准备不构成再部署授权。具体对话、失败/修复见最新 maintenance。

## 关键约束

手机接入维护触发：用户报告扫码后 DSH authentication required，并确认“已退出”。现用 relay 0.1.1 已修跨站首登 Strict cookie 跳转：先原生认证、再同源过渡文档，不改账户/Host/Origin/RPC/mux 或 cookie 强度；旧插件可恢复备份，五份 profile 哈希不变。真实 HTTPS Chrome 的直接/合成外链登录回归通过，新 QR 已刷新；实际手机与本次重启后的 iPad 待验收。认证仍是账户加浏览器凭据，没有逐设备配对。接手时读专用部署“手机首连与独立验收”和 maintenance 的 Chrome 修复记录，区分合成外链与真实 Lens。

移动最新反馈：先“出现了, 手机还没做”，后“实时显示，已经结束”。iPad 本轮实际输入/同步、实时内容及正常结束由用户确认通过，手机未验收。更新只依据专用部署与 maintenance 的实际反馈，不把 Chromium 成功推断成人类端通过。

- 2026-10-03 正式接入已获上述授权；只访问同一 Desktop Host，非整机远控。新的外部入口、身份范围或后台服务仍需确认，不能凭隔离成功扩大范围。

早期 23 项 loopback 检查仅是接缝证据；正式安装、HTTPS 和实际移动验收按新部署记录分别核对，不复用旧 PID/凭据。

- Desktop 使用官方 `standard` 新会话；不要改写追加式旧会话日志来伪造预设兼容。恢复归档前先停止 Desktop 并备份当前数据。
- 旧 WSL Serve 与看门狗继续退役；新 Serve 只映射 Desktop 随进程运行的 loopback relay。先验精确 authority、原生 cookie、mux 和动态端口；Funnel 关闭。

## 组件分类速查

| 类型 | 目录 | 说明 |
|---|---|---|
| 外部源码 | `vendor/` | submodule：deepseek-harness fork、EAC、awesome 等 |
| 自研插件 | `plugins/` | dsh-memory-panel、dsh-skill-router、dsh-routing-suite |
| 第三方补丁 | `community-plugins/` | dsh-backup、DSH-better-sidebar、git-workflow、undo-fixed、wsl-workspace |
| 技能 | `skills/` | mattpocock skills、math-research-dsh skills（submodule 或 vendored） |
| 配置 | `config/` | Desktop 最小补丁与旧配置快照 |
| 服务 | `services/` | 已随识图/生图/Ollama 退役，暂留空目录 |
| 文档 | `docs/` | 方案、架构、维护手册、ADR |

## 持续修复方法（2026-10-01）

用户要求“继续工作直到完成”。先复现完整检查中的失败，再以固定上游版本恢复缺失源码；保留本地修改，记录每个恢复文件的 SHA-256。自用包记录真实 fork 所有者并保持私有，不冒充官方 npm 发布成员；所有依赖、构建、类型和行为检查仍需执行。阶段证据在 `F:\tools\dsh-retired-20261001\completion-repair`；未完成验收前不发布或安装到真实 Desktop。

## 维护边界

- Harness 子模块锁定已发布的原生 Desktop 适配源码，WSL 不再承担运行服务。本仓旧 `config/`、`plugins/`、`community-plugins/` 是历史快照，不能覆盖真实 Desktop profile；重建按 `scripts/README.md`，发布后分别读回管理仓 ref、gitlink 和方法文件。
- 图形控制台、远程插件和旧管理脚本不再是重建入口；其历史可由 Git 找回，归档数据保留在明确列出的目录。
- `docs/PLAN.md` 和 `docs/architecture.md` 是历史设计记录；当前进度以 `docs/current-deployment.md` 和 `docs/maintenance.md` 为准。

## 对话记录（2026-09-29）

用户要求先更新 DSH 官方最新版、保留插件适配，特别核对本地网络内容隔离插件，再把配置方法同步到 `xsoc1/dsh-selfuse`。候选合并官方 `0.2.0-rc.1` 后，用户被告知完整文档门禁有 19 项失败，明确回复“修完全部门禁再发布”。候选后来通过 `doc-sync` 42/42、构建和隔离 Web 验证；首个临时 profile 仍错误指向现用灵枢记忆目录，启动日志记录 1 项索引对账，随后修复为 `${DSH_HOME}` 路径展开并通过回归测试。同步本仓时发现旧 manifest schema 的 `action` 枚举未收录已有值，补齐并验证。不能把云端候选、隔离测试或本地隐私检查误报为现用服务升级、iPad 端到端验证或绕过服务商策略。

本日后续：完整门禁通过后先发布 fork 分支和本仓 pin，再独立备份、更新现用 profile 的两个外部插件、切换活跃源码链接并重启。现用进程已核对为 `0.2.0-rc.1` 提交，PC 本机登录与 Tailnet HTTPS 登录均为 303→200；iPad 会话及真实模型调用尚未验证。当前 Tailnet 直通模式关闭远程设备配对，启动日志因此提示普通 `/api` 对受信主机开放；不得将它误称为配对保护或公网安全配置。详细步骤、备份与回退边界见 `docs/upgrade-0.2.0-rc.1.md`。

用户随后要求更新最新 DSH，并从 DeepSeek 官网而非 GitHub 调研新发布桌面端，评估并实践有用功能的全量迁移。2026-09-29 将官方 `0.2.0-rc.2` 合入隔离 WSL 工作树，修复自用私有插件构建遗漏，跑通构建、定向测试、隔离 Web 和 43 项文档门禁后备份现役 profile、切换活跃链接并重启；本机与 Tailnet 带令牌页面均 HTTP 200。官方签名的 Windows 桌面端已安装；隔离 Windows home 初始化 Desktop profile 后，随包 CLI 可安装两个外部插件，但实际 GUI、会话和 iPad 迁移均未验证，不可宣称 Web 已退役。控制脚本的旧令牌缓存误报也已修复并复测；详细证据和方法见 `docs/desktop-migration-0.2.0-rc.2.md`。

## 对话记录（2026-09-30）

用户问“能别装到 c, 装到 f 吗”，指前一日安装的官方 Windows Desktop。先核查了官方安装包的签名、原 C 盘安装目录和卸载注册表、无运行中进程、F 盘空间。随后用官方安装包指定 `F:\Apps\DeepSeekHarness`，安装器自动移除 C 盘旧程序；卸载注册表、开始菜单快捷方式和实际启动进程均已指向 F。将此前本项目的 C 盘临时测试 home 移至 F 留存；没有迁移或清除真实 `.dsh`、WSL 用户数据和会话。隔离启动只验证 Desktop 进程及 profile/storages 创建，GUI、插件激活和会话迁移仍待验收。更新 `manifest.json`、当前部署、迁移评估及维护记录以反映实际位置。

用户随后提供桌面端 “DeepSeek Harness is unavailable” 截图，未另附文字要求，按启动故障处理。连续两次真实启动与一次空白 profile 均产生新 Host 崩溃报告，错误为必需 WebServer 监听 `127.0.0.1:19387` 被系统拒绝；Windows 排除端口范围覆盖该端口，普通 Node 监听同端口也失败。官方 profile patch 支持覆盖 `webserver`，隔离测试证实 `port: 0` 可启动，故备份真实 patch 后只修改该行并保留官方 gzip 配置。真实 profile 复测无新崩溃、动态 loopback 端口有监听、窗口存在，用户表示“我看到正常启动了”。上一轮只看进程与文件创建属于不充分验收，已在文档中更正；会话与插件实际运行尚未测试。方法与备份位置见 `docs/desktop-migration-0.2.0-rc.2.md`，重建模板见 `config/desktop/cordis.patch.yml`。

用户再问“一定要保留 web host 才能远程吗”。已区分桌面窗口必需的内部 Web Host 与现有 iPad 使用的 WSL Web：前者不等于可用的远程入口；当前 Tailscale Serve 仍转发到 WSL `3080`，Desktop profile 不含远程 UI 插件，本次端口设为动态 loopback。理论上远程可以迁到另一个经验证的服务，不必永久保留旧 WSL Web，但目前不能关闭它而仍宣称 iPad 可用。上述边界同步进迁移评估和维护记录。

用户本轮要求选择最接近官方原生的模式、排除 `Unknown agent preset: wsl-router-standard` 并清理旧控制台。起初用户强调 iPad 和手机均为远程对象，随后明确改变决定：“放弃远程插件，清除掉”；对旧会话选择“归档旧会话，桌面版从 standard 开始”。工作方法是先查实际 Desktop profile、会话日志、WSL 进程、计划任务与 Serve 映射，再做可恢复归档和精确删除。官方 Desktop 不注册旧 WSL 预设，也不扫描旧 `.agent-presets`；没有改写会话日志。用户正常退出桌面版后，将 Windows 旧会话移到 F 盘，WSL Web profile 移出活动目录；移除两项 DSH 看门狗计划任务和唯一的 Serve 映射，Tailscale 本身未卸载。复查发现 Desktop 将默认值写回 `ptc`，已在停止程序后改为 `standard` 并重启读回；新 Desktop 会话记录 `agentPreset: standard`，Host 在动态 loopback 监听且无新崩溃，模型对话与第三方插件尚未验收。WSL fork 构建、类型检查和文档门禁通过，但卫生门禁 12/18 失败，涉及历史包债务；本轮修改均未提交或发布。

用户随后提供桌面端 JavaScript 错误截图：主进程 `NsisUpdater.checkForUpdates` 处的 `console.info` 报 `write EPIPE`。检查到出错窗口由上一轮短命 PowerShell 启动，父进程已退出。差分复现中，关闭继承的标准输出管道后约 12 秒出现 `Error` 窗口，保持管道可读则窗口正常；经 Windows Shell 启动后，发起启动的 PowerShell 退出仍保持正常窗口，当时误判已修复。复现窗口的正文未自动抓取，不能据此声称验证了每次弹窗的完整异常栈。详见 `docs/maintenance.md`。

用户再次发来相同 `write EPIPE` 截图，并确认是程序运行一段时间后自动弹出。上一轮 Shell 启动只观察了约 20 秒，漏掉默认约 10 分钟一次的更新轮询，不能视为修复。用户正常退出实际桌面程序后，在隔离 `DSH_HOME` 把更新轮询临时缩到 1 秒：关闭标准输出读取端会再次出现 `Error` 窗口；把输出接到持久文件后，启动父进程退出仍完成 82 次检查且无 `EPIPE`。现用 Desktop 以同样文件重定向重新启动，输出在 F 盘受限目录；初次更新检查、窗口和 `standard` 配置已核验。没有改变正式轮询频率或官方安装包；普通开始菜单启动及持续数小时的真实 profile 运行尚未单独验收。

用户要求“再复检验收一轮目前方案”。本轮以只读现场检查、现有会话的完整多帧解码、归档逐文件验证和定向测试验收，没有重启当前程序、改写会话或发布。真实文件重定向实例有 18 次成功更新检查、0 次 `EPIPE`；12:34 Host 退出与系统重启时段重合，不直接认定为独立运行故障。当前 `explorer.exe` 启动实例运行约 185 分钟且无新 Host 报告。活动会话三轮完成但有 4 次工具错误，其中两次 WSL UNC 新建文件报 `ENOTSUP`，不能宣称文件工具全通过。229 份归档解压和 JSON 解析全通过；退役的任务、Serve 映射和活动 WSL Web profile 均未恢复。源码定向测试 175/175、文档门禁 43/43，卫生门禁仍为 6/18，发现远程包路径只剩 `node_modules` 也会触发包结构检查；因此运行链路部分通过，完整迁移/清理和发布验收未通过。详细证据与待办集中在 `docs/maintenance.md` 的本轮验收小节。

用户要求“继续修复”，选择“桌面使用 F 盘本地工作区”，并确认正常退出程序。先复核进程为零，将真实 `workspace.json` 备份到 `F:\tools\dsh-retired-20260930\native-workspace\workspace.before.json`，仅新增原生 `F:\tools` 工作区；旧工作区与会话关联保持不变。官方 `defaultWorkspaceId` 只用于首次初始化，并非普通导航的默认工作区，不能仅设置它便宣称已切换；需另外核验设备本地导航选择。源码中已退役的 `remote-web-ui` 目录只余 `node_modules`，将这一确切残留移到 WSL `dsh-retired-20260930/source-residue/remote-web-ui` 可恢复保存；不删除原会话。门禁修复使用仓库自带 rescope 生成器，不通过扩大忽略项隐藏失败。后续验收结果继续记录在维护手册，不以进程存在代替功能验收。

后续实际验收：签名 Desktop 的新原生 `standard` 会话完成 `write → read → edit → read`，四次结果均成功；安装包内 Win32 文件系统八项测试也通过。关闭临时调试入口后正常重启，测试脚本和文件可恢复归档，旧三个工作区与备份逐项相同。源码移除无断言的空模块，修正 Host 代理策略、相对路由、心跳收窄及改名脚本误改事件名，69 项定向回归通过。发布仍受完整门禁约束，最终数值以本仓维护手册为准；没有新增第三方桌面插件或声称已同步云端。

## 对话记录（2026-10-01）

用户继续要求修复，并批准“归档退役旧包”。先检查候选配置和包依赖，再把五个退役 EAC 集成、market、skill-router 和 wsl-workspace 完整移出 WSL 构建树；195 个受跟踪文件逐个 SHA-256 相同，未提交改动和依赖也随目录保留。task-notify 仍有候选引用，不随 EAC 名称批量退役。工作方法是精确路径验证、可恢复移动、生成锁文件及目录索引、回归和完整门禁复跑，不添加忽略规则。另修正通知包漏打包入口、Git 图误收录中间 JS、undo 回归入口和临时路径；真实 Desktop 配置和会话不变，全部门禁通过前不发布。归档位置、检查结果和剩余失败见 `docs/maintenance.md` 本日小节。

用户随后再说“继续修复”。本轮用真实 Agent/Session/审批和 Loader 重新装配代替不完整测试对象，修复 SSH 请求校验与中英文文字、任务板封闭动作构造。回归 24/24；卫生门禁 12/18、lint 仍未全绿。发现 SSH/任务板缺失构建配置、仍依赖旧 Client API：源码通过不等于冻结 bundle 或 Desktop 已适配。方法、负例和最终门禁见 `docs/maintenance.md` 后续小节，真实运行与数据保持不变，发布继续被阻止。

用户在插件弃用评估后说“按你的方案办”。本轮按先前首选项归档 settings/community/skins/all，46 个受跟踪文件逐个哈希一致；候选配置独立加载 Git 图和皮肤中心，将必要 DOM 属性提取为生命周期受控的皮肤适配。生成器明确移除四个旧依赖但保留其他 CLI 插件，全部回归使用临时 home；memory-panel、git-workflow 和条件项未删除。任务板只解除旧设置页依赖，剩余旧 Client API 与冻结产物仍是待办。同步双语包说明、目录与本仓维护记录；没有改动真实 Desktop、数据或发布状态。执行和回退方法见 `docs/plugin-retirement-20261001.md`。

用户随后明确选择“归档三个条件项，优先原生功能”。SSH、任务板、MinerU 与闲置 ClientRuntime/ApiProxy 完整归档；764 个文件/链接记录及 7359945 字节逐项一致，未动会话或插件用户数据。方法是先清除候选引用、验证字面路径，记录全目录哈希和链接目标后移动并复核；生成器禁止恢复九项退役依赖，保留无关原生 CLI 插件。皮肤中心从固定 dsh-web v0.2.7 恢复真实源码，保留包改接原生 ConfigForms、会话与显式 Host/Client 工程；不以假 TS 入口、空安装器或整包排除通过检查。通知标题生命周期问题用真实 Session 回归修复。维护记录区分已通过回归、未通过完整门禁和未验收 Desktop 激活；未提交、推送或修改子模块 pin。

后续将 Git 工作流的原有纯解析逻辑与 Host 实现迁为严格 TS 可重建工程，保留五种工具的结构化结果，修复 `git_log` 参数合并和 `git_branch` 输出格式。实际 bundle 经原生 tools、subprocess、sandbox-policy/Bash 在临时 Git 仓库中验收；只读拒绝、路径拒绝、引用转义和行卸载分别验证。未提交真实项目、未联络模型提供方，也不把这类测试冒充已安装 Desktop 验收。完整检查结果仍以维护记录为准。

用户继续要求“继续维护”。先修正仍阻止构建的 backup：保留真实功能并迁为严格 TS、原生 Config/工具 schema、显式 Host/Client 工程和可重建 bundle；旧源码与产物先备份。方法是先保存失败证据，再用隔离 home、实际 Loader/工具和临时 Git 远端验证备份、恢复、卸载重载及换仓库同步，不在真实 Desktop 或会话上试验。补齐六个缺失皮肤样式，CSS 声明逐项与 Lightning CSS 导出核验；备份 Client 使用正常压缩构建，不手改第三方模板字符串。最终组合回归 33/33、文档 43/43，但卫生门禁 15/18、全仓 lint 168 错误，memory-panel 等旧工程仍阻止发布。两份 Desktop profile 文件哈希不变，lockfile 仍不存在。详细证据与剩余限制见维护记录；没有提交、推送、更新子模块 pin 或授权绕过服务商安全机制。

用户随后输入“xiu”，按“继续修复”接手 memory-panel 的剩余工程。方法是先保存原文件与构建/加载失败，迁移真实 Host/Client TS、原生 RPC 和设置渲染，使用临时 Markdown 根目录和 CLI profile 验证，不把注册成功当作 UI 验收。旧 smoke 脚本与归档 SHA-256 一致后移除，原生 UI 测试实际保存、刷新、切换中文、拒绝 HTML 执行并卸载；进一步使用 Host Gateway 验证调用与坏参数。同步双语说明、生成目录和维护记录，最终数值见 docs/maintenance.md。本轮未修改真实 Desktop profile、会话或云端 pin；门禁不全绿不发布。

用户随后要求“完全全部任务”（按完成全部任务处理），批准“归档 undo，保留 backup 和原生恢复”，以及“允许明确列为共享 peer 导出”。本轮将 undo 全目录移动到 checkout 外并逐项复核，保留快照数据；Soul 改为真实原生 Host TS、配置、监听和持久化会话回放，浏览器输出用编译器保持模板字符串语义。`defineTool` 按人工批准加入必须共享官方 tools 实例的分类，不列安全豁免。继续修全量单元测试、文档、卫生及重复门禁，固定源码状态再复跑；实际 Desktop/data 和远程退役不改。具体过程与当前未完项见 docs/maintenance.md，检查不全绿不发布。

本轮后续：退役移动端缓存/eval 加载及隐式重试恢复官方 rc.2 方式，原修改先归档；跨平台测试依据明确的执行世界装配，flock 只探测当前 libc 的实际 addon。皮肤/Git 图共用挂载保护，新增导出分类等待人工确认。全量单元测试以 4 个 worker 通过，保持原断言、超时和跳过项；源码构建与全仓 lint 通过。不要并行重建 CLI 与读取其产物的进程测试。真实桌面 patch 在程序运行中变化，作者未确认，保留现状，不覆盖成旧保护哈希；维护记录区分已知变化和本轮无写入。

安装版后续验收发现 Soul 默认配置条目没有 config，但 schema 将整个对象设为必填。先补失败回归，再改为显式空对象默认值，严格构建与五项回归通过。使用官方随包 CLI 和实际 ASAR Host，在 F 盘临时 profile 激活九个保留条目；记忆文件操作、路径拒绝和 Windows tar 校验/恢复预览通过。linked 包必须有可解析的本地依赖，不能把 WSL node_modules 带入 Windows。保持编译时 const enum 与运行时导出之别，测试环境采用 Desktop 实际提供的客户端版本变量。完整构建产物回放通过；客户端分层补查的 82 项错误仍阻止发布，不省略检查，不宣称正式 GUI/模型通过。

2026-10-02 后续按“完成所有修复”继续：用户对 defineTool 的人工批准不覆盖 mountOnce。按实际职责下沉共享服务、把 Office/PDF 组合放回入口，分层检查改为语法树并补齐正反例；82 项分层错误归零，类型与 9518 项 GUI 单元通过。完整链路发现嵌套 npm 接收 pnpm 专用参数，改为包目录内通用 run，并校验私有 peer 的顺序/循环；实际 npm 重建 10 包通过。保留失败日志，不更改门禁或归档 notes 来掩盖失败。字典所有权的新门禁问题仍需修正，完整回放/单元正在复跑；细节与最终数值只写维护记录。正式 Desktop 仍运行，不写入其 profile，不将旧日志当作当前实例证据，不在门禁未齐时发布。

随后全量单元 39211 项通过；再将共享字典合入原生 locale 所有者，逐项证明 6 字典/242 键值相同。本地化与分层检查通过，继续复跑受影响 GUI/类型/文档；不把更早的全量结果标为最终冻结状态。源码和管理仓均维护具体对话与方法，最终证据集中在 maintenance.md。

用户随后单独批准“允许列为共享 peer 导出”，对象是 `@dsh-selfuse/plugin-mount#mountOnce`。先保留两个失败回归，再明确共享 peer 分类并将皮肤/Git 图消费者改为 peer 加 dev，不列 duplicate-safe。完整 Web 回放失败须分清源码与环境：先测实际字体/尺寸，再以隔离缓存作对照；不因旧 Chromium 字体缓存漏掉新字体而改界面或断言。正式 Desktop 仍不写入，固定产物后才重跑完整验收。

分类后官方检查器继续指出四份 manifest 的 38 项问题，按既有修复器改共享 peer/dev 和 Client/runtime 声明，回归 48/48；不新增豁免。用户再回复“已退出”，进程为 0，配置哈希保持新保护状态。CDP 与隔离缓存证实三个布局失败源于旧 Chromium 字体缓存，原断言全部通过；旧缓存不删，完整验收和安装仍分阶段记录。

收到正常退出确认后，先串行执行原生 `check:all`，避免重建产物与读取产物的测试交叉；全量单元这一阶段通过，其余门禁仍在继续。本仓新增官方 Desktop CLI 安装器和八项测试，默认只预检，执行安装须显式 `--apply`。工作方法是独立 F 盘版本目录、受限 ACL、配置逐项备份和哈希核验、仅复制产物不带 WSL 依赖；保留用户 YAML 正文与禁用选择，不恢复退役功能。实际 Electron 进程必须等待真实退出码，不能把 PowerShell GUI 调用的短时返回当成功。预检通过，不代表已经安装，正式状态继续以维护记录为准。

后续总门禁 71/71，Windows 隔离 Host 九个条目激活、Git/记忆/备份操作和卸载通过。新增安装器的实装负例发现开放 stdin 导致 pnpm 完成后仍不退出；补真实 EOF 与取消进程树回收，十项测试和隔离实装通过，正式 profile 尚未写入。完整浏览器首轮仅 remote-welcome 的准备登录失败：Node 不解析 Chromium 自行处理的 remote.localhost。修正测试准备请求走已分配 loopback，浏览器仍访问原 remote authority，原权限/欢迎语断言不变并补地址断言。原失败保留，定向通过后重跑完整浏览器；不跳过、不恢复远程部署、不提前发布。

最终浏览器 lane 与全仓 lint 通过后，用户退出的正式 Desktop 经官方 CLI 安装十个保留包，产物/配置哈希备份在 `F:\Apps\DeepSeekHarnessPlugins\selfuse-20261002-rc2-final`；原 patch 正文逐项保留，仅补缺少行，模型/权限/预设和会话未改。以持久文件重定向启动官方程序，新实例初次更新检查无 EPIPE 或插件启动错误；图形面板/模型不是仅看进程就通过，已请求用户界面验收。源码 32 份明确编译残留先核对 source map 再移动、逐个哈希一致，四项真实 Loader 组合复检通过；不把生成输出放进发布提交。完整同步与远端读回未做完，方法和当前结果继续见维护记录。

用户实际反馈“能打开，但我没在设置里看见什么记忆备份皮肤面板”。正式只读 inventory 发现五个条目无 fiber，客户端只含布局适配；不能把之前隔离 Host 的成功沿用为正式验收。用安装器的真实外置目录复现，保留 ERR_MODULE_NOT_FOUND，再按官方 linked-package resolver 的祖先 peer 规则连接运行依赖；九个 Host 和五个 Client 清单通过。正式运行中不写配置，已请求正常退出；补安装器回归、图形验收前不发布，细节见维护记录。

后续安装器 13 项回归和只读验收正反例通过；独立浏览器实际加载原生 ASAR 组合，三个面板渲染与记忆保存/Host 读回通过。测试代码的引导弹窗、原生“内置插件”标签和响应字段定位错误先保留失败再按声明修正，不改产品或跳过检查。文档预算通过凝练阶段记录修复，不抬上限。真实 Desktop 仍运行，正式补连接和云端发布尚未进行；当前文档/manifest 已改正“未安装”的过期说法。

最后 18 项部署回归、21 项文档快速检查、manifest schema 和差异空白检查通过。准备的正式修复脚本在仍运行时真实拒绝，备份目录未创建，配置未写；正常退出后才允许补连接。正式验收和云端同步不是完成状态。

等待正常退出期间，实际五个 Desktop 进程仍在，不补连接或强制关闭。对两仓存续改动及未忽略新文件做只读发布候选扫描，源码 464 文件、管理仓 17 文件；没有私有日志/会话目录或链接/二进制跳过，五项签名命中经复核为测试、翻译和运行时变量模板，不输出值，也不宣称完整安全保证。先修正误用 WSL Git 读取 Windows worktree 的扫描命令，再按各自原生 Git 完成；报告留在 checkout 外。同步 manifest、PLAN 和历史精简文档中的旧状态，补充设置 → 内置插件 → 备份/记忆及设置 → 皮肤中心的验收路径。具体方法和未完成项见维护记录；未提交或发布，正式修复仍等正常退出。

之后实际 Desktop 进程为零，受保护脚本完成正式外置依赖连接，五份 profile 文件哈希不变。新实例的只读验收仍失败：memory-panel 缺少 DSH_HOME 时无法激活，新增真实 Loader 回归为 1 failed/3 passed，产品修复尚未完成。用户问“GitHub 这个插件的上游仓库能不能直接装下来”，暂按灵枢理解；只读核对 GitHub 固定提交与 npm 0.7.0，区分原生安装渠道、自动记忆与人工面板、已发布包与未验收桌面运行。上游没有原代理配置整段隔离补丁，未替换正式插件或发布；具体证据见维护记录。

随后按“完成所有修复”修复现用 memory-panel，而非替换成灵枢：使用官方启动器提供的 dshHomePath，保留显式 root 和环境选择优先级，缺少隔离路径仍拒绝。真实 Loader、原生 CLI 和面板 11 项回归通过；签名 Windows 隔离 Host 九项激活、五个 Client、三个实际面板与记忆保存读回通过，不设置 DSH_HOME/DSH_MEMORY_ROOT。测试临时 USERPROFILE 不传给浏览器，保留首轮浏览器失败和差分复测证据。当前正式程序仍运行，已请求正常退出后更新插件；复查相关门禁后才允许正式验收和云端发布，记录见维护手册。

2026-10-03 用户回复“已退出”，实际进程为零后更新精确的 Windows 已验收记忆产物，旧包归档、五份 profile 哈希不变。两次启动因本轮 null setter 留下空 Node 模式变量而退出 0；差分探针证实环境项仍在，改为真正移除后新实例九个 Host/五个 Client 通过。用户先称“有皮肤中心，没有备份和记忆”，说明页内标签位置后回复“有了”；按该实际反馈记录，不冒充正式保存/模型验收。未执行的额外浏览器探针已移除；当前检查与云端同步仍分别记录在维护手册。

随后发布前暂存检查发现新增文件的末尾空行和播放器模板中的行尾空格；修正格式并证明嵌入页面每字节不变，快速文档及 43 项完整文档通过。正常源码提交/push 钩子运行，464 份候选哈希未被修复器改变；源码 42d47032d3d 已发布并从远端 fetch 读回相同提交。GitHub API 此时 workflow_count 为零、status_count 为零，未报告 CI，不称通过。管理仓通过原生 Windows Git 精确更新 gitlink 和方法文件，普通快进发布后另核远端，保留私有归档和运行数据。

## 对话记录（2026-10-03，远程方案调研）

用户原话“想想, 查查, 有没有全新的更合适的远程访问方案”。本轮按 research 技能并行核对一手候选资料，主 agent 查官网、上游固定提交及本机系统版别；仅写研究文档，不安装、改配置、恢复 Serve/看门狗或推送。重新评估远程时读 `docs/remote-access-options-20261003.md`：区别同实例屏幕控制和独立 Web Host，官方 master 的新参数不是现用 rc.2 的验收结果；选择部署路线后再征求所需权限、做移动端真实验收。具体方法与未验证项见 maintenance.md，本轮不改变当前部署。

## 对话记录（2026-10-03，私有远控试行）

用户原话“试行一下首选的这套方案”，回答“先用 iPad”。方法是先核对真实 Tailscale/系统/旧入口，再验证官方固定资产、仅解包 F 盘、原生最小配置和指定设备防火墙；配置、监听和移动操作分别取证。自动执行 RustDesk 被工具策略拒绝后，只继续文件/系统准备，不用替代执行通道规避。程序启动及 iPad 输入、完成、重连需用户操作验收。重建、排错或回退试行时必须先读 `docs/rustdesk-trial-20261003.md`，再只读 Verify；无服务、开机项、旧 Web 或 DSH profile 写入。本轮具体结果与权限阻塞见 maintenance.md。

用户执行 Firewall 报“未能找到路径…RustDesk2.toml 的一部分”。句柄复现证明原配置在 Codex LocalCache\Roaming，逻辑路径/TOML/同源两个 PowerShell 的存在检查被重定向误导，原生就绪结论撤回。按 diagnosing-bugs 建红测、比较实际存储后改为 F 盘暂存、外部原生 PowerShell 初始化、物理路径核验、幂等且不覆盖；31 项双 PowerShell 回归通过，真正用户环境的初始化/规则和移动验收仍待重跑。维护者在 Codex 中只能暂存，不把缓存检查冒充原生；具体步骤见上述试行说明。子进程未报告 package identity 仍可继承重定向，必须保留句柄检查；不修改 Codex 全局隔离策略或 DSH 数据。

用户原生 Firewall 随后报三次“一个或多个地址前缀无效”及读回失败。排错/重试先读 `docs/maintenance.md` 的原生验证记录：只读 SystemDefaults 重放确认 `::/0` 复现 0x80070057，两个 /1 消除该地址错误。脚本已支持精确校验现存规则、禁用本次 Allow 后补齐 Block、失败即止及安全重试，并接受原生空 Package；两种 PowerShell 各 57 项通过，其中原生地址校验与模拟规则修复分开标注。本轮未写活动规则、原生配置或 DSH 数据；现场仍仅一条 AllowDirect、程序未运行。用户须重跑同一原生管理员命令，再验收移动连接；不能把只读校验冒充实际提交成功。
