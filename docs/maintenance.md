# dsh-selfuse 维护手册

> 现役 WSL 配置来源与已锁定候选版本以 [当前部署说明](current-deployment.md) 为准。以下早期 Windows 安装/更新记录保留供追溯，不能直接作为现行操作步骤。

## 维护原则

- 本仓是当前源码引用、管理脚本快照和部署方法的云端索引；运行配置实际在 WSL `~/.dsh`，不是本仓旧 `config/` 的副本。
- 每次变更组件/配置后，同步更新 `manifest.json` 与本文“维护记录”。
- 不提交：密钥、大模型二进制、node_modules、venv、日志。

## 常用操作

### 核对锁定的 Harness submodule

```powershell
git submodule update --init --recursive
git submodule status vendor/deepseek-harness
git -C vendor/deepseek-harness rev-parse HEAD
```

### 历史方法：新增自研插件

> 以下步骤属于旧 Windows profile；当前应修改锁定 Harness 的 `packages/selfuse/` 和 `config/selfuse/`，先验证再单独更新子模块指针。

1. 在 `plugins/<name>/` 放源码（或 submodule）。
2. 在 `manifest.json` 增加一条 `type: plugin`。
3. 如需默认装配，更新 `config/profiles/web/package.json` 与 `cordis.patch.yml`。
4. 在本文“维护记录”追加说明。

### 历史方法：修改 profile 配置

> 以下步骤不适用于现役 WSL profile，不要执行旧 `install.ps1` 的应用动作。

- 直接改 `config/profiles/web/package.json` / `cordis.patch.yml` / `settings.yaml`。
- 运行 `install.ps1 -DryRun` 查看同步动作；确认后执行。
- 当前线上环境未自动跟随，需要安装器同步或手动复制。

## 维护记录

### 2026-09-30 Windows Desktop 默认端口启动故障

- 用户截图显示桌面端 “application could not start”。用每次启动产生的 Host 崩溃报告建立可重复失败信号，独立空白 profile 同样失败；报告为 `listen EACCES 127.0.0.1:19387`。Windows TCP 排除段 `19362–19461` 覆盖官方默认端口，普通 Node 监听同端口也失败。先前仅凭进程和目录创建的安装验收不足，已在 [迁移评估](desktop-migration-0.2.0-rc.2.md)更正。
- 备份真实 Desktop profile patch 后，按官方支持的覆盖方法把 `webserver` 改为 loopback 动态端口 `0`，并保留原 gzip 设置；隔离和真实 profile 均不再产生启动崩溃。真实窗口打开，用户确认正常启动。没有修改 Windows 端口排除、防火墙、Tailscale、WSL Web 或第三方插件；本仓新增可重建模板 `config/desktop/cordis.patch.yml`，只能合并，不能覆盖用户现有 patch。
- 用户进一步问是否要保留 Web Host 才能远程：现有 iPad → Tailscale Serve → WSL Web `3080` 链路仍依赖 WSL 服务；Desktop 的内部 Host 供桌面窗口使用，当前 profile 未装远程 UI 插件、端口为动态 loopback。本次没有迁移 Tailnet 入口，也没有退役 WSL Web。

### 2026-09-30 官方 Windows Desktop 改装 F 盘

- 用户要求“不装到 C，装到 F”。确认原 `0.2.0-rc.2` 官方签名包、旧安装注册表、无运行中的桌面进程与 F 盘空间后，使用原安装包指定 `F:\Apps\DeepSeekHarness` 安装。安装器自行移除旧 C 盘程序目录；注册表、开始菜单快捷方式与新启动进程均指向 F 盘。隔离 F 盘测试 home 已能创建 profile/storages；GUI、插件激活和会话迁移仍未验收。
- 将本项目先前创建的 C 盘临时测试 home 整体移到 `F:\Apps\DeepSeekHarnessPriorSmoke` 保留；没有操作真实用户 `.dsh`、会话或 WSL 服务。安装程序在 F 盘不意味着所有用户配置和更新缓存也在 F 盘。复核细节见 [桌面版迁移评估](desktop-migration-0.2.0-rc.2.md)。

### 2026-09-29 官方 0.2.0-rc.2 与桌面版评估

- 用户要求更新最新 DSH，从 DeepSeek 官网而非 GitHub 调研新发布的桌面端，并实践有用功能的全量迁移。核对官方 Windows 更新源为 `0.2.0-rc.2`；官方源码修订 `639ed015` 合入自用构建提交 `a096be31e89`，修复风险防护插件未随官方 build 生成运行文件的问题；最终含迁移记录的子模块 pin 为 `c9896317dd6`。完整构建、定向测试、临时 profile 插件启动及文档门禁 43/43 通过。
- 本机备份现役 Web profile 五个顶层文件后切换 WSL 活跃链接到 rc.2，进程 cwd、CLI 版本、本机与 Tailnet 带令牌页面 HTTP 200 已核验。外部 prompt optimizer 和 memory 插件仍为锁定版本。未验证真实模型调用、iPad 会话同步或移动端重连情况。
- 官方 Windows 安装包 SHA512 和 Authenticode 检查通过并已安装；随包 CLI 报 rc.2。独立临时 Windows home 已初始化 Desktop profile，经校验的两个外部插件 tarball 用本地路径安装并由 CLI 列出；实际桌面 GUI、插件运行、会话迁移和移动端访问仍未验收。评估结论是保留 WSL Web/Tailnet，桌面端先作为独立 Windows 入口试用；逐项验证后才可考虑全量替换。证据与回退路径见 [桌面版迁移评估](desktop-migration-0.2.0-rc.2.md)。
- 切换后发现 `dsh-control.ps1 start` 把旧令牌缓存在同一进程中，服务可用时仍报超时。已同步修正现役 Windows 脚本和本仓快照，复测 `start` 返回就绪。既有 Tailnet 受信主机 `/api` 不配对警告仍存在，不把私有 Tailnet 等同于设备配对或公网安全。

### 2026-09-29 官方 0.2.0-rc.1 候选与 selfuse 同步

- 将 Harness 子模块候选锁定到 fork 提交 `bcf8c14b1927fb1ee3701e5e3852ff2c3ef25249`；其中包含官方 `4878cdabd87d4041bdaff61d04c966883b9fd07a`、selfuse 兼容修改与文档修复。云端 pin 不等于现役服务切换，切换前后须另做备份和运行验收。
- 更新 `manifest.json`、`README.md`、`docs/current-deployment.md` 与 [升级说明](upgrade-0.2.0-rc.1.md)，分开记录源码、外部插件包、活跃链接及用户配置。第三方提示词优化器锁定上游 `v0.7.6`，灵枢记忆锁定上游 `v0.6.0` 加本地隐私补丁；补丁和包 SHA-256 可在升级说明中复核。
- 按用户“修完全部门禁再发布”的要求修复候选 `doc-sync` 初始 19 项失败；最终文档门禁 42/42、构建、类型检查、内容隔离测试 20/20、profile 安装测试 9/9 通过。隔离 Web 用原样登录链接验证到 303/Cookie/200；未验证现役模型调用或 iPad 端到端。全仓 `pnpm run lint` 仍因既有自用源码遗留规则失败，不能宣称全仓 lint 通过；本次变更的 staged lint 与提交 hook 通过。
- 首次隔离启动时发现灵枢模板的硬编码记忆根指向现用目录，并触发 1 项索引对账；立即停止，修复 `${DSH_HOME}` 路径展开并增加回归测试。只读检查未发现近期记忆正文写入，但索引日志、锁和对账日志有写入，不能称其已回滚。后续隔离启动确认记忆根和辅助根均位于临时 `DSH_HOME`。
- 同步修正 `docs/manifest.schema.json` 中滞后的 `action` 枚举（仅补入现有清单早已使用的 `copied-to-repo`、`vendored-copy`），使完整 `manifest.json` 可通过 JSON Schema 校验。
- 通过全部文档门禁后，fork 升级分支与本仓子模块 pin 已推送；再停止旧 Web、备份现用 profile/settings/会话/记忆（`/home/huangzy/.dsh/maintenance-backups/upgrade-20260929-FvYBA5`，约 171 MiB）、通过原生 CLI 安装提示词优化器 `0.7.6` 和灵枢 `0.6.0-selfuse.1`、将活跃源码链接切到 `bcf8c14b...` 并重启。期间旧进程再次占用 3080，首个新进程因 `EADDRINUSE` 退出；停止旧进程后新版启动成功。
- 运行验收：活跃进程工作目录与锁定源码一致、两个外部包实际版本正确、配置 dump 含内容隔离插件，本机登录 303→200、PC 经 Tailnet HTTPS 登录 303→200、Serve 指向 3080 且状态中未见 Funnel。未验证 iPad 端会话同步或真实模型调用。既有 `requirePairingForLan: false` + trusted-host 会使普通 `/api` 对 Tailnet 受信主机开放，插件报 CRITICAL；该安全取舍须限于私有 Tailnet，不能误写为配对模式。

### 2026-08-19 初始骨架

- 创建 `F:\tools\dsh-local` 骨架：README、AGENTS、PLAN、architecture、maintenance、manifest 草案。
- 复制 `~/.dsh/settings.yaml`、`profiles/web/*`、`agent-presets/router-standard|spec` 为规范副本。
- 复制管理脚本（control/gui/run-dsh-web/watchdog/ensure/make-icon）到 `scripts/`。
- 复制 `image-gen/server.py` 与 `start-image-gen.ps1` 到 `services/image-gen/`。
- 将 profile `package.json` 的绝对 link 改为相对 `link:../../../...`。
- 本地 `git init` 并提交骨架（`85fcf65`），后续 dry-run 修复提交 `f0765b9`。
- `install.ps1 -DryRun` 已验证可运行且无副作用。
- 尚未创建 GitHub 仓库、尚未迁移运行区。

### 2026-08-19 Phase 1a/1b：复制插件源码进 dsh-local

- 将自研插件复制到 `plugins/`：dsh-image-bridge、dsh-memory-panel、dsh-skill-router、dsh-image-vision、dsh-routing-suite。
- 将第三方补丁插件复制到 `community-plugins/`：dsh-backup、DSH-better-sidebar、dsh-plugin-git-workflow、dsh-undo-plugin-fixed、dsh-wsl-workspace。
- 复制方式为 **rsync 排除 .git/node_modules**，保留 lib 构建产物；未移动原目录，线上 dsh 不受影响。
- 移除 dsh-routing-suite 副本中的 `.gitmodules`（改作 vendored 目录）。
- `.gitignore` 不再全局忽略 `lib/`，因为 dsh-memory-panel 等插件的源码/运行产物就在 lib 中；插件包需要直接可 link。
- 更新 `manifest.json` 对应组件状态为 `copied-to-repo`。
- 将技能集合复制到 `skills/`：mattpocock-skills、math-research-dsh（排除 .git），并更新 manifest 类型/路径/状态。
- 尝试在仓库内独立 `pnpm install` 验证 profile；因 npm registry 网络错误（error 23）未完整跑完，已终止。
  - pnpm 已把 `config/profiles/web/pnpm-lock.yaml` 更新为相对 link，并补上 dsh-skill-router / dsh-memory-panel / dsh-wsl-workspace 依赖项；保留该 lockfile 更新。
  - 相对 link 与插件 main 入口已用脚本验证全部存在；完整安装待网络恢复后重试。

### 2026-08-19 Phase 2：GitHub fork / 仓库创建

- 用 GitHub REST API + 凭据管理器 token：
  - fork `deepseek-ai/deepseek-harness` → `xsoc1/deepseek-harness`（public fork）。
  - 创建 `xsoc1/dsh-selfuse`（private，无 auto_init）。
- 推送：
  - `dsh-local` main 已推送到 GitHub（`git push` 用 token URL，随后已把 upstream 改回干净的 `origin`）。
  - `deepseek-harness` 的 `local/image-admission` 已推送到 fork；`master` 因 fork 已含更新的上游提交而拒绝推送（正常，fork 自带 master）。
- 在 dsh-local 登记 submodule（gitlink 方式，未实际 clone）：
  - `vendor/deepseek-harness` → `xsoc1/deepseek-harness` @ `8f4aff2`（local/image-admission）
  - `vendor/awesome-dsh-plugin` → `xsoc1/awesome-dsh-plugin` @ `a225e67`
- 用户确认：Deepseek-Harness-EAC 不使用，不 fork。

### 2026-08-19 网络验证重试结果（未完全通过）

- `pnpm install` 在仓库 profile 内重试：锁文件通过、233 个包已装入本地 store，但 `pdfjs-dist` / `@napi-rs/canvas-win32-x64-msvc` / `tesseract.js-core` 三个 tarball 反复 `error(23)`，最终 `TimeoutError` 退出（curl 单独下载 pdfjs 正常，疑似 pnpm 下载器/代理问题）。
- `git submodule update --init --recursive` 尝试克隆 `vendor/awesome-dsh-plugin` 时长时间无进度，已终止；未产生残留。
- 结论：GitHub REST/API 与 `git ls-remote` 正常；大仓库 clone 与 npm 部分二进制包下载在当前网络/代理下不稳定。后续可在网络恢复或换镜像/代理后重试。
- 补充：改用 `--registry=https://registry.npmmirror.com` 后依赖下载成功，进入 install 脚本阶段；`cpu-features` 按已知情况失败（可选），`sharp`/`tesseract.js` 完成，但 `cloudflared` postinstall 卡在 GitHub 下载最新二进制，已终止。核心依赖已基本可装，仅剩 cloudflared 等 GitHub 下载项受网络影响。

### 2026-08-19 Phase 3：install.ps1 完善 + 隔离 DSH_HOME 演练

- `install.ps1` 新增 `-NoSystem`（跳过环境变量/计划任务/服务/健康检查）与 `-SkipSubmodules`（跳过 submodule clone），便于隔离演练与避免网络卡死。
- 修复技能链接：改为递归查找含 `SKILL.md` 的目录，mattpocock 的分层技能（engineering/productivity/misc/in-progress）现在能正确建 junction。
- 隔离演练（`DSH_HOME=F:\tools\dsh-local\.test-dsh-home`，`-Force -NoSystem -SkipSubmodules`）通过：
  - settings.yaml 复制成功；
  - agent-presets router-standard/router-spec junction 成功；
  - profiles/web junction 成功；
  - 39 个技能 junction 成功（35 mattpocock + 4 math-research）。
- `.gitignore` 增加 `.test-dsh-home/`，演练后已清理临时目录。

### 2026-08-19 Phase 3b：install.ps1 系统级能力实现（DryRun 验证）

- 环境变量：实现 `DSH_ROOT` / `OLLAMA_MODELS` / `HF_HOME` 写入 User 作用域（`-NoSystem` 跳过）。
- 计划任务：实现用 `schtasks.exe` 注册 `dsh-watchdog`（ONLOGON）与 `dsh-watchdog-ensure`（每 5 分钟）。
- 服务启动：实现 Ollama（11810）与 image-gen（17821）的检测/启动逻辑（未找到时告警）。
- 健康检查：实现 `Invoke-WebRequest` 探测 3080 / 11810 / 17821。
- Bootstrap：缺失 git/node/pnpm 时打印 winget/corepack 安装命令（真正执行仍为 TODO，避免未测试就在真实机器安装）。
- 验证：PowerShell Parser 0 错误；`-DryRun -NoSystem` 与 `-DryRun` 均正常；隔离演练仍通过。

### 2026-08-19 Phase 4 预检（未切换）

- 已备份 `~/.dsh`：`C:/Users/HuangZY/Desktop/dsh-backups/dsh-20260819-213751821.tar.gz`。
- 线上健康基线：dsh web 200、Ollama 200、image-gen 200、watchdog heartbeat 新鲜。
- 完整 `install.ps1 -DryRun` 预览已执行，动作清单见 `docs/phase4-precheck.md`。
- 发现硬阻塞：repo profile 的 `node_modules` 未完整安装，直接 junction 会破坏线上 dsh；submodule 也未实际 clone。
- 结论：暂不切换；建议先完成 repo profile 依赖安装，或采用“只同步配置不 junction”的低风险方案。
- 后续：用 `pnpm install --registry=https://registry.npmmirror.com --ignore-scripts` 已成功完成 repo profile 安装（233 包，6.6s）。`node_modules` 现为 253MB，相对 link 插件均正确链接。
  - 注意：`--ignore-scripts` 跳过了 cloudflared 等 postinstall，因此 `cloudflared` 二进制可能缺失；remote-web-ui 公网隧道若需要，需后续单独补装。
