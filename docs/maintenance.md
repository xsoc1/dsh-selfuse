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
