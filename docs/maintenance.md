# dsh-local 维护手册

## 维护原则

- 本仓是规范源；`F:\tools` 下现有运行目录是“待迁移/运行副本”。
- 每次变更组件/配置后，同步更新 `manifest.json` 与本文“维护记录”。
- 不提交：密钥、大模型二进制、node_modules、venv、日志。

## 常用操作

### 更新外部 submodule

```powershell
git submodule update --init --recursive
git -C vendor/deepseek-harness pull --rebase
git add vendor/deepseek-harness
git commit -m "chore: bump deepseek-harness fork"
```

### 新增自研插件

1. 在 `plugins/<name>/` 放源码（或 submodule）。
2. 在 `manifest.json` 增加一条 `type: plugin`。
3. 如需默认装配，更新 `config/profiles/web/package.json` 与 `cordis.patch.yml`。
4. 在本文“维护记录”追加说明。

### 修改 profile 配置

- 直接改 `config/profiles/web/package.json` / `cordis.patch.yml` / `settings.yaml`。
- 运行 `install.ps1 -DryRun` 查看同步动作；确认后执行。
- 当前线上环境未自动跟随，需要安装器同步或手动复制。

## 维护记录

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
  - 创建 `xsoc1/dsh-local`（private，无 auto_init）。
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