- 2026-08-19 已执行“只切文件不重启”：
  - 再次备份 `~/.dsh`：`C:/Users/HuangZY/Desktop/dsh-backups/dsh-20260819-215715900.tar.gz`。
  - 原 `~/.dsh/profiles/web` 改名为 `web.bak-20260819-215736`，新建 junction 指向 `F:\tools\dsh-local\config\profiles\web`。
  - 当前运行中的 dsh 仍用旧已加载模块，dsh web 仍 200；**重启后才会真正加载 repo profile**。

### 2026-08-19 junction 相对链接故障（线上回滚 + 链接加固）

- 现象：切换 junction 后重启 dsh，web.log 报 `cannot resolve profile bundle "@dsh-external/dsh-super-injector"`，3080 无法访问。
- 根因：repo profile 的本地插件 link 为相对路径（如 `..\..\..\..\..\plugins\...`）。在物理路径下能解析，但通过 `~/.dsh/profiles/web` junction 访问时，相对路径按 junction 可见路径解析到不存在的 `C:\Users\HuangZY\plugins\...` / `C:\Users\HuangZY\community-plugins\...`。
- 线上修复：停 watchdog；坏 junction 改名为 `~/.dsh/profiles/web.junction-broken-20260819-221500`；恢复 `web.bak-20260819-215736` 为真实 `profiles\web`；`dsh-control.ps1 start` 后 HTTP 200，watchdog 记录 server ready after 68.6 s；Ollama/image-gen 未动。
- 仓库加固：`config/profiles/web/package.json` 的本地依赖改为绝对 `link:F:/tools/dsh-local/...`；`node_modules` 内 9 个本地插件链接改为绝对 junction（旧相对链接已清理）；临时 junction 解析测试通过后已清理。
- 经验：pnpm v11 会把绝对 `link:` 在 `pnpm-lock.yaml` 的 `version` 字段归一化为相对路径；重跑 `pnpm install` 可能再次生成相对符号链接。任何 profile 切换前，必须用临时 junction 做一次 bundle 解析测试，不能只看物理路径下的 `node_modules`。

### 2026-08-20 watchdog-ensure 权限修复

- 现象：`dsh-watchdog.log` 在 00:01/00:06 出现 `ensure: watchdog missing or heartbeat stale, relaunching` + `not elevated; relaunching with administrator privileges`。
- 结论：dsh 主进程实际仍为管理员（token 探测 elevated=1）；问题出在 `dsh-watchdog-ensure` 计划任务本身。
- 根因：`install.ps1` 注册 ensure 任务时漏了 `/RL HIGHEST`，任务每 5 分钟以普通权限启动 watchdog，再由 watchdog 用 `-Verb RunAs` 二次提权；无 UAC 交互会话下该链路不可靠。
- 修复：`install.ps1` 的 ensure 注册补 `/RL HIGHEST`；用 `schtasks /Create /TN dsh-watchdog-ensure /SC MINUTE /MO 5 /RL HIGHEST /F` 更新现有任务，XML 已确认 `RunLevel=HighestAvailable`。

### 2026-08-20 WSL 自动拉起功能

- `scripts/run-dsh-web.ps1` 与 `scripts/dsh-watchdog.ps1` 同步 deepseek-harness 版本，新增 WSL 自动拉起：
  - 启动阶段：隐藏启动 `wsl.exe -d Ubuntu -e sleep infinity` 作为 Windows 侧 keepalive（已有则跳过），再轮询 30 秒等网关 IP。
  - watchdog 兜底：每 60 秒检查网关，缺失时重新启动 keepalive。
- 试过 `-e true` 和 `nohup sleep infinity &`，都不能让 WSL 稳定保持 Running；Windows 侧常驻 `wsl.exe -e sleep infinity` 实测有效。
- 验证：WSL Stopped → Running 约 2-3 秒，网关 172.22.112.1；dsh 重启后 web.log 有 `wsl auto-start` 记录，HTTP 200；四个脚本 Parser 0 错误。

### 2026-08-19 修复 dsh 卡顿：终止 runaway lake build 会话

- 现象：dsh 极卡，日志/进程显示多个 `lake build` 子进程反复 clone/fetch mathlib4。
- 定位：通过 staging 工具访问 `ctx.get('sessions').list()` / `ctx.get('agents')`，发现 `session-35623230-9cbd-4218-83b5-08bcc4171b37`（Riemann Conjecture 工作区）事件 61.9 万、状态 running，日志含 1008 次 `lake build`。
- 处理：调用 agent `cancel()` 将该会话置为 idle；临时禁用 `lake.exe` 防止重生成，随后恢复 `lake.exe`；确认无 `lake/git` 子进程残留。
- 附带：`settings.yaml` 增加 `dsh-better-sidebar.bottomPanelAutoTerminal: false`，减少 node-pty `AttachConsole failed` 错误。
- 结果：node CPU 从 ~5s/8s 降到 ~1.9s/8s，web 200；runaway 会话已 idle。
- `install.ps1` 新增 `-ProfileMode Copy|Junction`，默认 `Copy`（只同步 `cordis.patch.yml` / `pnpm-workspace.yaml` / `settings.yaml`，不覆盖 package.json/lock），避免再次因 junction 相对链接问题破坏线上。

### 2026-08-19 执行 Phase 4 系统级动作（install.ps1 -Force -SkipSubmodules -ProfileMode Copy）

- 备份：`C:/Users/HuangZY/Desktop/dsh-backups/dsh-20260819-235620355.tar.gz`
- 执行结果：
  - settings.yaml 同步（含 `bottomPanelAutoTerminal: false`）。
  - agent-presets router-standard/router-spec 改为 junction 指向 `dsh-local/config/agent-presets/*`（原目录已备份）。
  - web profile Copy 模式：仅同步 `cordis.patch.yml` / `pnpm-workspace.yaml`，未覆盖 package.json/lock。
  - 环境变量：`DSH_ROOT` 曾被 `-Force` 误设为 `F:\tools\dsh-local\vendor\deepseek-harness`（不存在），已立即恢复为 `F:\tools\deepseek-harness`；`OLLAMA_MODELS`/`HF_HOME` 保持本机实际路径。
  - 计划任务已指向 `F:\tools\dsh-local\scripts\dsh-watchdog.ps1` / `ensure-dsh-watchdog.ps1`；手动执行 ensure 退出 0。
  - Ollama/image-gen 已在运行，跳过重复启动。
- 加固：`install.ps1` 增加服务重复启动检测；`DSH_ROOT` 若 vendor 子模块不存在则回退到 `F:\tools\deepseek-harness`。

### 2026-08-20 agent-preset Junction 导致 wsl-router-standard 缺失修复

- 现象：每次 dsh 重启，恢复旧 WSL 会话时报 `agent-presets: preset "wsl-router-standard" not found`，可用列表只剩 `router-standard-v011-bak` / `wsl-router-standard-v011-bak`，真正的 router-standard/router-spec 消失。
- 根因：`install.ps1` 在 Phase 4 把 `~/.dsh/.agent-presets/router-standard` 与 `router-spec` 建成 Junction（指向 `F:\tools\dsh-local\config\agent-presets\*`）。dsh 的 agent-preset 扫描（`packages/preset/agent-presets/src/discovery.ts`）用 `Dirent.isDirectory()` 过滤，Windows Junction 的 `Dirent.isDirectory()` 返回 false，preset 不进 roster；dsh-wsl-workspace 的 `materializeVariants` 只对 roster 可见 preset 生成 `wsl-<id>`，所以 `wsl-router-standard`/`wsl-router-spec` 永不生成，旧 WSL 会话恢复失败。残留的 `router-standard-v011-bak` 因目录名匹配 `PRESET_ID` 反而出现在可用列表。
- 修复：
  - 删除两个 Junction（仅删除链接，目标树未动），将 `F:\tools\dsh-local\config\agent-presets\router-standard` / `router-spec` 真实复制到 `~/.dsh\.agent-presets\`；Node 实测 `isDirectory=true`、`isSymbolicLink=false`。
  - 旧残留 `router-standard-v011-bak`、`wsl-router-standard-v011-bak`、`.bak-20260819-*` 移至 `F:\tools\dsh-local\backups\agent-presets\2026-08-20\`，不再被扫描为 preset。
  - `install.ps1` 的 agent-presets 同步改为真实复制：遇到已有 Junction 先 `[IO.Directory]::Delete()` 删除链接再 Copy-Item，不再 `New-Item -ItemType Junction`，防止下次 install 复发。
- 验证：`dsh-control.ps1 restart` 成功，HTTP 200；重启后 `.agent-presets` 自动生成 `wsl-router-standard`/`wsl-router-spec` 真实目录且含 `agent.cordis.yml`/`preset.yml`；`dsh-web.log`/`dsh-watchdog.log` 无 `WSL preset-variant generation failed`；`install.ps1` Parser 0 错误。
- 经验：agent-presets 不能使用 Junction/符号链接，必须真实目录；`Dirent.isDirectory()` 对 Windows Junction 为 false。

### 2026-08-20 全面弃用 Junction：skills 改为真实目录

- 用户要求全面弃用 junction。
- 已将 `~/.dsh/skills` 下 39 个技能 junction 全部转换为真实目录（复制目标内容 → 删除 junction → 移入真实目录），验证 remaining links=0、total skills=39。
- `install.ps1`：
  - `-ProfileMode` 仅允许 `Copy`，移除 Junction 分支。
  - 技能同步从 `New-Item -ItemType Junction` 改为 `Copy-Item -Recurse`，遇到旧链接先删链接再复制。
- 文档同步：`AGENTS.md`、`README.md`、`PLAN.md`、`troubleshooting.md` 均注明全面弃用 junction。

### 2026-08-20 隔离全新安装演练通过 + package.json BOM 修复

- 在临时 `DSH_HOME` 执行完整 `install.ps1 -Force -NoSystem -SkipSubmodules -ProfileMode Copy`（含 pnpm install）：
  - 生成 `package.json`（repo-root 绝对 link）成功；
  - `pnpm install` 完成（2m53s，ssh2 可选 crypto 构建失败但非阻塞）；
  - agent-presets 真实复制、39 个技能真实复制、node_modules 正常、顶层无 junction。
- 发现并修复：`Set-Content -Encoding UTF8` 会给生成的 `package.json` 加 BOM，pnpm 报 `Invalid package.json`；改为 `UTF8Encoding($false)` 无 BOM 写入后通过。
- 推送：`211c50a`（含 `e6ea742` gitignore）。

### 2026-08-20 node-pty AttachConsole 本地补丁

- 检查 npm：node-pty 最新版本仍为 `1.1.0`，无法通过升级解决。
- 本地 patch `node-pty@1.1.0` 的 `conpty_console_list_agent`（src + lib）：
  - `AttachConsole` 失败时返回空列表而不是抛错，避免 dsh-web.log 刷 `AttachConsole failed`。
- 新增幂等补丁脚本：`scripts/patch-node-pty.ps1`。
- 验证：补丁后 60 秒内日志 `AttachConsole failed` 计数未增加（42 → 42）。

### 2026-08-20 image-gen 服务修复（离线加载本地快照）

- 现象：image-gen 服务无法启动，`from_pretrained` 因网络/Hub 不可达失败；缓存快照被判定 incomplete（缺 README/LICENSE 等非关键文件）。
- 修复：
  - `server.py` 增加 `HF_HUB_OFFLINE=1`，并直接解析本地 snapshot 目录传给 `from_pretrained(local_files_only=True)`，绕过 snapshot 完整性检查。
  - `start-image-gen.ps1` 恢复 UTF-8 BOM，避免 Windows PowerShell 解析失败。
- 验证：`/health` 返回 200，`model` 指向本地 snapshot，`device=cuda:0`。

### 2026-08-21 上游 dsh 更新到 0.1.1-rc.1 并适配

- `deepseek-harness` master 已 fast-forward 到上游 `528c682e06`（0.1.1-rc.1）。
- 本地维护分支 `local/image-admission` 已 rebase 到新 master：
  - adapter 补丁解决冲突后保留（image admission）。
  - 新增 spawn `windowsHide` 补丁（`packages/subprocess/subprocess-local/src/spawn.ts` + lib）。
- 补丁文件已入库：`patches/deepseek-harness/`（spawn-windows-hide.patch + README）。
- `manifest.json` 已记录上游版本/commit。
- 正在重新构建 host lib（`npm run build:lib:host`）以同步 lib 产物。

### 2026-08-21 上游更新 lib 构建成功

- `pnpm install` 在 deepseek-harness 完成（仅 14 个包增量）。
- `npm run build:lib:host` 成功（修复本地 spawn-windows.spec.ts 的 vitest mock 类型后通过）。
- 构建后验证：
  - `dsh --version` → `0.1.1-rc.1`
  - `packages/llm/llm-deepseek/lib/index.js` 含 `inputModalities: ["text","image"]`
  - `packages/subprocess/subprocess-local/lib/index.js` 含 `windowsHide: true`
- fork `xsoc1/deepseek-harness` 已更新：master `528c682e06`，local/image-admission `a436d48b41`。
- dsh-selfuse 本地提交 `d082ebe`（推送因网络暂未完成，待重试）。

### 2026-08-21 dsh 0.1.1-rc.1 崩溃抢救 + 共享依赖根 + Ollama 重建

- dsh 0.1.1-rc.1 更新后崩溃，抢救恢复：
  - client bundle 缺失（`MissingClientBundleError`）：`pnpm run build:lib:client` + `pnpm run build:web` 成功。
  - out-of-tree 插件依赖解析失败（`Cannot find package`）：新增共享依赖根 `F:\tools\dsh-local\package.json` 与 `F:\tools\community-plugins\package.json`，含 14 个 `@deepseek-ai/*` link 依赖 + `schemastery 3.18.0`；两个根 `pnpm install` 成功。
  - 删除抢救期临时 junction：dsh-image-bridge / dsh-vision / dsh-wsl-workspace / DSH-better-sidebar 下的 `node_modules\@deepseek-ai` 均已清理；Node `createRequire` 对全部插件解析通过。
- `scripts/run-dsh-web.ps1` 增加 client/web 构建产物 preflight，缺失时自动构建。
- 新增 `services/ollama/setup-ollama.ps1`：下载/解压便携版、设置 `OLLAMA_HOST=127.0.0.1:11810` + `OLLAMA_MODELS=F:\tools\ollama\models`、启动 serve、拉 `qwen3-vl:4b`、验证 API。
- 新增 `scripts/repair-dsh.ps1`：一键自检 client 构建、共享依赖、Ollama。
- `scripts/dsh-watchdog.ps1` 与 `deepseek-harness\dsh-watchdog.ps1` 同步新增 Ollama 自愈：每 30 秒检查 11810，未开且便携版存在时自动后台启动 serve。
- `F:\tools\ollama\` 此前整个丢失，已重下 `ollama-windows-amd64.zip` v0.32.9 并解压；`qwen3-vl:4b` 正在重新拉取。
- 验证：dsh web HTTP 200，watchdog 重启后 `server already alive`，Ollama 11810 `/api/tags` 含 `qwen3-vl:4b`，chat 推理实测可加载；实测杀掉 Ollama 后约 30 秒 watchdog 自动拉起并恢复 API；8 个 PowerShell 脚本 Parser 0 错误。
- 待办：`F:\tools\image-gen\` 目录也缺失，生图服务 17821 待用户确认是否重建。

### 2026-08-21 dsh-web-ui-all 0.2.7 升级（settings.plugin.item keyed slot 报错修复）

- 现象：dsh 升级到 0.1.1-rc.1 后浏览器报 `Failed to load plugins @linxin666/dsh-client-ui-web-ui-settings ... settings.plugin.item requires options.key`。
- 根因：官方 `settings.plugin.item` 变为 keyed slot（要求 `options.key`）；`dsh-web-ui-all@0.1.17` 的 settings 插件仍注册旧 slot 且不带 key，加载即抛错。
- 修复：`@linxin666/dsh-web-ui-all` 0.1.17 → 0.2.7（上游已改为 `settings.section` + `web-ui.plugin.item`）；`~/.dsh/profiles/web` 与 `F:\tools\dsh-local\config\profiles\web` 的 package.json 同步升级，`cordis.patch.yml` 禁用项改为新聚合包 id（`web-ui-pet` / `web-ui-describe-image` / `web-ui-dsh-aionui-panel` / `web-ui-better-sidebar`），保留本地 better-sidebar 0.12.2。
- `pnpm-workspace.yaml` 将 `node-pty` allowBuilds 置为 true，pnpm install 成功且 prebuild 就位。
- 验证：`dsh-control.ps1 restart` 后 web HTTP 200、watchdog/WSL/Ollama 正常；headless Chrome 抓控制台无插件加载错误（仅 iframe sandbox warning 与 better-sidebar 无工作区时的既有 `/sidebar/api/fs.tree` 400）；临时文件与测试 Chrome 进程已清理。

### 2026-08-21 退役识图/生图/Ollama 本地链路

- 用户确认原生多模态已可用，删除本地识图/生图/Ollama 链路：
  - 删除运行区插件 `dsh-vision`、`dsh-image-bridge`、`dsh-image-vision`（profile package.json 依赖、cordis.patch.yml insert、node_modules junction 均已清除）。
  - 删除 `F:\tools\ollama`、`F:\tools\image-gen`、`F:\tools\dsh-image-bridge`、`F:\tools\dsh-image-vision`、`~/.dsh/vision-bridge`、`~/.dsh/image-gen` 及 User 环境变量 `OLLAMA_MODELS`。
  - 回退 `settings.yaml` 的 opencode-go `defaultInput`/`modelOverrides`，并回退 `llm-deepseek` adapter/lib 的 `inputModalities` 为纯文本（`deepseek-v4-flash-vision-exp` 原生多模态模型保留）。
  - 图形控制台（运行区 + dsh-local 规范源）移除「生图」状态/按钮与 image-gen 启动逻辑；Ollama 管理保留但移除 dsh-vision 文案。
- dsh-local 规范源同步清理：
  - `plugins/` 删除 dsh-image-bridge、dsh-image-vision；`services/` 删除 image-gen、ollama。
  - `manifest.json` 移除对应条目；`config/profiles/web` 的 package.json/template/cordis.patch.yml 移除相关依赖与装配。
  - `install.ps1` 移除 OLLAMA_MODELS/HF_HOME 环境变量、Ollama/image-gen 服务启动与健康检查。
  - 更新 README/AGENTS/PLAN/architecture/troubleshooting/plugins/services 等文档。
- 保留：GitHub 仓库/PR/分支（用户未选择删除）、原生多模态模型、Ollama 管理脚本（供未来重装）。

### 2026-08-21 删除 Ollama 控制入口

- 用户确认暂不保留 Ollama，删除所有 Ollama 管理入口：
  - `scripts/dsh-control.ps1`：移除 Ollama 配置、Extras、状态行、菜单项、Action-Ollama、启动逻辑。
  - `scripts/dsh-control-gui.ps1`：移除 Ollama 状态行、按钮、轮询状态/PID/模型检测、poll 参数与诊断文案。
  - `scripts/dsh-watchdog.ps1`：移除 Ollama 自愈（Ensure-Ollama、端口/模型变量、循环调用）。
  - `scripts/repair-dsh.ps1`：移除 Ollama 检查/启动段与 `-SkipOllama` 参数。
- 运行区脚本与 dsh-local 规范源同步清理，均恢复 UTF-8 BOM 且 Parser 0 错误。
- `F:\tools\ollama` 目录与 `OLLAMA_MODELS` 环境变量仍保持已删除状态。

### 2026-08-22 上游更新到 0.1.1-rc.2

- 通过 GitHub IP 工作区（codeload/api 可达，github.com DNS IP 不通）fetch 上游 master → `b150a551b8`（0.1.1-rc.2）。
- local/image-admission rebase 到新 master：
  - 丢弃旧 adapter image-admission 补丁（上游原生多模态已支持，不再需要）。
  - 保留 spawn windowsHide 补丁与测试。
- 构建：`pnpm install` + `npm run build:lib:host` 成功（后台任务）。
- dsh-selfuse 已推送最新 `fd7c97d`；manifest/README 已更新版本与补丁说明。

### 2026-08-22 社区插件索引确认 + math-research-dsh 提交 + web-ui-all 精简

- 识别截图中的「社区插件」页：不是 DeepSeek Harness 官方市场，而是 `@linxin666/dsh-web-ui-all` 全家桶自带的社区插件索引（`zhu1090093659/dsh-web-ui` 的 `community.json`，当前 36→38 条，只收录仓库链接不搬代码）。
- 保留 `dshmarket`（用户确认不删）；将 `math-research-dsh` 登记到该社区索引：
  - fork `zhu1090093659/dsh-web-ui` → `xsoc1/dsh-web-ui`，基于 `dev` 建分支 `add-math-research-dsh`。
  - 在 `packages/dsh-community-plugins/community.json` 追加条目（id `math-research-dsh`、category `tools`、author `xsoc1`）。
  - 用仓库自带 `node scripts/community-index` 重新生成 `src/client/generated/community.ts`（38 entries）。
  - 创建 PR：https://github.com/zhu1090093659/dsh-web-ui/pull/929（base `dev`）。
- 按用户选择精简 `@linxin666/dsh-web-ui-all`：保留 dshmarket 和社区索引/远程 UI 等，彻底删除 7 个子插件：
  `dsh-pet`、`dsh-tool-describe-image`、`dsh-client-ui-aionui-panel`、`dsh-liangshen`、`dsh-client-ui-skill-explorer`、`dsh-desktop-launcher`、`dsh-client-ui-plugin-manager`。
  - 从 `node_modules/@linxin666/dsh-web-ui-all/cordis.patch.yml` 移除对应 insert 行。
  - 删除上述 `node_modules/@linxin666/*` 目录（live + 管理仓副本）。
  - `cordis.patch.yml` 删除对应 disabled 项，仅保留 `web-ui-better-sidebar disabled`。
- 新增 `scripts/prune-web-ui.ps1`：安装/升级后自动清理上述子插件；已在 `install.ps1` 中接入，并为 web profile 的 `package.json` / `package.json.template` 添加 `postinstall` 钩子（手动 `pnpm install` 后同样自动清理）。
- 验证：prune 脚本 live/managed 均可运行，PowerShell Parser 0 错误；未重启 dsh（运行中的旧装配不受影响）。

### 2026-08-22 plugin-manager client bundle 加载错误修复 + web-ui-all 真精简

- 现象：浏览器报 `Failed to load plugins ... @linxin666/dsh-client-ui-plugin-manager ... bundle script ... failed to load`，dsh-control 状态仍显示正常。
- 根因：此前的精简直接删除了 `node_modules/@linxin666/*` 包目录；dsh 0.1.1 的 client-modules 按依赖路径加载每个 client.js，包目录缺失即报错（patch 层没有该行也一样）。
- 修复：`prune-web-ui.ps1` 不再删除包目录；改用真正的依赖精简——本地 `file:` 包 `F:\tools\dsh-local\plugins\dsh-web-ui-all-slim`（dsh-web-ui-all 0.2.7 副本，package.json 移除 pet / describe-image / aionui-panel / liangshen / skill-explorer / desktop-launcher / plugin-manager 7 个依赖）。
- profile 的 `package.json` 改为 `@linxin666/dsh-web-ui-all: file:F:/tools/dsh-local/plugins/dsh-web-ui-all-slim`；`pnpm install` 后 `@linxin666` 下只剩 10 个保留子包，7 个精简包彻底不在依赖树中（节省约 15.5MB）。
- 验证：dsh 重启后 HTTP 200；headless Chrome 抓控制台无 `Failed to load plugins` / plugin-manager / bundle script 错误（仅既有 iframe sandbox warning 与 better-sidebar 无工作区时的 `/sidebar/api/fs.tree` 400）。
- 经验：不要通过删 `node_modules` 包目录来“禁用”插件；Cordis 的 patch `disabled` 或本地 `file:` 精简包才是兼容方式。

### 2026-08-22 控制台增加 DSH 版本检查/更新 + web-ui-all 加载目录修正

- 新增 `scripts/update-dsh.ps1`：
  - `-Check`：读取本地 `package.json`/commit，用 GitHub API/`ls-remote` 对比上游，只读。
  - `-Apply`：拉取上游 master（含 github.com IP 兜底）、快进 master、rebase `local/image-admission`，然后 `pnpm install` + `npm run build:lib:host`。
- CLI `dsh-control.ps1` 新增：`check-update`、`update` 子命令与菜单 8/9。
- GUI `dsh-control-gui.ps1` 新增：
  - 状态栏「DSH版本」行（由 poller 读取 `$HarnessRoot/package.json`）。
  - 「检查更新」「更新 DSH」按钮（更新前弹确认；poller 异步执行 `update-dsh.ps1 -Check/-Apply`）。
- 修正 web-ui-all 精简方式：**不再删除 `node_modules/@linxin666/*` 包目录**，只从聚合 patch 移除不需要的 insert 行；
  否则 dsh 0.1.1 client-modules 按依赖路径加载 client.js 会因缺目录报 `bundle script ... failed to load`。
- 本地新增 `plugins/dsh-web-ui-all-slim`：只保留需要子插件依赖的本地聚合包，作为 profile 的 `@linxin666/dsh-web-ui-all` 链接源；
  所需 `@linxin666/dsh-*` 子包同时作为 profile 直接依赖安装，避免 link 依赖不展开的问题。
- dshmarket 更新到 `1.17.1`（live profile + 管理仓 package.json/template/lock）。
- 验证：`update-dsh.ps1 -Check` 可读；`dsh-control.ps1`/`dsh-control-gui.ps1` PowerShell Parser 0 错误。
- 注意：dsh web 当前未在运行（之前删除目录/切换链路导致）；下次启动需确认 profile/依赖已就绪。

### 2026-08-23 全面迁移到 WSL 原生文件系统 + 新 Obsidian skills + WSL 运行 dsh

- 依据 Microsoft WSL 文件系统文档，将整个工具链从 `F:\tools`（Windows DrvFs）迁到 `/home/huangzy/tools`（WSL ext4）：
  - `dsh-local`、`deepseek-harness`、`community-plugins`、`obsidian-skills`、`mattpocock-skills`、`docs`、`dsh-memory-panel`、`dsh-routing-suite`、`dsh-skill-router`、`awesome-dsh-plugin` 等已复制/同步到 WSL。
- WSL 内安装 Node.js `v24.17.0` + pnpm；安装 `build-essential` 后成功编译 `node-pty` 等原生依赖。
- `~/.dsh` 用户配置已复制到 WSL，并清理指向 `/mnt/c`、`/mnt/f` 的跨文件系统符号链接；`DSH_HOME=/home/huangzy/.dsh`。
- 新增 skills：
  - `skills/obsidian-skills/`（defuddle、json-canvas、obsidian-bases、obsidian-cli、obsidian-markdown，源 `kepano/obsidian-skills`）。
  - 更新 `install.ps1` / `sync-skills.ps1` / manifest 收录。
- 控制台/运行脚本已改为通过 `wsl.exe` 管理 WSL 内 dsh：
  - `run-dsh-web.ps1` 实际在 WSL 内启动 `node ... apps/cli/src/bin.ts web`。
  - `dsh-control.ps1` / `dsh-control-gui.ps1` 停止时调用 WSL `pkill` 清理 dsh 进程。
  - VBS 调度入口改为 `\\wsl.localhost\Ubuntu\home\huangzy\tools\dsh-local\scripts\...`。
- dsh web 已从 WSL 启动并通过 WSL/Windows localhost 均 HTTP 200 验证。
- 已推送 dsh-selfuse：`f85e063`（迁移+新 skills）、`a957d92`（WSL 运行管理）。

### 2026-08-24 selfuse 插件内化 + Web profile 切换到 @dsh-selfuse

- 在 `xsoc1/deepseek-harness` 的 `selfuse` 分支完成第三方插件源码内化：
  - `packages/selfuse/*` 统一为 `@dsh-selfuse/*`，保留原 LICENSE。
  - 新吸收本机自研 `memory-panel`、`skill-router`。
  - 修复自用插件 YAML 引用、缺失 SDK peer 依赖、remote-web-ui 的 `@linxin666` 残留。
  - 关键修复：DOM data attribute 恢复为稳定的 `data-dsh-better-sidebar` / `data-dsh-backup`，避免 sidebar/skin 选择器崩溃。
- 源码运行链路：所有 `@dsh-selfuse/*` 已加入 `apps/cli/package.json`，profile bundle 从 dsh 安装区解析。
- 新增一键脚本：
  - `scripts/selfuse/generate-profile.mjs`：生成 `~/.dsh/profiles/web`。
  - `scripts/selfuse/install.mjs` / `install.sh`：同步 profile、settings、skills。
- live web profile 已切到 selfuse 并重启验证：HTTP 200、各插件 client 路由 200、remote-web-ui 绕过保留。
- 用户确认当前稳定。
- 已推送到 GitHub：`xsoc1/deepseek-harness` `selfuse`（`c987a35620`、`57bbc737f9`）。
- 待办：控制脚本正式入库、F: 旧目录退役、pre-push/pre-commit hooks 对 selfuse 代码的排除策略。

### 2026-09-16 当前 WSL 0.1.6 云端同步

- 核对现役 WSL Harness HEAD `52801d41d4ef7af4972ea2b095d7170e32200f3b` 和官方 `0.1.6-alpha.1` 基线；将该提交推到 `xsoc1/deepseek-harness` 的独立 `selfuse-0.1.6-alpha.1-20260916` 分支，本仓子模块锁定该提交，未改 fork `master`。
- 本仓同步当前 Windows 控制、看门狗、启动脚本；增加 WinForms 控制台的源码、后台探针、只读诊断及测试快照，不提交 EXE、个人壁纸、服务凭据、日志或 `DSH_HOME` 用户数据。
- 记录 Safari/Tailscale Serve、严格的 `*.ts.net` trusted-host 启动兜底、代理直连检查、DERP 调试开关的回退边界和 iPad 端到端验收方法。旧 `install.ps1`、旧 profile/插件与历史 PLAN/architecture 已醒目标记为非现役资料。
- 验证：`scripts/run-dsh-web.test.ps1`、`console/tests/status-regression.ps1`、`diagnostic-routes.ps1`、`console-features.ps1` 全部通过；`manifest.json` 可解析，`git diff --check` 通过。只做代码和本机静态/定向回归，不能据此宣称 iPad Safari 已验证。
- 保留原 `F:\tools\dsh-local` 中的用户未提交改动；云端同步从新克隆的干净工作树完成，没有覆盖旧工作树或自动重启服务。

### 2026-09-30 官方 Desktop 本机切换与远程退役

- 用户先要求 iPad、手机都纳入远程验收，随后明确决定放弃 DSH 远程插件，并选择把旧 Windows 会话归档到 F 盘、Desktop 从官方 `standard` 新会话开始。旧 `wsl-router-standard` 日志未改写；官方 Desktop 只注册随包原生预设，旧 WSL 预设不会从 `.agent-presets` 自动加载。
- 用户正常退出桌面程序后，将 `C:\Users\HuangZY\.dsh\sessions` 整体移到 `F:\tools\dsh-retired-20260930\windows-sessions-legacy`，核对归档 229 个压缩会话文件、264825963 字节，并重建活动会话目录。WSL 原会话不动；其 Web profile 归档到 `/home/huangzy/.dsh/retired/web-profile-20260930`。
- 备份真实 Desktop patch 后，把 `agent-preset-registry.selectedDefault` 改为 `standard`，保留 `webserver` 的动态 loopback 端口及 gzip。桌面重启后新 v4 会话日志显示 `agentPreset: standard`，Host 监听动态本机端口。未做模型调用，也未把临时 profile 的插件安装误报为真实 Desktop 插件可用。
- 两项 DSH 看门狗计划任务需要 UAC 才能删除；操作前逐项核对任务动作，删除后读回确认均不存在，XML 存于 F 盘归档。Tailscale Serve 重置前核对仅有 DSH `443 → 127.0.0.1:3080` 一条规则，重置后状态为 `{}`；Tailscale 应用未卸载。
- WSL fork 删除 `@dsh-selfuse/remote-web-ui`、`control-gui` 源码及聚合引用，更新锁文件和生成目录。本仓删除 `console/` 与旧 Windows 管理脚本快照，更新 `manifest.json`、Desktop patch 模板和当前文档。旧 `F:\tools\deepseek-harness` 工作树只在干净的控制台包路径做精确删除，未清理其他用户改动。以上源码改动尚未提交或推送；门禁与桌面实际功能验收需分别记录。
- 复查发现 Desktop 曾把 `selectedDefault` 写回 `ptc`，虽然此前新会话显式记录 `standard`。停止本轮启动的五个 Desktop 进程后重新把真实 patch 设为 `standard`，再启动观察：配置保持 `standard`，五个 F 盘进程运行、Host 在 `127.0.0.1:34077` 监听，且没有新的 Host 崩溃报告。此端口仅是本次动态分配值，不可写入固定配置；尚未实测后续 UI 操作是否再次改动默认值。
- WSL fork 全量 `pnpm run build`、`pnpm run typecheck`、`pnpm run build:selfuse` 成功；`pnpm run doc-sync` 为 43/43。`pnpm run hygiene` 为 6/18，通过 6 项、失败 12 项，主要命中本轮未改的历史自用包、已有缺失的 `packages/client/runtime` 源文件/元数据及旧规则例外。此失败不等于本次删除导致，但仍阻止按用户此前要求发布；未提交或推送。`git diff --check` 和本仓 `manifest.json` 解析通过。

### 2026-09-30 Desktop 更新检查时 `write EPIPE`

- 用户只发截图：官方桌面版主进程弹窗 `A JavaScript error occurred in the main process`，正文显示 `Error: write EPIPE`，栈落在 `console.info` 与 `NsisUpdater.checkForUpdates`。没有把截图文字当成新的配置指令。
- 现场主进程的父 PowerShell 已退出，窗口标题为 `Error`。关闭报错实例后做单变量对照：以重定向标准输出启动实际 F 盘 EXE 并立刻关闭读取端，12 秒后为 `Error`；保持读取端开放，同样时间窗口标题为 `DeepSeek Harness`。这个自动检查未抓取弹窗正文，因此它验证的是同类错误窗口与输出管道的因果关系，不能单独证明每次异常栈逐字相同。
- 用 Windows Shell 启动真实 Desktop 后，发起命令的 PowerShell 退出，主进程仍显示正常 `DeepSeek Harness` 窗口；约 20 秒后再次读回正常，`selectedDefault: standard` 保持，最新 Host 崩溃日志仍停留在此前端口故障的时间。当时把这当成修复，实际未覆盖定时更新轮询；下一节记录复发和更正。

### 2026-09-30 同一 `EPIPE` 的延迟复发与修正

- 用户再次发来完全相同的异常截图，确认程序是运行一段时间后自动弹出，而非手动点击检查更新。上一节把 Shell 启动后约 20 秒正常误报为已修复；官方 rc.2 本机源码的普通更新轮询默认间隔为 600000 毫秒，故上一轮没有覆盖延迟触发。此结论已在 `AGENTS.md` 与当前部署说明更正。
- 用户结束实际会话并正常退出程序后，在原隔离 `F:\Apps\DeepSeekHarnessSmoke` profile 只加 `webserver.port: 0`，用环境变量把测试进程的更新间隔缩至 1000 毫秒、抖动设为 0；正式 profile 的轮询配置未改。关闭测试进程继承的标准输出读取端，8 秒内重现 `Error` 窗口。把同一 EXE 的标准输出与错误输出重定向到 F 盘文件，启动父进程退出后，日志记录 82 次 `Checking for update` 及 82 次对应结果、0 次 `EPIPE`；随后停止隔离测试进程。窗口正文未自动读回，完整异常栈仍以用户截图为证。
- 真实 Desktop 重新用两个持久文件承接输出启动；初次检查日志正常，主窗口为 `DeepSeek Harness`，`selectedDefault: standard`，启动父进程已退出。日志位于 `F:\Apps\DeepSeekHarnessRuntimeLogs`，该目录及两份日志的 ACL 已精确收紧到当前用户、管理员、系统。隔离 profile 的临时端口补丁已恢复原状，四份短期探针日志已从 F 盘归档目录精确移除（共 15111 字节）。没有修改官方二进制、用户会话、更新源或正式轮询频率；隔离加速测试证明了周期性检查在此启动方式下可重复运行，但不能替代真实 profile 连续运行数小时的观察，也不能证明普通开始菜单路径安全。

### 2026-09-30 复检验收：运行链路与发布边界

用户要求“再复检验收一轮目前方案”。本轮不变更运行配置，不停止或重启当前 Desktop，不写入会话、不新增模型请求、不推送。检查范围覆盖官方安装与进程、更新输出、系统重启事件、真实 profile、完整会话帧、归档、远程退役状态及源码回归。当前工具列表没有 Computer Use 所需的 `node_repl`，因此没有自动点击 GUI；窗口标题、监听端口及历史对话日志不等同于全部界面操作验收。

| 检查项 | 实际结果与边界 |
|---|---|
| 官方安装 | F 盘 EXE 的 Authenticode 签名有效；开始菜单仍直接指向该 EXE，无启动参数；官方版本为 `0.2.0-rc.2` |
| `EPIPE` 长时间检查 | 09:43 文件重定向实例 PID 60552 的 stdout 有 18 次 `Checking for update` 和 18 次对应结果，0 次 `EPIPE`；最后一次结果为 12:24；日志 ACL 保持当前用户、管理员、系统 |
| 重启前 Host 报告 | 12:34:14 报 Host 退出码 `1073807364`（`0x40010004`）；系统 LastBootUpTime 为 12:34:32，系统日志也记录关闭/启动。退出与重启时段重合，更符合重启终止，尚不足以指认 DSH 独立故障或终止者；它不是 `EPIPE` 报告 |
| 当前实例 | PID 26016 于 12:35 启动，父进程 `explorer.exe`；15:40 已运行约 185 分钟，五个官方 EXE 进程仍在、Host 只在 loopback 监听、未授权请求返回 401、无新 Host 报告或 DSH `Error` 标题窗口。主窗口标题为空，可能是后台状态，未据此判断可见界面。旧 stdout 日志不属于当前实例，当前更新轮询次数未留证 |
| 预设与真实使用 | patch 的 `default` / `selectedDefault` 仍为 `standard`；两个活动会话头均为 v4 `standard`。主会话后来显式切到官方 `ptc`；完整 648 帧、1205 行可解码，三轮分别于本地 09:36、10:18、13:12 记录 `completed`，有 124 条 assistant 消息和 121 次 `run_code` 调用 |
| 文件工具缺口 | 121 次工具调用含 4 次错误：两次在 `\\wsl.localhost\Ubuntu` 新建文件的硬链接发布报 `ENOTSUP`，一次搜索 `\\wsl.localhost\Ubuntu\mnt\f\tools\AGENTS.md` 拒绝访问，一次执行到 120000 毫秒超时；没有把正常 turn/end 误当成工具零失败 |
| 旧会话归档 | 229 个文件、264825963 字节；使用源码 `scanZstdFrames` 定位每个压缩帧，再用 Node 公共 API 解压并逐行解析 JSON，229/229 成功、0 个残缺帧、0 个解析失败。单次对整个文件调用 `zstdDecompressSync` 只读到第一帧，不能用于完整会话验收；此前没有输出用户正文或凭据 |
| 远程退役 | 两项 DSH 看门狗任务为 0；Tailscale Serve 为 `{}`；WSL 3080 无监听；活动 Web profile 不存在、归档 profile 存在，WSL 会话现有 391 个文件仍保留。Windows Desktop profile 依赖为 `{}`，只包含官方 bundles |
| 定向回归 | `pnpm exec vitest run` 对 update-coordinator、update-schedule、host-process、main-startup、profile-mcp、cli-launcher 六个测试文件为 175/175；这是 WSL 源码测试，不是对已签名 Windows app.asar 的替换或 GUI 端到端测试 |
| 全量门禁 | 本轮 `pnpm run doc-sync` 为 43/43；`pnpm run hygiene` 仍为 6/18。失败包括 vendor rescope、publint、constraints、package dependencies、两项包不变量、client packages/i18n/routes、proxy-aware dispatchers、unknown casts、Cordis config；本仓 manifest schema 和 diff 检查通过 |

`0x40010004` 的微软定义为 `DBG_TERMINATE_PROCESS`，但退出码不能证明是谁或因为什么终止进程，见 [Microsoft NTSTATUS 定义](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-erref/596a1078-e883-4972-9bbc-49e60bebca55)。这里只将本机系统事件与 Host 时间线关联，不将其替代根因证据。

验收结论是**运行链路部分通过，完整迁移/清理与发布未通过**。发布前还须处理以下已明确的缺口，而非放宽门禁：

- Windows 原生文件工具不应把 WSL UNC 当作可完整兼容的本地文件系统；后续用 Windows 本地工作区复验，WSL 文件写入由 WSL 执行世界处理。不能通过退化原子写入、改写会话日志来掩盖问题。本轮没有自动搬移用户工作区。
- `packages/selfuse/remote-web-ui` 已删除源码，但路径下还留有 `node_modules`；constraints 明确把这个缺少 package.json 的包目录列为失败之一。因此上一轮“主要为历史债务”的归因不覆盖全部失败，开发树清理仍有残留。本轮仅核查，没有自动删除该目录。
- 真实 Desktop 未安装自用/第三方插件；临时 profile 的安装测试不能当作正式插件迁移完成。普通 Explorer 启动已有约三小时无新 Host 报告的现场证据，但没有当前轮询日志或 GUI 操作验证，仍保留自动化文件重定向启动方法。
- 本轮只更新本仓维护文档和 `AGENTS.md`；保留用户及此前退役改动，不提交、不推送，不声称云端已同步。

### 2026-09-30 继续修复：原生 F 盘工作区与源码门禁

用户要求“继续修复”，选择“桌面使用 F 盘本地工作区”，并回复“已退出”。本轮在进程为零时备份并切换工作区，随后用真实签名 Desktop 发起一轮专用文件工具验收，不把源码构建或临时 profile 当作实际桌面成功。

- 工作区备份为 `F:\tools\dsh-retired-20260930\native-workspace\workspace.before.json`。仅新增工作区 `b3e435fc-8b4f-4ef9-b12f-65476ac054e9`，路径 `F:\tools`，标题 `tools (Windows)`。旧三个工作区及其会话列表与备份逐项相同，归档和置顶会话列表也未改变。官方 `defaultWorkspaceId` 只用于首次初始化，不能用它代替导航选择。
- 在一次临时、仅 loopback 的调试启动中，精确重置客户端 `dsh.sessions.current` 导航键，观察并核对新原生工作区选择。没有清空浏览器资料、登录状态或所有 localStorage。通过当前桌面页面的认证 RPC 发送一条受限测试请求，仅允许专用测试文件的 `write/read/edit/read`，不允许其他文件、网络或执行工具操作。
- 真实日志为 `C:\Users\HuangZY\.dsh\sessions\--F-tools--\session-44a94132-2ad7-414f-8c79-0506c5510bc6\session.v4.jsonl.zstd`。完整帧解码显示会话头为 `standard`、`F:\tools`；四次工具调用及持久结果均成功，最终 `turn/end` 原因为 `completed`，第二次读回内容为 `DSH_NATIVE_EDIT_20260930`。未把模型自述当作验收，也没有使用 `run_code` 绕过文件工具。
- 独立探针通过 Electron 的 Node 模式加载已安装 app.asar 中的 `@deepseek-ai/dsh-fs-local`，不是 WSL 源码替身。实际通过八项：原生相对路径、受保护硬链接新建、UTF-8 读取、不覆盖保护、原子编辑并保留 CRLF、拒绝旧版本编辑、受保护 Win32 替换、绝对路径与目录枚举。以 `Start-Process -Wait` 核对退出码 0 与八项结果，不能把 GUI EXE 发起后返回或空日志误认为完成。
- 调试实例正常关闭后，以无调试参数的普通模式重启；当前主进程 PID 22616、16:22 启动，Host 只在 loopback 监听。旧调试端口 38294 已无监听；当前输出使用受限 F 盘日志文件。本轮测试脚本、专用测试文件、结果和备份已移到上述归档目录，逐文件哈希一致，真实验收会话保留。旧会话和 WSL 项目文件未删除，官方二进制未修改。
- 源码将 `remote-web-ui` 的仅 `node_modules` 残留移到 `/home/huangzy/tools/dsh-retired-20260930/source-residue/remote-web-ui`，可恢复；使用官方 rescope 生成器修正旧依赖名称。移除 SSH、任务板两个不注册任何断言的空不变量伴随模块及导出，保留服务实现；两个有实际断言的模块明确加入发布文件。构建产物不变量检查通过 41 个伴随模块。
- 保留但未启用的市场源码改用官方 Host 全局 HTTP 策略，代理诊断按实际目录/镜像 URL 解析；增加四项测试，覆盖直连、Host 代理、无私有 dispatcher、无效 URL。两个客户端请求改为文档相对路径。以上修复不重新启用市场或 WSL 工作区插件。
- Gateway 心跳改为数字类型收窄，新增字符串和 null 拒绝用例；修正 rescope 对 inspect 测试事件名的误匹配，分别验证事件名保留及真实模块 import 仍改名。四个定向测试文件共 69/69 通过。双语文档、配对记录和第三方声明使用仓库命令重新生成；真实原生验收与源码发布门禁分别记录。

最终复跑：`pnpm run doc-sync` 为 **43/43**，`pnpm run typecheck`、`pnpm run build`、`pnpm run build:selfuse` 均完成；`pnpm run hygiene` 从此前 **6/18** 提升到 **10/18**，仍有八项失败。通过的是本轮相应修复及其他现有检查，不代表整体发布验收通过。文档与类型检查曾因改名误改事件名而失败，已修正后重新整套运行；没有只引用失败前的旧绿灯。

补充最终回归：官方 Desktop 的更新协调/定时、Host 进程、主进程启动、profile MCP、CLI 启动六个测试文件与本轮四个源码修复文件同组执行，10 个文件 **244/244** 通过；`pnpm run test:docs` 为 **21/21**。全仓 `pnpm run lint` 对 5254 个文件报告 **1247 个错误、5 个警告**，未通过；没有本轮干净基线对照，不能断言每一条都是既有问题。这是独立的发布缺口，不能用构建、文档或卫生门禁的部分通过替代。

九个本轮涉及的代码文件另做定向 lint，共 44 个错误，全部位于旧任务板设置卡对 `t()` 的类型解析；其他八个文件没有报告错误。该卡本轮只改了 EventSource 的相对 URL，没有修复旧 runtime 类型。既不把定向 lint 宣称通过，也不将其 44 项与全仓 1247 项相加。后续需要迁移旧客户端 API 并重新验证，不能用类型断言或禁用规则掩盖。

八项剩余失败有：publint（六个旧 EAC 包缺少声明的产物）、constraints（旧版本和第三方/私有包不满足官方发布成员规则）、package dependencies 与 package invariants（冻结的 `packages/client/runtime` 没有源码/tsconfig）、client packages（旧 runtime 种子未使用 staticLinked 构建）、client UI i18n（29 处硬编码文本/键）、no new unknown casts（历史自用包双重断言）、Cordis config（旧包没有可解析的源码路径）。这些包仍存在于开发工作树，不在真实 Desktop profile 中；不能通过伪造源码、改成官方所有权或扩大忽略项获得绿灯。全部要求通过前不提交、推送或更新本仓子模块 pin。

16:56 的真实普通实例再次读回：四次更新检查、四次对应结果、0 次 `EPIPE`；主进程存活，Host 为 `127.0.0.1:44783`，旧调试端口无监听，EXE 签名仍有效。此证据覆盖本次约 34 分钟运行和正常轮询，不延伸为普通开始菜单路径或任意运行时长已无问题。

### 2026-10-01 退役源码归档与打包复验

用户要求继续修复，并批准“归档退役旧包”，明确不删除会话、不动仍有用途的插件。先追踪 `apps/cli/package.json`、候选 profile 和源码入站引用；归档目标为五个已退役 EAC 包（client-file-changes、easy-setup、file-changes、shell-terminal、web-shell-bridge）及 market、skill-router、wsl-workspace。`eac-task-notify` 仍被候选配置引用，继续保留；真实官方 Desktop 的 profile、工作区和会话没有修改或重新启动。

完整目录移到 `/home/huangzy/tools/dsh-retired-20261001/source-packages`，包含未提交改动、构建产物与依赖；移动前后逐个校验 **195 个受 Git 跟踪文件**，SHA-256 全部一致。执行脚本、清单和本轮验收日志保存在 `F:\tools\dsh-retired-20261001`。恢复前核验当前源码链接与目标目录，逐包恢复并重新生成/测试，不覆盖新文件。只暂存本轮明确归档的删除路径，未批量覆盖用户改动。

使用仓库命令更新 pnpm 锁文件、配置/插件/客户端/依赖/模块目录、关系图、第三方声明及双语配对；删除退役包的 README 分类记录。部署回归不再读取已归档 bridge 的 bundle，而直接核验候选清单、原生 CLI 依赖及八个源码目录均无退役包；另验证通知包仍保留。没有修改门禁忽略清单或把第三方包冒充官方发布成员。

真实打包缺陷也已修复：通知包声明包含现有 `lib/index.js`；Git 图只收录实际 Host/client/invariant bundle 和类型声明，不把缺少 CSS 的中间 `lib/types/*.js` 当运行资产；undo 两个回归脚本改为实际 `lib/index2.js` 入口，并修复四个含包命名空间斜线的 `mkdtemp` 前缀。通知包载荷回归先失败再通过，完整 publint 同样先失败再通过；undo 曾因第二至第四临时目录前缀失败，修正后重跑整个包测试，而非引用途中部分结果。

| 本轮复验 | 结果与边界 |
|---|---|
| selfuse 部署/归档/通知载荷回归 | **11/11**；使用可丢弃用户目录，未恢复真实 Web 服务 |
| undo 配置逻辑回归 | **101/101**；加载实际保留 bundle，模拟 Host、临时配置；不是 Desktop 注册验收 |
| undo 实际文件监听时序回归 | **10/10**；临时文件的自动快照、undo 抑制回声快照与 redo 阻断均通过 |
| publint 检查器回归 | **7/7**；包括不完整载荷被拒绝的既有用例 |
| Desktop 源码回归 | 更新协调/定时、Host 进程、主进程启动、profile MCP、CLI 启动六个文件 **175/175**；不是对签名 app.asar 的替换或 GUI 端到端验收 |
| 类型与构建 | `pnpm run typecheck`、`pnpm run build`、`pnpm run build:selfuse` 均完成；没有改动签名安装包 |
| 文档 | 最后整套 `doc-sync` **43/43**，`test:docs` **21/21**；归档初次造成的旧目录链接和中文链接问题已修复并整套重跑 |
| 卫生门禁 | **11/18**；publint 已通过，仍有七项失败，未发布 |
| 全仓 lint | 最后检查 5198 文件，**305 错误、1 警告**；归档后首次为 302，完整构建后最后为 305，以最后结果为准。此前为 1247/5；移出退役包减少检查对象，不意味着每条旧错误都修好了 |

七项剩余失败是 constraints、package dependencies、package invariants、client packages、client UI i18n、unknown casts、Cordis config。已确认旧 `packages/client/runtime` 缺少源码和 tsconfig、旧 API 的类型与模块种子不匹配；多个有用整合包只保留编译产物，不能凭空补假源码或关闭检查。i18n 剩两处 SSH 文本，unknown cast 剩 24 处；它们仍须按各包实际类型/源码处理。第三方 Desktop 激活尚未验收。全部要求通过前继续不提交、不推送、不更新本仓子模块 pin；本机归档和构建完成不等于云端已同步或完整升级交付。

## 2026-10-01 继续修复：请求校验与真实服务回归

用户再次要求“继续修复”。本轮只改 WSL 开发源码与说明，未重启或修改真实 Windows Desktop、profile、会话、远程服务和签名二进制。按失败检查→回归→修复→复跑处理，未扩充 cast 基线、增加忽略项或放宽发布门禁。

- 隐私插件测试不再用只有 `session.header` 的对象冒充完整 Agent，也不伪造审批服务。改用真实 AgentRegistry/AgentLoop、Session、projection 和审批服务；审批审计通过事件订阅读回，PTC 日志使用实际工具执行对象和正确 scoped dispatch。Loader 通过真实 `cordis.yml`/Include 装配，只有模块解析受测试控制，并验收禁用后工具消失、重新启用后恢复。外部模型适配器仍是受控测试替身，不能据此宣称真实提供方接受请求或能够绕过其策略。
- SSH HTTP 负例先复现：对象类型的密钥口令被返回 HTTP 200 并写入。新增逐字段解析器后，畸形认证、备注、端口、标签及跳板链返回 400，文件逐字节不变；合法局部更新保留旧凭据，响应不含口令，跨来源请求仍为 403。使用真实 HTTP listener、HostStore、SshEngine 与临时目录，不连接外部 SSH。
- SSH 两处硬编码界面文字改为共享中英文字典；API 错误与实际 ClusterTab 渲染测试覆盖语言切换、错误响应和 `27 ms` 耗时。任务板动作解析改为由已验证字段构造封闭联合，保留禁止未知字段的检查；JSON 结果用 `unknown` 变量承接而非强制断言。
- 定向回归 **24/24**，隐私包及新 SSH 测试/解析器/共享文字的重点 lint **13 文件、0 错误、0 警告**。全仓 lint 完整构建后最后为 **5203 文件、269 错误、1 警告**；构建前为 266，增加的三个报告都在 Git 图 `src/client/index.ts:123` 的旧会话字段读取。较上一轮 305/1 减少，但仍未通过，不能引用构建前数字，也不能把部分重点 lint 等同于所有改动文件干净。
- `typecheck`、`build:selfuse` 已通过；其中后者实际重新编译隐私包，不等于重建所有第三方插件。卫生门禁 **12/18**，国际化已通过，禁止 `as unknown` 的未通过位置由 24 降到任务板的 **3** 处。剩六项为 constraints、package dependencies、package invariants、client packages、unknown casts、Cordis config。

另查明 SSH、任务板引用的 `tsconfig.build.json`、`tsconfig.json`、tsdown 配置均不在当前整合包中；全仓 build 不会重新生成其冻结 bundle。其 Client 部分仍依赖旧 runtime，不能把新 HTTP/渲染源码测试误报为产物修复或 Desktop 插件可用。后续须恢复真实可重建工程、迁移官方拆分后的 Client 服务并分别验收源代码与产物；不能补假源码或改 manifest 版本冒充适配。最后完整构建通过并记录 368 个 Client 产物，`doc-sync` **43/43**、`test:docs` **21/21** 通过；这些绿灯不替代六项未通过门禁或第三方产物/激活验收。全部要求通过前不提交、不推送、不改子模块 pin。原始日志保存在 `F:\tools\dsh-retired-20261001\interface-repair`。

## 2026-10-01 按方案精简旧 UI 兼容包

用户在弃用建议后要求“按你的方案办”。执行首选的四项归档：web-ui-settings、web-ui-community-plugins、skins、web-ui-all。先检查实际引用与必要行为，发现任务板的旧设置页依赖以及皮肤资源所需的布局属性，再做最小适配、可恢复移动和测试。完整目录（含未提交文件、产物及依赖）移至 WSL `/home/huangzy/tools/dsh-retired-20261001/native-ui-packages`；46 个受跟踪文件、389754 字节逐个 SHA-256 一致，复验时四个活动目录均不存在、四个归档均存在。方法与回退见[精简说明](plugin-retirement-20261001.md)。

候选清单直接加载 Git 图和皮肤中心，皮肤布局适配独立为小型可重建叶子包。生成器不从旧 profile 恢复四项明确退役依赖，但保留无关 CLI 插件及本机覆盖；非法清单试图重新启用退役包时，在写 profile 前失败。任务板源码取消旧设置包依赖并改接官方 settings.section；剩余旧 Client API 和冻结产物不被误称为已迁移。memory-panel、git-workflow 与其他条件项暂时保留，没有删除记忆、账本或会话。

| 最后复验 | 结果与边界 |
|---|---|
| 定向回归 | **40/40**；真实 Loader/Include、DOM 生命周期、构建集成、rescope、隐私、SSH 与任务板协议 |
| 生成器与实际浏览器产物 | **13/13**；临时 home、旧依赖清除、无关插件保留、非法清单拒绝；jsdom 执行真实 lib/client.js 工厂 |
| 新增代码重点 lint | **5 文件、0 错误、0 警告**；不是任务板旧 Client 部分已全面通过 |
| 类型与构建 | 正式聚合 `typecheck` 和完整 `build` 通过；构建记录 364 个 Client 产物，皮肤布局叶子包真正编译；不代表所有冻结第三方包各自 typecheck 或重建通过 |
| 文档门禁 | 最后整套 **43/43**；初次新增 README 缺少 Dev Note/限制列表、目录和配对记录过期均已修复后重跑，无新忽略项 |
| 卫生门禁 | **12/18**；仍有六项失败，未发布 |
| 全仓 lint | **5205 文件、268 错误、1 警告**；中途新增测试缺少开发依赖/Node 声明导致的报告已修复，引用最后完整检查而非中途数字 |
| 真实 Desktop 保护 | 三份 profile 文件与操作前哈希相同，第三方依赖仍为 **0**；未改签名程序、工作区、会话或进程，未进行插件 GUI 激活验收 |

归档后的 rescope 初次试图读取 Git 索引中尚未暂存删除的旧文件；改为只处理当前存在的受跟踪文件，保留 exact-edit 与 postcondition 检查，没有添加退役包忽略清单。源码别名为新布局包显式注册；生成客户端/配置/插件目录、锁文件与双语配对。文档规范与 writing-for-agents 要求同步了包说明、项目 AGENTS 和具体对话记录。

六项剩余失败仍是 constraints、package dependencies、package invariants、client packages、unknown casts、Cordis config。旧 runtime 缺源码和构建配置，冻结第三方包缺可解析源码，自用层身份仍不满足官方发布成员元数据要求；新的本地布局叶子包保持 private，也没有伪造官方仓库所有权来通过这一规则。任务板还有三处历史 unknown 双重断言。本轮源码精简和定向验收完成，不等于完整发布方案已验收；全部要求通过前继续不提交、不推送、不更新子模块 pin。原始日志与归档清单在 `F:\tools\dsh-retired-20261001\native-ui-retirement`。

## 2026-10-01 条件插件归档与可重建源码收尾

用户明确回复“归档三个条件项，优先原生功能”。SSH、任务板、MinerU 与仅被退役包使用的旧 ClientRuntime/ApiProxy 完整移至 `/home/huangzy/tools/dsh-retired-20261001/conditional-packages`；764 个文件/链接记录、7359945 字节的哈希和链接目标逐项一致。会话、记忆和插件用户数据未移动或删除。原生 SSH 与计划任务作为优先方案；不能将官方能力宣称为 MinerU OCR 的等价实现。生成器拒绝候选清单重新启用九项退役依赖，保留无关 CLI 插件和用户本地覆盖；用户自有覆盖中若仍指定旧行，须另行处理，不能宣称已自动改写。

皮肤中心从 dsh-web 的固定 v0.2.7 提交 `314f9ea7524c1a8fa2bb6c9a2c3bcaaa440cee5f` 恢复 34 个真实源文件，逐文件记录哈希且不覆盖本地源码；恢复脚本验证标签解析出的提交，且不再恢复已归档 SSH/任务板或已移除的空 Git 图 invariant。240 个非 Git 跟踪、带有实际 TS 源映射的重复编译文件移出 src，1084269 字节原样保留；后续正规构建没有再次向 src 写入这些产物。生成残留的原始写入者仍未确定。

保留包改接当前原生 ConfigForms、uiRenderer、会话控制服务和显式 Host/Client 工程。皮肤设置使用 Loader 行标识与原生 ConfigForms 校验/冲突处理；Git 图删除无断言的空 invariant，不以空安装器冒充检查；隐私包按源码项目引用严格编译，测试使用当前工具消息结构。通知包迁至 task-notify，以真实 Session 生命周期回归修复已销毁会话标题残留，并明确 Windows 实际通知投递尚未验收。本地隐私隔离不绕过模型服务商政策。

| 本批验收 | 结果与边界 |
|---|---|
| 定向源码和产物回归 | **137/137**：105 项私有包元数据检查及 32 项 ConfigForms、隐私、通知、实际浏览器 bundle 工厂等测试；不是 Desktop 图形激活或真实模型验收 |
| 生成器、归档参数与恢复 pin | **17/17**；临时目录和负例，非法参数/标签在写入前被拒绝 |
| 严格聚合类型检查 | `tsc -b tsconfig.host.json tsconfig.client.json` 通过；不再整体排除 selfuse |
| 可重建产物 | 皮肤中心、Git 图、通知和隐私包的实际 build 通过；不是所有旧第三方 JS 包均已重建 |
| 完整文档门禁 | **43/43**；通知新增生命周期事件导致关系图过期，使用生成器修复并整套重跑 |
| 卫生门禁 | **15/18**；剩 package dependencies、package invariants、Cordis config，主要阻塞于 backup 等旧 JS 工程 |
| 全仓 lint | 本批先为 **5176 文件、197 错误、0 警告**；后续 Git 工作流适配复跑为 **5179 文件、197 错误、0 警告**，仍未通过 |
| 完整 selfuse 构建及集成用例 | 均失败于 backup 没有真正的 build 脚本；git-workflow、memory-panel、undo 和 soul-md 等也仍需源码/构建适配，不以跳过或假入口通过 |
| 真实 Desktop 保护 | package.json、cordis.patch.yml 与此前保护清单的哈希一致，pnpm-lock.yaml 仍不存在；没有修改签名程序、真实 profile、会话或启动进程 |

原始日志在 `F:\tools\dsh-retired-20261001\completion-repair`。本批归档和适配完成，完整发布仍未完成；没有提交、推送、改管理仓子模块 pin 或安装到真实 Desktop。继续修复保留包时按实际执行故障、严格源码、产物和隔离运行分别验收，不能以文档全绿替代其他失败。

### 后续：Git 工作流原生工具与可重建工程

Git 工作流从原有 Host/纯解析 JS 逻辑迁为严格 TS 源码，加入真实编译与 bundle 构建，并保留五种工具的结构化字段；旧 lib 先备份到 WSL `dsh-retired-20261001/completion-artifacts/git-workflow-lib`。新实现使用当前 `defineTool` 参数验证及可空输出 schema，修复日志 `-n` 与数量被合并为一个参数、分支格式缺少分隔空格两处执行问题。不能仅凭原有纯解析测试通过判定真实工具可运行。

实际 bundle 装入原生 tools、system-prompt、subprocess、sandbox-policy 和 Bash 服务，三项临时仓库运行测试通过：带上游为空的状态结果、限量日志、完整分支名；带单引号及 shell 表达式的提交消息保持字面内容且无额外文件；diff 摘要、路径拒绝、插件行卸载及只读策略拒绝。只读用例也允许沙箱执行器不可用时失败关闭，不能由此声称本机所有 OS 沙箱后端均能正常执行。没有触碰用户项目的暂存区或提交，没有外部模型请求。

旧 `node --test test/` 在当前 Node 中不能解析测试目录，已改为实际文件入口；15 项辅助解析/策略测试通过。新增工程三个代码文件重点 lint 为 **0/0**，完整 Host/Client 聚合类型检查重新通过；完整文档门禁再次 **43/43**、卫生门禁仍 **15/18**。完整 selfuse 构建继续被 backup 缺少真实 build 阻止；Git 工作流不再是缺少构建入口或源码别名的包，backup、memory-panel、undo、soul-md 等待办未被隐藏。README 中删去私有包可直接从 npm 安装的错误暗示；Windows PowerShell 与已安装 Desktop 激活仍待独立验收。

最后将 Git 运行用例与此前十个回归文件合并重跑，**11 文件、140/140** 通过；生成器/归档/恢复 pin 另 **17/17**，Git 辅助用例另 **15/15**。管理仓 manifest 按 draft-07 schema 验证通过，两仓涉及路径的 diff 空白检查通过。13:58 再次逐项比较 Desktop 保护清单，两份文件哈希相同且 lockfile 仍不存在，结果落盘 `desktop-protection-final.json`。恢复脚本干跑为 0 个待恢复文件，重复源码产物干跑为 0 文件/0 字节。严格保留失败状态，不提交、推送或安装候选插件。

## 2026-10-01 继续维护：备份包和样式声明

用户要求“继续维护”。本批先保存 backup 缺少 build 和原生 schema 失败的实际证据，随后将原有 Host、Client 功能迁为严格 TypeScript，加入显式项目引用、类型导出和原生 clientBundle；不是空 TS 入口或冻结 JS 的包装。备份默认值使用原生 Config，Typert 服务有明确返回类型和完整目录归属，客户端 codec 与失败响应匹配。Host/Client 分别生成声明，共享浏览器安全的响应源码，不交叉引用另一面工程。

修复真实运行暴露的故障：恢复前轮转不再删除选中归档；换 Git 仓库时从新远端读取 lease，新仓库实际收到归档；本地凭据文件不进入提交；列表超出内存保留区时读取完整 spill，完整输出仍超过 1 MiB 则在恢复写入前停止；恢复拒绝链接、特殊文件和逃逸路径。本机 HTTP 同时检查 Host 与对端地址，拒绝归档符号链接并从已打开的普通文件读取；没有 Web 服务时不显示无效下载入口。文件删除/重命名使用字面 Node 文件操作，修改动作按插件实例串行化。恢复不是并发写入者的一致快照，解压失败不自动回滚，校验和不是加密或认证。

旧 `src/*.js`、旧 JSX、独立构建/假服务冒烟脚本、fixture 和嵌套锁文件共 13 份先逐项比较 SHA-256，再用补丁删除；原文件仍在 `/home/huangzy/tools/dsh-retired-20261001/backup-before-maintenance` 可恢复。用户数据、会话和真实 profile 不在这些删除目标内。候选源码不再维护两套备份实现；私有包安装说明不再宣称可从 npm 直接安装。

随后处理保留包 lint，先在相关 selfuse 路径做机械修正，再将皮肤中心宽泛 CSS 索引声明改为编译器实际导出类名。严格编译发现壁纸目录引用六个不存在的样式，已补齐真实样式，声明对应 60 个实际类名。新增测试直接调用 Lightning CSS 比较导出表，缺失或虚构名称都会被拒绝，不通过伪造声明或放宽 lint 绕过问题。原生服务、客户端和配置目录由生成器更新，双语 README 按对侧同步记录。关系图的新增服务同步到中文对侧后，完整文档门禁重新通过。backup 使用原生工厂并仅压缩 Client 产物，保留准确源映射及可读 Host；没有手工删改内联第三方模板字符串来消除空白检查错误，最后回归执行的是重新构建的实际工厂。

### 本批验收状态

最终源码和产物已组合复测。证据在 `F:\tools\dsh-retired-20261001\maintenance-next`，完整门禁失败保留原日志，没有添加整包忽略或提高错误基线。

| 本批最后复验 | 结果与边界 |
|---|---|
| 组合源码和真实产物回归 | **12 文件、33/33**：backup 的 10 项存储/原生 Host/Client/CLI 用例、皮肤/通知/工厂 13 项及服务目录分区 10 项；15:40 最后重跑执行压缩后的实际 Client 工厂，不是模型或 Desktop 图形验收 |
| 严格聚合类型检查 | `tsc -b tsconfig.host.json tsconfig.client.json` 通过；backup 不再依赖无源码的旧 JS 入口 |
| 可重建产物 | backup 与皮肤中心实际 build 通过；完整 `build:selfuse` 仍因 memory-panel 无 build 脚本而停止，不宣称全部包已完成构建 |
| 重点 lint | **14 文件、0 错误、0 警告**；覆盖 backup 源码、运行测试、构建配置、CLI 测试、CSS 导出测试和服务图/目录生成器 |
| 完整文档门禁 | **43/43**；末次修复英文生成图与中文对侧、重新记录双语配对后整套重跑 |
| 卫生门禁 | **15/18**；package dependencies、package invariants、Cordis config 仍失败，直接定位到 memory-panel 缺少源码/工程及 memory-panel、undo 的源码别名问题 |
| 全仓 lint | **5190 文件、168 错误、0 警告**；本轮起点为 197，当前仍未通过，不能以重点 lint 全绿替代 |
| 管理仓与空白检查 | manifest 按 draft-07 验证通过；两仓 diff 空白检查通过，未重写内联第三方源字符串 |
| 真实 Desktop 保护 | package.json、cordis.patch.yml 哈希与保护清单相同，pnpm-lock.yaml 仍不存在；未启动、安装候选包或修改真实会话 |

发布仍受 memory-panel 缺失真实构建入口、undo/soul-md 等旧工程和全仓 lint 阻止。没有提交、推送、修改子模块 pin 或安装候选插件到真实 Desktop；实际 GitHub HTTPS 认证、Windows tar 和 Desktop 图形激活未验收。`desktop-protection.json` 记录两份保护文件哈希相同及 lockfile 仍不存在，不代表所有用户文件被逐项审计。

## 2026-10-01 xiu：记忆面板原生适配

用户输入“xiu”，按“继续修复”处理。先按诊断方法保存旧 Host/Client、两份 smoke、配置与双语说明到 WSL `/home/huangzy/tools/dsh-retired-20261001/memory-panel-before-repair`，记录旧构建和加载失败，再迁移真实源码。旧客户端在同一个原生渲染器测试中不能显示本地记忆标签；这只是旧 API 不兼容的差分证据，不是签名 Desktop 的故障复现。新实现不是导出冻结 JS 的空 TS 包装，也没有增加整包忽略项或错误基线。

### 已完成的源码和行为修复

- memory-panel 现在有显式 Host/Client TS 工程、声明导出、原生 clientBundle 和真实 build。原生 RPC 发布七项操作，设置标签经官方模块表与渲染器装配；不再依赖旧 `/memory/api/*` 或必须存在的 WebServer。它是给人浏览、搜索和创建 Markdown 的可选面板，不调用模型、不注入上下文，也不替代灵枢等模型记忆系统。
- 保留 `knowledge/*.md`、`notes/*.md` 布局；根目录依次取配置、启动快照的 `DSH_MEMORY_ROOT`、`DSH_HOME/memory`，必须是绝对 Host 路径，不能回落到真实用户 home。新笔记使用唯一文件名和排他创建，同秒同标题不覆盖；完整 UTF-8 字节数受限，坏编码、越界 id、链接文件和链接目录均拒绝。读取普通文件的句柄，未提交写入取消时清理新文件，卸载等待本实例文件调用结束；不声称抵御并发进程恶意替换路径祖先。
- 界面使用原生 locale 字典，保存后刷新计数和列表，知识页/笔记显示为文本而非 HTML，卸载清理标签、字典、样式和 RPC。浏览器测试执行重新构建的工厂，使用真实原生渲染器、codec 及文件支持的载体 fixture；不是只检查注册，也不是已安装 Desktop 的 GUI 验收。
- 生成服务/配置/Client/包目录和服务关系图，同步中文对侧及配对记录。两份旧 smoke 与归档 SHA-256 一致后用补丁移除；归档可恢复，用户 Markdown、真实 profile 和会话不在删除目标内。工作方法及具体对话同步到源码、管理仓和 `F:\tools` 的 AGENTS.md，按规则压缩 root 记录而未提高字数上限。

### 本批复验

原始日志及保护读回在 `F:\tools\dsh-retired-20261001\memory-panel-repair`；失败日志保留，后续同名最终日志不覆盖首次失败证据。

| 检查 | 结果与证据范围 |
|---|---|
| 新面板定向回归 | **3 文件、5/5**；实际 Loader 重载、同标题持久化、坏路径/链接/编码/分页/大小/取消拒绝，原生 Host Gateway 七项调用及坏参数，实际浏览器工厂保存/刷新/中文/HTML 文本化/卸载，原生 CLI 在临时 profile 中 add/remove |
| 组合回归 | **15 文件、38/38**；包含此前 backup、皮肤、通知和服务目录分区；最终面板另在正常 minify 配置重新构建后复测 5/5，不是模型提供方或 Desktop 激活验收 |
| 严格类型及重点 lint | Host/Client 聚合检查通过；相关 **12 文件、0 错误、0 警告**。文档首轮新增 Gateway 测试的可选 signal 类型失败，已修正，不把仅 Vitest 通过当作类型通过 |
| 完整文档门禁 | 最终 **43/43**，171.46 秒；首次 **40/43** 的链接配对、root AGENTS 字数和测试类型失败均保留证据并修复，再整套重跑通过，见 `doc-sync-final.log` |
| 自用构建 | 面板实际 build 通过；完整 `build:selfuse` 现停止于 `@dsh-selfuse/soul-md` 缺少 build，不再停止于 memory-panel |
| 卫生门禁 | **15/18**；依赖检查定位到 undo 缺少 `src/index.ts`，工程约束定位到 soul-md 缺少 tsconfig，Cordis 配置定位到 undo 缺少源码别名 |
| 全仓 lint | **5200 文件、168 错误、0 警告**；仍未通过，不能用新包重点 lint 全绿替代 |
| 管理仓与空白检查 | manifest draft-07 验证通过，管理仓和面板 authored 源码/双语说明的 diff 空白检查通过；源码仓全量 diff 仍因新生成 Client bundle 内 Zod 模板字符串的四处尾随空白失败。未手改这些字符串或放宽 Git 规则；尝试 minifier target 不解决后恢复正常配置 |
| 真实 Desktop 保护 | 两份 profile 文件 SHA-256 与基线相同，lockfile 仍不存在；没有安装候选插件、重启进程或改会话。该对比不等于审计所有用户文件 |

### 剩余工作与发布状态

1. 为保留的 undo、soul-md 恢复真实源码、原生 API 与严格可重建工程，再复跑自用构建和卫生门禁；不能靠假入口、删除功能或绕过校验完成。
2. 修复剩余全仓 lint 与生成 Client bundle 的字符串输出/空白问题；必须保持运行语义、准确 source map 和生成器可复现，不直接删第三方模板字符串里的空白。
3. 全部要求的门禁通过后再独立做 Windows 和已安装 Desktop 插件验收，再考虑发布及管理仓 pin 同步。源码完成、隔离 Linux/jsdom 通过和签名 Desktop 激活是不同状态。

本批没有提交、推送、更新管理仓子模块 pin 或恢复远程服务。旧管理仓 `plugins/dsh-memory-panel` 仍是历史副本，不能拿来覆盖正式 Desktop；新实现当前只在 WSL 候选源码中。该面板不涉及模型请求或服务商安全机制的规避。

## 2026-10-02 完成全部任务：进行中

用户要求“完全全部任务”，后明确批准归档 undo、保留 backup 与原生恢复，并批准将官方 `defineTool` 列为必须共享 tools 实例的 peer 导出。后者只是补全依赖策略分类，不添加安全豁免或复制官方运行实例。

undo 已完整归档到 `/home/huangzy/tools/dsh-retired-20261001/undo-retirement/undo`，36 个文件/链接记录、869861 字节复核一致；用户快照不在操作目标。Soul 已迁为真实严格 TS、原生配置与生命周期受控监听，缺失文件才用 fallback；坏编码或超限不会替换最后有效内容。实际官方 CLI 临时 profile 安装/移除、Soul 三项运行回归、无密钥 authored 会话持久化刷新和回放通过。它们不证明模型提供方或已安装 Desktop 验收。

生成浏览器 bundle 的字符串空白由 esbuild 编译输出保留运行语义并组合 source map，不手删模板内容。当前曾通过 root build、build:selfuse、5207 文件 lint 0 错误/0 警告、定向 61/61 与维护脚本 17/17；这些检查之后又增加共享 mount 工具和修复，必须最终固定状态再跑。全量单元测试首轮 32 个失败，另两份测试加载失败；文档 41/43、卫生 16/18、重复检查 11 项。原始日志在 `F:\tools\dsh-retired-20261001\completion-final`，失败不覆盖；当前继续修复，不能称门禁完成。

已复核真实 Desktop 两份 profile 文件哈希与保护基线一致、lockfile 仍不存在；程序正运行，未写正式 profile、重启、改会话或恢复远程服务。未提交、推送、更新子模块 pin；Windows 实际插件验收与发布仍待完整检查通过。

### 02:20 后续验收：源码与安装版分开记录

前文数值属于本轮早期快照。后续先定位全量失败：按执行世界装配 Windows/Linux 路径、GIO 和原生打开程序的 fixture；更新唯一的侧栏标题预期；桌面 flock 构建仅探测当前 libc 的实际 addon。重复代码改为有实际消费者的局部共享实现。检验产物的 expected/snapshot 不再与会清空 CLI 产物的重建并行；不提高超时或删断言来掩盖竞争。

安装版探针发现 Soul 的 `Config.required()` 与安装补丁中缺省的 config 矛盾；新增加载缺省条目的回归先失败，再改为 `default({}).volatile()`。严格构建和 5 项 Loader/CLI 回归通过。两份 inspect 回放 fixture 曾将真实事件 `cordis/inspect-query` 误改成 npm 命名空间；恢复生产事件名，并补齐 rescope 的精确消费者名单和正反例，55 项相关测试通过。全量构建产物回放末次通过，未重录失败输出来掩盖不匹配。

| 检查 | 已执行结果与边界 |
|---|---|
| 全量单元测试 | 1899 文件通过、19 文件跳过；39178 项通过、1 项预期失败、236 项跳过，558.46 秒。其后的 Soul 和 rescope 改动另通过定向回归，不宣称完整覆盖率或 CI 平台矩阵通过 |
| root/selfuse 构建 | 两者通过，root 生成 357 个 client artifacts；Soul 缺省配置修复后单独严格重建通过 |
| 全仓 lint | 5208 文件、0 错误、0 警告；最新 `lint-final-5.json` 中 diagnostics 为空 |
| 重复代码 | 2418 文件扫描，0 clones；见 `duplication-2.log` |
| 文档门禁 | 43/43，最新 `doc-sync-final-7.log`，118.90 秒 |
| built expected output | 18 文件、108/108；最初失败由与 CLI 重建并行造成，产物稳定后整套通过，不更改断言 |
| built Session snapshot | 8 文件、188 通过、2 跳过，109.39 秒；首轮缺少匹配的 Playwright Chromium，装齐测试浏览器后整套通过 |
| 审批/Issue/模块图 | 审批 80 项、Issue 51 项通过；模块图 3 份产物为最新。不是 GitHub 发布或审核通过 |
| 卫生门禁 | 最新 17/18；只剩 `mountOnce` 两处未分类，等待人工确认，不擅自放宽依赖策略 |
| 客户端分层 | 补查发现 82 项违规，涉及官方 conversation、account、browser、documentpreview、workspace；原始 `client-domain-graph-final.log` 保留。该检查属于 check-all，不能省略或以其他全绿替代 |
| 已安装 Windows Host | 官方随包 CLI 在隔离 F 盘 profile 添加本地包；11 个层、0 skipped bundles，9 个保留 Host 条目实际 ACTIVE。Git 原生 shell 状态/限量历史/完整分支名、记忆写入读回与路径拒绝、Windows tar 备份/校验/恢复预览及 Host 释放通过 |

Windows 验收直接使用签名安装目录的 Electron Node、官方 CLI 和 ASAR Host，没有替换官方程序、共享 WSL node_modules 或改真实 Desktop profile。`link:` 不自动安装链接包的依赖，探针把包放在临时 profile 内并显式安装 Windows 依赖。GUI 界面、通知实际送达、GitHub 真实认证/推送和模型提供方调用未验收；风险插件的激活不是绕过提供方规则的证明。

Windows Git 探针最初使用了父进程工作区，然后改为临时工作区；两次都因权限不足失败关闭。F 盘继承给当前用户 Modify 而非 FullControl。官方 ACL 沙箱同时修改 DACL 和完整性标签，后者要求 `WRITE_OWNER`，参见 [Microsoft SECURITY_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/secauthz/security-information)。仅向本轮拥有的临时 workspace 授予当前用户 FullControl 后，原 `workspace-write` 下的 Git 调用通过；没有改成 danger-full-access、加无沙箱回退或修补真实 F 盘权限。Windows PowerShell fixture 还须从自身 PSHOME 加载原生 Security 模块，避免继承 PowerShell 7 的模块搜索路径造成 autoload 失败。失败和最终日志分别保留，最终是 `windows-native-host-all-8.*.log` 和对应临时 home 的 `acceptance-results.json`。

真实 Desktop 始终是 10 月 1 日 22:30 启动的同一批进程。00:35 实际 cordis.patch.yml 被运行程序或用户改变，作者未知；其新哈希已读回并保留，不能继续说两份文件均与最早基线一致。package.json 哈希未变，lockfile 不存在。本轮没有写正式 profile、安装候选插件、重启程序、改会话或恢复远程入口；保护证据在 `desktop-protection-20261002-0110.json`，后续只读读回仍一致于新状态。

下一步仍是处理未分类导出的人工确认与 82 项客户端分层错误，按真实职责调整模块后重跑所有受影响检查；全部要求通过才提交 fork、同步管理仓 pin 和配置方法。正式 profile 安装/GUI 验收须先确认桌面正常退出。当前没有提交、推送或更新子模块 pin，不能把本轮进展称为全部任务完成。

### 11:50 后续：客户端分层与嵌套构建

82 项客户端分层问题已处理，原失败日志保留。InputBar、上下文用量表和控件行测量归输入模块；浏览器的共享导航、持久化和 tab 状态下沉到 Client 根目录，页面/呈现接口归 `contract/`，iframe 与 Electron 各自实现。文档预览共享注册表、资源成员、tab 生命周期、行导航和缩放控件不再冒充独立格式域；Office 不导入 PDF 实现，由根入口显式组合。共享行/弹窗样式与工作区行和操作分别解耦。未添加绕行 re-export 或关闭分层检查；归档 Agent Notes 保持冻结。

分层检查改用 TypeScript 语法树，覆盖普通、类型、副作用、动态和 import-equals 导入，避免把注释当依赖。仅根 `assets/` 下真实存在的 PNG/SVG 属于共享图片；缺失图片、CSS、JS/TS 和其他域中的图片仍按原规则检查。回归先有 6 项失败，修复后 29/29；全仓分层检查通过。Client 聚合类型检查通过，GUI 单元 597 文件、9518 通过、1 跳过，206.29 秒；它们不是 Windows 正式 GUI 验收。

首次 `DSH_SNAPSHOT=replay pnpm run test:web` 在 selfuse 构建处失败：官方外层脚本使用 npm，原自用构建却向 npm 传 pnpm 的 `--filter`。修复为在每个包目录执行 `run`，并遍历私有依赖和 peer 的构建顺序，拒绝 peer 环。三个新回归先失败，修复后连同分层/启动参数共 43/43；真实 `npm run build:selfuse` 重建全部 10 包通过。第二次完整 Web 链路已成功构建 357 个 client artifacts，浏览器回放及全量单元复跑仍在进行。

新一轮卫生检查为 16/18：共享 `mountOnce` 分类仍待人工确认；另发现引导字典移出 `locales/` 后不再被本地化检查识别。后者需将共享字典合入其真正的 locale 所有者，不能新增排除项。最新 lint/重复检查曾分别通过 5208 文件 0/0 与 2418 文件 0 clones；构建工具随后修改，仍需复核最终状态。根 AGENTS 曾超字数，按原预算压缩维护记录后通过，没有提高上限。

11:44 只读读回正式 Desktop：仍为 10 月 1 日 22:30 同一批进程，package.json 与已记录哈希一致，patch 与 00:35 新哈希一致，lockfile 不存在。F 盘重定向日志属于更早的实例，不能拿来证明当前实例的更新检查次数。未安装候选包、改会话、重启或回写设置；人工分类、全套检查、正式 Desktop 验收与云端同步仍未完成。

后续全量单元复跑为 1899 文件通过、19 跳过，39211 项通过、1 项预期失败、236 跳过，652.93 秒，见 `unit-layering-final.log`。该结果之后才合并 locale 所有者：账号/引导与预览/缩放文案分别归本包的根 `locales.ts`，没有扩充 i18n 排除项；合并前后实际导入比对 6 字典/242 键值完全相同，见 `locale-values-green.json`。客户端本地化和分层检查均通过；合并后的 GUI、类型/lint 仍在复跑，不能把此前完整单元数值称为最终冻结状态验收。

### 12:30 后续：人工 peer 分类与浏览器环境复核

用户单独批准“允许列为共享 peer 导出”，对应 `@dsh-selfuse/plugin-mount#mountOnce`，不扩大之前对 `defineTool` 的授权。两个分类均是共享实例约束，未加入 duplicate-safe 或安全豁免。先增加分类与两个消费者声明回归，原状态有 2 项失败；分类完成后检查器进一步报告 38 项 manifest 问题。官方修复器按既有策略修正 backup、memory-panel、skin-center、web-ui-git-graph 四份声明：共享 Cordis/tools/mount 保留匹配的 peer/dev；Client-only 导入只在 dev；可独立复制的协议/schema 才为正常 runtime dependency；私有辅助包范围为 `workspace:~`。没有新增第三方版本、包角色排除或其他导出分类。最终依赖策略和 48 项回归通过，锁文件同步。

字典合并后的 GUI 597 文件/9518 项通过、1 跳过，251.41 秒；类型检查通过，lint 5206 文件/0 diagnostics，重复检查 2416 文件/0 clones。完整文档首轮 42/43，唯一失败是文件迁移后客户端生成目录过期；已经生成并单独验证，仍需最终完整复检。

完整 Web 回放首次为 157 文件通过、6 失败、2 跳过，591 项通过、5 失败、22 跳过。两类环境问题不能算源码缺陷：WebKit 的测试版本及系统依赖缺失，补装后实际启动、推理选项与会话恢复通过；补装的字体也使中文 Office 转换完整通过。其余三个布局失败稳定复现后，以 CDP 实际字体及尺寸验证：旧 Chromium cache-11 未发现新装的 Liberation 字体，代码被错误选择为非等宽 DejaVu Sans；系统 `fc-cache` 生成 cache-9，不能刷新 Chromium 的私有格式。隔离 `XDG_CACHE_HOME` 并保持真实 `PLAYWRIGHT_BROWSERS_PATH` 后，实际字体恢复 Liberation Sans/Mono，三个原断言 19/19 通过。没有改 UI 样式、源代码样本、断言条件或金色回放。测试增加尺寸诊断以保留具体失败上下文。旧缓存未删除，环境对照日志保留。

一次定向命令错误地使用额外 `--`，导致 Vitest 忽略路径筛选并重复跑全套；已保存列表与日志、停止该自有测试进程，退出 130，不当作验收通过。随后不带多余分隔符的定向检查只执行指定 3 个文件并通过。

用户回复“已退出”，只读确认正式 Desktop 进程为 0；package/patch 哈希与最新保护状态一致，lockfile 不存在。尚未安装候选插件、改会话或更新云端 pin。正在固定最终产物并完整复检；此前和构建并行的卫生检查虽为 18/18，仍需产物稳定后重跑，不能当作最终冻结验收。

### 12:50 后续：串行总门禁与可重建 Desktop 安装方法

固定产物后运行原生 `check:all`，71 项门禁、单一调度 worker；单元测试保留四个执行 worker，快照只并行其允许的案例，不重建与读取同时进行。全量单元阶段通过（602.91 秒），源码构建阶段通过（37.13 秒），后续门禁尚在运行；不提前写全量通过或发布。

管理仓新增 `scripts/install-desktop-plugins.mjs` 及真实 Electron Node 模式的八项测试，全部通过；只读预检实际退出码为 0，十个候选包均有构建入口。默认不安装，显式 `--apply` 才复制新 F 盘版本目录、设置仅当前用户/管理员/系统可读写的 ACL、逐项备份并哈希核对 profile 文件，再通过官方随包 CLI 安装。用户 patch 正文和注释保留，普通插件只补缺少的 task-notify/privacy 两行，已有禁用选择不改；不复制 WSL node_modules、不改会话或旧预设。安装日志和备份不入云端。CLI 组合、实际 Host、图形和模型验收分别记录，不能相互替代。

第一次直接用 PowerShell `&` 调用 GUI 子系统的 Electron 时返回过早，未据此认定测试或预检成功；改为 `Start-Process -WindowStyle Hidden -Wait -PassThru`，读取真实进程退出码与文件日志。独立进程入口另有测试，防止无输出的假成功。详细安装及回退方法在 `scripts/README.md`。本节记录时仍未对正式 Desktop 执行安装或发布。

### 13:10 后续：总门禁通过与最后浏览器准备请求修复

串行 `check:all` 最终 71 passed、0 failed、0 skipped，1144.59 秒，见 `completion-final/check-all-peer-final.log`。它覆盖完整单元、构建、会话快照、期望输出、18 项卫生和全部文档检查；不是完整覆盖率或跨系统 CI 矩阵的声明。该冻结状态的 Windows 隔离 profile 用官方随包 CLI 安装十个包，11 层/0 skipped，九个 Host 条目为 ACTIVE；原生 Git status/log/branch、Markdown 保存读取及路径拒绝、Windows tar 备份/校验/恢复预览、完整 dispose 全通过，见 `windows-native-host-all-9` 和 `windows-profile-3QYj6w/acceptance-results.json`。没有真实模型或正式 GUI 操作。

安装器第一次隔离实装在 pnpm 打印 Done 后超时，并留下两个明确属于私有 fixture 的子进程；先核对其完整命令和 PID 后终止，未强杀用户 Desktop。原因是非交互调用保留了开放的 stdin。关闭输入后实装退出 0；进一步改用官方随包 execa 的 stdin ignore/killDescendants，实现取消后等待进程树退出。十项测试包括实际子进程 EOF、可观察子进程就绪后取消、等待后 ESRCH；最终隔离实装十包/11 层通过，受限 ACL 和 `_profile-before` 哈希备份保留。第一次失败材料不删，不提高超时掩盖问题。正式 profile 尚未安装。

完整浏览器 CI lane 按官方次序串行两类 HMR 所有者、再三个 worker 跑剩余 163 文件：160 文件通过、1 个 suite setup 失败、2 跳过，592 项通过/19 跳过（不含前两串行文件）；首次退出 1。唯一剩余失败是 remote-welcome 的准备 token 交换在 Node 中访问 `remote.localhost` 报 ENOTFOUND；Chromium 能自行解析该地址，Node 无此保证。修正 scaffold 的准备交换也使用实际 127.0.0.1 监听，浏览器继续原 remote authority，并新增页面地址断言。定向 remote-welcome/public-mount 三项通过；权限/欢迎语与金色断言未改。共享测试 fixture 和维护 AGENTS 的后续修改需复核相应检查，完整浏览器即将最终复跑；不将首轮失败称为通过，也不恢复已退役的远程入口。

### 13:30 后续：完整浏览器通过、正式 CLI 安装与原生启动

最终官方浏览器 lane 退出 0：前两串行文件各自通过，剩余 163 文件为 161 passed/2 skipped、593 passed/18 skipped，607.04 秒，见 `web-ci-authority-final.log`。跳过项为原仓平台/真实提供方条件，未新增排除或跳过。完整 lint 首次又指出新 peer 回归里的四处 JSON any 访问；改为 unknown 和相同字段断言（runtime dependency 要求无此键更严格），76 项相关回归通过，5206 文件全仓 lint 0 warnings/0 errors，79.1 秒，见 `peer-lint-green.log`、`lint-contracts-authority-final-2.log`。误用默认 lint 触发了无源码变化的 Host 重建，已终止重复调用（143，不记作成功）；随后纯检查入口通过，十个保留包的每份 lib 文件与隔离实装逐个哈希相同。

确认正式 Desktop 仍退出、两份 profile 哈希与最新保护状态一致后，执行已隔离实装验收的官方 CLI 安装器。十包安装退出 0，原五个官方 bundle 保留，新增六个自用 bundle，共 11 层/0 skipped；普通 notice/privacy 只补缺少行。正式产物和恢复备份在 `F:\Apps\DeepSeekHarnessPlugins\selfuse-20261002-rc2-final`，文件权限只给当前用户/管理员/系统；每个原配置文件已备份并哈希核对，旧模型/权限/预设正文、注释、会话和用户数据没有改写。CLI 会生成独立 pnpm lock；这不是重装官方程序或复制 WSL node_modules。

13:28:29 以官方程序、F 盘工作目录、持久受限日志启动正式 Desktop，主 PID 32016；13:29 读回五个进程、stderr 0 字节、一次初始更新检查，未检测到 EPIPE 或插件启动失败。本次运行日志在部署目录 `_runtime`，不能用较早实例的日志替代。尚未具备可用 GUI 自动控制工具，已请用户确认界面和三个面板；未把进程/CLI 组合、隔离 Host 或浏览器 fixture 当正式图形/模型验收。

另将仅有 source map 指向同目录真实 TS 的 32 份未跟踪 Loader 编译输出可恢复移动到 `/home/huangzy/tools/dsh-retired-20261001/vendor-loader-emitted-20261002`，共 90026 字节，逐个哈希一致，源码/数据不删。移出后四项真实 Loader/profile 组合及客户端分层复检通过；清理不会被用来略过真实源码测试或将污染产物提交云端。源码发布、管理仓 pin 更新和远端读回仍待完成。

### 正式界面负例：外置 link 目录的依赖未连接

用户验收反馈“能打开，但我没在设置里看见什么记忆备份皮肤面板”。通过当前实例的认证 loopback 只读读取 pluginInventory/list 和页面 boot graph：backup、memory-panel、web-ui-git-graph、skin-center、content-risk-guard 五项 enabled，但 fiberPhase 为 null；Client 71 行只含一个 selfuse 布局适配。正式 GUI 未通过，发布继续停止；运行中未写用户配置。此前实际 Host 测试把产物放在 profile/artifacts，与正式 F 盘外置安装的查找路径不同，不能复用其成功结论。

在安装器第三轮隔离实装目录，使用正式 Electron 的 --expose-internals 和真实 ASAR runProfile 复现同五项导入失败，分别明确缺少 schemastery、plugin-mount；见 linked-runtime-baseline2.*。整目录 node_modules junction 仍不能解析其中的相对 link，原失败见 linked-runtime-junction.*。修复使用独立部署项目的显式安装版 peer 声明，以及非官方辅助包、jpeg-js、lightningcss 的逐包绝对 junction；只利用官方 linked-package resolver，不复制 WSL 依赖或官方 ASAR，也不放宽包依赖策略。修后隔离九个 Host 均 ACTIVE，五个自用 Client 进入 boot graph，退出 0，见 linked-runtime-project.*；正常 Host shutdown 完成。正式实例尚未补连接，已请用户正常退出；Client 实际图形/调用与云端同步仍待验收。

安装器新增三个外置依赖回归，合计 13/13 通过；缺失 helper、native 依赖、越界名称与已有部署清单均拒绝。新增 verify-desktop-plugins 只向认证 loopback 读取 inventory 和页面/资源，区分 ACTIVE 与仅 enabled，拒绝缺少 Client、异源 URL 和不相关 RPC 回包；默认九个 Host、五个 Client 都须通过，不覆盖用户禁用选择。实际修复后的隔离 Host 与 bundle GET 已由该脚本验收。

真实 Windows Chrome 的独立无界面浏览器加载的是官方 ASAR Host 的客户端组合，不驱动用户正在运行的 Desktop。最初遇到原生引导弹窗及把“内置插件”错当“插件”的测试定位错误，保留 browser2–6 的失败；browser7 三个面板渲染通过，browser8–9 的人工测试代码误读 notes/文档字段，按真实声明改正。最终 browser10 退出 0，pageerror 为 0，皮肤中心与皮肤目录、备份总览和归档列表、记忆存储均实际渲染；原生“内置插件”页签为 插件列表/备份/记忆。浏览器保存 CANARY 本地条目后，Host 使用 notes.items 和 note.note.content 读回确认落盘，未调用模型或修改真实用户记忆。截图/ARIA、正反例日志均在 completion-final；正式 GUI 仍未通过，不能把隔离图形证据冒充用户实例。

根 AGENTS 新记录曾超过 2300 字预算；将阶段记录压缩并指向本维护记录，规则和事实保留，不提高预算，八份预算文档复检通过。正式进程 PID 32016 及子进程仍在运行，未强制退出；等待正常退出后补依赖连接，再重启、运行只读验证及请用户验收。源码和管理仓不发布。

收尾冻结回归为 18/18（安装器 13、只读验收 5），退出 0；实际隔离 Host 的最新 RPC 回包关联验证同样退出 0。文档快速检查 21 passed/0 failed/0 skipped，manifest schema 和双仓 diff whitespace 检查通过。已准备只补现有正式产物依赖的私有修复脚本，先检查 Desktop 停止，再逐项备份五份配置、补连接并保证这五份配置哈希不变；运行中拒绝的真实负例退出 1，未创建修复备份目录、未写正式 profile。该拒绝是保护测试，不是正式修复通过。正常退出、应用修复、正式面板验收、Git 发布和远端读回仍未完成。

### 等待正常退出期间的发布范围复核

只读复查正式五个进程仍为 PID 32016 及原子进程，部署根尚无依赖连接用的 package.json；没有强制关闭、应用修复或写真实配置。此前请求用户正常退出仍未收到回复。继续核对待发布内容，未重复重建产物或把等待当作正式验收成功。

对两仓相对 HEAD 的存续改动及未忽略新文件做只读候选扫描：源码 464 个文件、7776607 字节，管理仓 17 个文件（文档后续调整后以最终私有报告为准）。没有匹配私有日志、凭据、会话或本轮证据目录的路径，也没有符号链接或二进制扫描跳过。源码四项、管理仓一项规则命中，逐项复核为 URL 拒绝用例、PDF 口令提示翻译、备份的运行时 cfg.token 模板及验收器拒绝 URL 的用例；不打印凭据值。它是有限签名的启发式复核，不等于完整 secrets 审计或全部仓库内容安全证明。报告只放在 checkout 外的 completion-final，不入库。

首次扫描误用 WSL Git 读取 Windows worktree 的 Windows-native gitdir 而失败；随后核实 Windows Git 位于 D 盘，管理仓改用其原生 Git，源码仍用 WSL Git，再完整扫描成功。没有更改 worktree 指针、索引或凭据。更正 manifest 中 memory/backup 的“未安装”旧说法和 WSL settings/preset 的当前部署误导，更新历史精简名单中已退役的 undo、PLAN 的门禁状态，并补充实际面板位置：备份/记忆在设置 → 内置插件，皮肤在设置 → 皮肤中心。原始阶段记录保留，不把旧状态重写成新验收结果。

正式应用、重启、当前 Host/Client 只读验证、人类图形验收、双仓提交/push/pin 更新和远端读回仍未完成。只在正常退出后执行受保护的正式依赖修复，已通过的源码门禁不能替代这一项。

### 正式依赖连接完成，原生默认目录回归仍失败

后续只读检查发现 Desktop 进程已经为零，不沿用先前运行状态，也未强杀用户进程。执行 checkout 外的 formal-runtime-dependencies-repair.mjs，先备份并核验 package.json、cordis.yml、cordis.patch.yml、pnpm-lock.yaml、pnpm-workspace.yaml，再调用安装器公开的 connectRuntimeDependencies。实际退出 0，五份正式 profile 文件 SHA-256 均不变，连接声明只写入本次 F 盘部署目录；会话、模型、权限和用户选择未改。

以持久文件重定向启动新的正式实例，主 PID 23648，使用新的 desktop-dependencies-fixed 日志，stderr 为 0 字节、更新检查未见 EPIPE。只读 verify-desktop-plugins 实际退出 1：memory-panel 的 fiberPhase 为 failed，验收器在该项停止，不能据此宣称其他条目或正式图形界面全部通过。启动无异常文本不等于插件激活成功。

memory-panel 当前默认目录只从 config.root、DSH_MEMORY_ROOT 或 DSH_HOME 取得；官方 Desktop 无 DSH_HOME 覆盖时不应依赖该环境变量。新增真实 Loader 回归，fixture 提供仅指向临时目录的原生 dshHomePath 能力，并移除 DSH_HOME：1 failed/3 passed，错误为 Set an absolute memory root or launch with DSH_HOME。证据为 completion-final/memory-native-home-red.log；产品代码尚未修改，既有完整门禁不能充作这一新回归通过。正式验收、双仓提交及远端同步仍未完成。

### 用户询问上游插件能否直接安装

用户问“你看看 GitHub 这个插件的上游仓库能不能直接装下来”，未给具体链接，暂按之前的 FuRongJun-1999/dsh-memory（灵枢）调查，不据此替换正式插件。只读 GitHub API 得到 main 提交 d5a6a511962a14f4260ed0ce0f42e402e352eb2c；npm latest 为 0.7.0，发布日期 2026-10-01，发布对应 gitHead 为 bfbdcb923da1ef2880dd3f9f979cf419d9211eb0。网页缓存先返回旧 0.6.0，最终版本以现场 API 与发布清单核对为准。

上游声明原生 DSH bundle 和 Node ≥22.19，可通过官方 CLI 安装发布包；Git 仓库未跟踪 lib，需要构建，优先固定 npm 发布版而不是浮动 main。其 DSH peer 范围与 rc.2 的原生 prerelease 匹配规则不冲突，但这不是当前正式桌面运行测试。灵枢是自动召回/落盘系统，不等价于本地供人浏览的 memory-panel；持久写入还受本地凭据和写入判定约束。发布版本与 main 的 hooks.ts 字节相同，都没有原 selfuse 补丁中的代理 URI、带凭据 URL、代理 YAML 整段拒绝及回忆预览过滤。未执行上游构建脚本、未安装到正式 profile，也不宣称保持了原隐私隔离或已经兼容验收。来源：[上游固定版本](https://github.com/FuRongJun-1999/dsh-memory/tree/bfbdcb923da1ef2880dd3f9f979cf419d9211eb0)、[npm 发布清单](https://registry.npmjs.org/@furongjun1999/dsh-memory/0.7.0)。

### 原生 Harness 用户目录修复与 Windows 无覆盖验收

按“完成所有修复”继续，重新执行 memory-panel 的真实 Loader 回归，仍为 1 failed/3 passed。源码随后仅在缺少显式 root、DSH_MEMORY_ROOT 和 DSH_HOME 时调用原生启动器已提供的 dshHomePath('memory')；使用严格 ctx.get 读取可选能力，不自行调用系统 home、不强制用户设置环境变量、不新增运行时 home 库。补类型导入、开发依赖和 Host 工程引用；显式目录优先级不变，相对目录和缺少隔离路径的临时上下文仍拒绝。

构建及相关三文件回归为 11 passed，包括原生 CLI 添加/移除、实际 Client 保存和九项 Loader/Gateway/路径行为。依赖锁由现有 pnpm 生成，双语 README 与配对记录同步；未删失败回归或修改断言来掩盖错误。现场 fetch 首次因 GnuTLS -110 失败，使用 HTTP/1.1 重试成功，官方 master 仍是当前 rc.2 发布提交；没有合并未经验证的新版本。

Windows 隔离验收沿用真实 ASAR runProfile 和外置目录，先备份隔离 memory-panel 产物，再只更新该 fixture 的包。使用新建临时 USERPROFILE 隔离原生默认用户目录，进程环境与 launch snapshot 均移除 DSH_HOME/DSH_MEMORY_ROOT，实际 memoryPanel.status().store 与临时 .dsh/memory 一致。九个 Host ACTIVE、五个 Client 的认证资源验收通过。首轮 Chrome 继承临时 USERPROFILE，启动提示 DevTools remote debugging requires a non-default data directory，进程退出 1；该环境差分失败保留为 memory-native-home-windows.*。只将浏览器环境恢复成原启动环境后，第二轮退出 0，三个面板实际渲染，记忆浏览器保存并经 Host 文件内容读回，pageerror 为空；证据为 memory-native-home-windows-2.* 和独立 native-home-acceptance 目录。没有驱动用户的正式 Desktop 或调用模型。

正式主 PID 23648 与四个子进程仍在，未覆盖其产物、会话或配置；已请用户正常退出。下一步为相关完整门禁复查、受保护的正式包更新、新实例 Host/Client 验证、实际正式面板验收及双仓云端同步。此前 71 项全量结果是最新修复前的证据，不把它或隔离图形测试当作正式最终验收。

## 2026-10-03 正式记忆更新与面板反馈

前轮相关检查最终结果补录：首轮 doc-sync 因 Config JSDoc 改变而拒绝旧 catalog，使用原生成器更新目录；第二轮 doc-sync 43 passed/0 failed（116.82 秒）、hygiene 18 passed/0 failed（28.29 秒），lint 仍指出测试中 asymmetric matcher 的 any 赋值。改为有类型的 note 内容断言后，11 项回归再次通过，全仓 lint 5206 文件、0 warnings/0 errors（50.3 秒），git diff --check 通过。保留 release-gates、release-gates-2 和 lint-final 三份失败/成功证据，不把未执行的链式后续命令报为成功。

旧正式实例只读完整 inventory 后续另证实八个 Host 激活、memory-panel failed，五个 Client 已进入页面 graph；同一实例七次更新检查未见 EPIPE。正式更新器在仍运行时真实拒绝，更新目录没有创建，不强杀程序。

用户 2026-10-03 回复“已退出”，新进程检查为零。checkout 外受保护的 formal-memory-native-home-update.mjs 先核对安装身份、运行依赖名/配置行不变、新 lib 与实际 Windows 已验收 fixture 每份哈希相同，再备份五份 profile 文件、复制候选并原子换名；旧包逐文件哈希仍相同，应用退出 0、stderr 0 字节。恢复目录为 F:\Apps\DeepSeekHarnessPlugins\selfuse-20261002-rc2-final\_memory-native-home-20261002\before-package；applied.json 记录 applied true/profileChanged false。五份 profile 文件和部署根 manifest 的哈希均未变化，用户设置、模型、权限、会话与官方签名二进制不改。

本轮前两次启动退出 0，stdout/stderr 均为空，验收器明确失败 No authenticated local URL；不能报作启动成功。环境清理曾调用 [Environment]::SetEnvironmentVariable(name, $null, 'Process')，实际 PowerShell 保留空环境项。使用无业务含义的临时变量差分，null setter 后 Test-Path Env 为 true、长度 0，Remove-Item 后项不存在；改用真正移除 ELECTRON_RUN_AS_NODE 后，正式主 PID 32384 和四个子进程启动，stderr 0 字节，官方 Authenticode 为 Valid。失败日志保留，不修改安装包或用户全局环境。

当前实例日志 desktop-memory-native-home-20261003.stdout.log 经 verify-desktop-plugins --log 验收退出 0：九个 Host 均 active，五个 selfuse Client 行各唯一、工厂资源 HTTP 200，RPC id 匹配本次请求。该检查只做当前认证 loopback 的只读请求，不调用模型或写入记忆；证据为 completion-final/formal-memory-native-home-verified-20261003.*。此前初次启动日志不能代替本次证据。

用户反馈“有皮肤中心，没有备份和记忆”，因此先维持正式 GUI 未通过，不以资源验收反驳实际界面反馈。说明备份/记忆位于设置 → 内置插件的页内标签，而非左侧菜单，并请求截图后，用户回复“有了”。据此记录用户已找到面板；未要求实际保存/恢复，不扩大为正式记忆落盘、GitHub HTTPS 备份恢复或模型对话验收。准备的独立只读浏览器探针尚未执行，收到反馈后移除，不重复打扰现用程序。

部署说明、manifest、源码与两级维护规则同步这一结果。源码和管理仓尚未提交/推送，子模块 pin 未变；相关文档复检和云端发布继续进行，不将本机修复等同远端同步。

### 发布前复检与源码远端读回

第一次本轮文档复检 test:docs 和 doc-sync 全通过，后者 43 passed/0 failed（136.34 秒），manifest schema 及管理仓空白检查通过。现场 fetch 官方 master 仍为已对齐 rc.2，fork 升级分支仍停在本地原 HEAD，管理仓 main 也没有并发移动。只读候选扫描源码 464 文件、管理仓 17 文件，没有私有运行/会话目录或链接/二进制跳过；五项签名经实际源码检查为假凭据反例、翻译文字和运行时变量模板，不输出真实凭据，也不宣称完整安全证明。

准备暂存先遇到已在 index 删除的路径不能重复 add，随后遇到忽略目录中的生成残留。保留第一次 index 备份与失败材料，只更新经复核的已跟踪路径和未忽略新文件，不 force-add、reset 或丢弃已暂存变更。完整暂存 whitespace 检出此前未跟踪的五份文件：两个 README/CSS/pkg-extract 的末尾空行，以及播放器嵌入字符串中的三条行尾空格。README 成对修正并运行配对记录器；模板空格以 x20 转义保留，修复前后实际导出的播放器页面 81698 字节、SHA-256 相同。未改产品行为、安装配置或用户数据。

最终暂存 whitespace、test:docs 通过，doc-sync 43 passed/0 failed（135.78 秒）。源码普通提交为 42d47032d3da839f088142c4b439f95128973a21；提交钩子的 25 个配对、声明生成、空白和 vendor 检查通过，暂存 lint 242 文件、0 errors/5 warnings。五条是精简规则集未启用对应全量规则的既有 disable 指令，不删除全量所需指令；全仓 lint 0/0 的前轮证据仍单独保留。提交后 464 份候选哈希逐一不变、工作树干净，不沿用未经复核的 pre-commit 状态。

普通 push 至 xsoc fork 的 upgrade/official-rc2-20260929，pre-push 的真实类型检查通过（16.59 秒），未 bypass。随后 fetch 同一远端分支，远端和本地 HEAD 均为 42d47032d3da839f088142c4b439f95128973a21，工作树干净。WSL gh 不存在、浏览器 API 与连接器查询失败后，Windows 只读 GitHub API 返回该提交 workflow_count 0、combined status pending/status_count 0；没有已报告 CI 检查，不能把这个 pending 当运行中的已验证任务或声称 CI 全绿。

管理仓此次同步包含当前 Desktop 模板、十包原生 CLI 安装器及其回归、只读 Host/Client 验收器、真实设置位置和启动环境处理方法，源码 gitlink 固定已发布提交。旧远程/控制台脚本删除保持可由 Git 历史找回；真实会话、备份、记忆、安装恢复目录、用户配置和官方签名二进制均不入提交。管理仓将普通快进发布至 main，再分别读回远端 HEAD、源码 gitlink 和方法文件；管理仓发布结果以最终验收回复为准，不用源码 fork 的成功替代。
