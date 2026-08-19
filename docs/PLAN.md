# dsh-local 本地代码管理方案

> 状态：**已确认方案，进入本地骨架阶段**
> 日期：2026-08-19
> 决策：
> - 仓库形态 = **双仓**（fork 源码仓 + 独立 dsh-local 管理仓）
> - 大文件策略 = **只存 manifest + 下载/导入脚本，不入库二进制**
> - 一键安装范围 = **当前机器可重建 + 新机器可部署**
> - 当前执行 = **先出方案文档与本地骨架，暂不创建 GitHub 仓库**

---

## 1. 背景与现状

本机 `F:\tools` 已积累一套可用的 dsh 自用环境：

- dsh 源码：`deepseek-harness/`（`deepseek-ai/deepseek-harness` 克隆，带本地分支 `local/image-admission`）
- 桌面封装：`Deepseek-Harness-EAC/`
- 自研插件：`dsh-image-bridge/`、`dsh-image-vision/`、`dsh-memory-panel/`、`dsh-skill-router/`、`dsh-routing-suite/`
- 第三方补丁插件：`community-plugins/`（backup、better-sidebar、git-workflow、undo-fixed、wsl-workspace 等）
- 技能：`mattpocock-skills/` + `math-research-dsh/`（已 junction 到 `~/.dsh/skills`）
- 图形控制台与看门狗：`deepseek-harness/` 根下的 PowerShell 脚本
- 本地小模型服务：`ollama/`（qwen3-vl:4b）、`image-gen/`（SDXL-Turbo）
- 用户配置：`~/.dsh/`（settings.yaml、profiles/web、agent-presets、memory、skills 等）

**痛点**：
1. 大量“代码/配置”散落在 `F:\tools` 各处，很多目录没有 Git 版本管理。
2. 管理脚本是 `deepseek-harness` 工作树里的未跟踪文件，升级/同步上游时容易丢失或脏树。
3. 配置（profile、settings、presets）只存在于 `~/.dsh`，无法在新机器快速重建。
4. 依赖关系靠人脑记忆，agent 接手时只能靠 AGENTS.md 长篇记录。

## 2. 目标

1. 把 dsh 自用环境变成**可版本化、可审计、可重装**的项目。
2. 人类与 agent 都能通过统一的 `manifest.json` + 文档 + 目录结构维护。
3. 在 GitHub 上：
   - fork `deepseek-ai/deepseek-harness` → `xsoc1/deepseek-harness`（源码仓）
   - 新建 `xsoc1/dsh-local`（管理仓，聚合个人内容）
4. 提供 `install.ps1`：
   - 当前机器：重建/修复 profile、技能 junction、脚本、服务、计划任务。
   - 新机器：安装依赖（Node/pnpm/Ollama/Python/服务）并部署完整环境。

## 3. 总体架构（双仓）

```text
GitHub
├─ xsoc1/deepseek-harness        # fork 自 deepseek-ai/deepseek-harness
│   ├─ master                    # 与上游同步
│   └─ local/image-admission     # 本地源码补丁分支（可 cherry-pick/rebase）
│
└─ xsoc1/dsh-local               # 自用管理仓（本骨架）
    ├─ vendor/deepseek-harness -> submodule: xsoc1/deepseek-harness
    ├─ vendor/deepseek-harness-eac -> submodule: xsoc1/Deepseek-Harness-EAC（可选 fork）
    ├─ vendor/mattpocock-skills -> submodule: xsoc1/skills（fork 后含本地修改）或上游+patch
    ├─ vendor/math-research-dsh -> submodule: xsoc1/math-research-dsh（已存在）
    ├─ vendor/awesome-dsh-plugin -> submodule: xsoc1/awesome-dsh-plugin（已存在）
    ├─ plugins/                  # 自研插件源码（直接入库，或各自独立仓再 submodule）
    ├─ community-plugins/        # 第三方插件（优先 fork+patch，其次 vendored）
    ├─ config/                   # 规范化配置（settings / presets / profile）
    ├─ scripts/                  # 管理脚本
    ├─ services/                 # 本地服务代码与编排
    └─ install.ps1               # 一键安装/配置
```

**为什么双仓**：
- 源码 fork 保持“接近上游”，`git pull` 干净；个人补丁集中在可管理的分支。
- dsh-local 只关心“我的东西”，体积小、易浏览、易给 agent 建立上下文。
- 两者通过 submodule 关联，安装器递归 clone 即可。

## 4. 目标目录结构

```text
dsh-local/
├─ README.md
├─ AGENTS.md
├─ LICENSE
├─ .gitignore
├─ install.ps1                 # 一键安装/配置（主入口）
├─ manifest.json               # 组件清单（机器可读，安装器/agent 使用）
├─ config/
│  ├─ settings.yaml            # 规范 ~/.dsh/settings.yaml
│  ├─ agent-presets/
│  │  ├─ router-standard/
│  │  └─ router-spec/
│  └─ profiles/
│     └─ web/
│        ├─ package.json       # 相对 link 的规范 profile
│        ├─ cordis.patch.yml
│        ├─ pnpm-workspace.yaml
│        └─ pnpm-lock.yaml
├─ scripts/
│  ├─ dsh-control.ps1
│  ├─ dsh-control-gui.ps1
│  ├─ run-dsh-web.ps1
│  ├─ dsh-watchdog.ps1
│  ├─ ensure-dsh-watchdog.ps1
│  ├─ make-dsh-icon.ps1
│  └─ README.md
├─ plugins/
│  ├─ dsh-image-bridge/
│  ├─ dsh-memory-panel/
│  ├─ dsh-skill-router/
│  ├─ dsh-image-vision/
│  ├─ dsh-routing-suite/
│  └─ README.md
├─ community-plugins/
│  ├─ dsh-backup/
│  ├─ DSH-better-sidebar/
│  ├─ dsh-plugin-git-workflow/
│  ├─ dsh-undo-plugin-fixed/
│  ├─ dsh-wsl-workspace/
│  └─ README.md
├─ skills/
│  ├─ README.md
│  └─ (submodule/vendored skills)
├─ vendor/
│  ├─ deepseek-harness/        # submodule -> xsoc1/deepseek-harness
│  ├─ deepseek-harness-eac/    # submodule -> xsoc1/Deepseek-Harness-EAC
│  ├─ mattpocock-skills/       # submodule
│  ├─ math-research-dsh/       # submodule
│  ├─ awesome-dsh-plugin/      # submodule
│  └─ README.md
├─ services/
│  ├─ image-gen/
│  │  ├─ server.py
│  │  ├─ requirements.txt
│  │  └─ start-image-gen.ps1
│  ├─ ollama/
│  │  ├─ models.manifest.json
│  │  └─ setup-ollama.ps1
│  └─ README.md
└─ docs/
   ├─ PLAN.md
   ├─ architecture.md
   ├─ maintenance.md
   ├─ adr/
   └─ agents/
```

## 5. 组件迁移清单

| 当前路径 | 目标位置 | 处理方式 |
|---|---|---|
| `F:\tools\deepseek-harness` | `vendor/deepseek-harness` | GitHub fork + submodule；本地补丁分支 `local/image-admission` |
| `F:\tools\Deepseek-Harness-EAC` | `vendor/deepseek-harness-eac` | 视需要 fork + submodule，或仅记录上游 URL |
| `F:\tools\awesome-dsh-plugin` | `vendor/awesome-dsh-plugin` | 已是 `xsoc1/awesome-dsh-plugin` fork，submodule |
| `F:\tools\mattpocock-skills` | `vendor/mattpocock-skills` | fork 到 `xsoc1/skills`（含本地去 disable-model-invocation 修改）或 vendored |
| `~/.dsh/math-research-dsh` | `vendor/math-research-dsh` | 已是 `xsoc1/math-research-dsh`，submodule |
| `F:\tools\dsh-image-bridge` | `plugins/dsh-image-bridge` | 直接入库（当前无 git） |
| `F:\tools\dsh-memory-panel` | `plugins/dsh-memory-panel` | 直接入库（当前无 git） |
| `F:\tools\dsh-skill-router` | `plugins/dsh-skill-router` | 直接入库（当前无 git） |
| `F:\tools\dsh-image-vision` | `plugins/dsh-image-vision` | 已是独立 GitHub 仓，可选 submodule 或入库 |
| `F:\tools\dsh-routing-suite` | `plugins/dsh-routing-suite` | 整理后入库或 submodule（含 injector-release + preset） |
| `F:\tools\community-plugins\*` | `community-plugins/*` | 有 git 的保留 origin，无 git 的入库；本地补丁记录为 patch |
| `F:\tools\deepseek-harness\*.ps1` | `scripts/` | 从运行目录复制为规范源；安装器负责同步到运行目录 |
| `F:\tools\image-gen` | `services/image-gen` | 代码入库；venv/hf 模型不提交 |
| `F:\tools\ollama` | `services/ollama` | 只存 manifest/脚本；模型二进制不提交 |
| `~/.dsh/settings.yaml` | `config/settings.yaml` | 规范副本（已复制） |
| `~/.dsh/profiles/web/*` | `config/profiles/web/*` | 规范副本（已复制，link 改为相对路径） |
| `~/.dsh/.agent-presets/*` | `config/agent-presets/*` | 规范副本（router-standard/spec 已复制） |

## 6. 一键安装/配置设计（install.ps1）

### 6.1 工作模式

- `.\install.ps1`：默认“当前机器重建/修复”，检测已有环境，尽量幂等。
- `.\install.ps1 -Bootstrap`：新机器完整部署（含依赖安装）。
- `.\install.ps1 -DryRun`：只打印将执行的动作，不修改。

### 6.2 主流程

1. **前置检查**
   - 检查 git、node、pnpm、PowerShell；`-Bootstrap` 时自动安装缺失项。
   - 检测 `~/.dsh`、`F:\tools` 现状，必要时先备份（调用 `dsh-backup` 或复制快照）。
2. **拉取 submodule**
   - `git submodule update --init --recursive`
   - 校验 `vendor/deepseek-harness` 的本地分支存在；缺失则提示。
3. **配置 `~/.dsh`**
   - 把 `config/settings.yaml` 写入 `~/.dsh/settings.yaml`（保留机器差异 overlay，如 Tailscale URL、端口）。
   - 把 `config/agent-presets/*` 同步到 `~/.dsh/.agent-presets/`（junction 或复制）。
   - **web profile 两种策略（推荐 junction）**：
     - 若 `~/.dsh/profiles/web` 不存在或是 junction → 直接建 junction 指向 `$RepoRoot\config\profiles\web`。
     - 若已是实体目录 → 先备份，再迁移为 junction（或复制 + 路径替换）。
   - 在 profile 内执行 `pnpm install`（依赖为相对 `link:`，可移植）。
4. **技能链接**
   - 对每个技能源（mattpocock / math-research），在 `~/.dsh/skills/<name>` 建 junction。
   - 若目标已存在非 junction，先备份再用 `-Force` 替换。
5. **环境变量**
   - `DSH_ROOT` → `$RepoRoot\vendor\deepseek-harness`
   - `OLLAMA_MODELS` → `$RepoRoot\services\ollama\models` 或本机模型缓存目录
   - `HF_HOME` → `$RepoRoot\services\image-gen\hf`
   - `OPENCODE_GO_API_KEY` 等凭据只提示/从系统凭据读取，不写入仓库。
6. **计划任务/服务**
   - 注册/更新 `dsh-watchdog`、`dsh-watchdog-ensure` 计划任务（隐藏窗口）。
   - 可选启动 Ollama（11810）与 image-gen（17821）。
7. **健康检查**
   - 检查 `http://127.0.0.1:3080`、Ollama `/health`、image-gen `/health`。
   - 输出状态汇总与下一步（重启 dsh 等）。

### 6.3 可移植性

- `config/profiles/web/package.json` 使用 `link:../../../plugins/...` 相对路径，仓库克隆到任何位置都可安装。
- 绝对路径仅出现在运行期由安装器生成的 junction/环境变量中。
- 机器相关配置（Tailscale 域名、端口、API key 环境变量名）集中在 `config/settings.yaml` 或单独的 `local.overrides.yaml`。

## 7. 实施步骤（迁移路线）

### Phase 0：本地骨架（当前）

- [x] 创建 `F:\tools\dsh-local` 骨架目录。
- [x] 复制 settings / profile / agent-presets / scripts / image-gen 代码。
- [x] 编写 README、AGENTS、PLAN、manifest 草案。
- [ ] 初始化本地 git 并提交骨架。

### Phase 1：仓库整理

- [ ] 把自研插件源码复制/移动到 `plugins/`，保留构建产物策略（lib 不提交）。
- [ ] 整理 `community-plugins/`：记录每个插件上游 repo、版本、本地 patch。
- [ ] 整理 `skills/`：决定 submodule 或 vendored，并写安装/更新脚本。
- [ ] 完善 `manifest.json` 字段（source、target、action、repo、version、notes）。
- [ ] 把管理脚本从 `deepseek-harness/` 运行目录“规范化”到 `scripts/`，并让安装器负责同步。

### Phase 2：GitHub 建仓

- [ ] 用 GitHub REST API fork `deepseek-ai/deepseek-harness` → `xsoc1/deepseek-harness`。
- [ ] 推送本地分支 `local/image-admission` 到 fork。
- [ ] 创建 `xsoc1/dsh-local` 仓库（private 或 public，待用户决定）。
- [ ] 配置 submodule 指向 fork 与外部仓库。
- [ ] 首次推送并验证 clone 后能 `install.ps1`。

### Phase 3：安装器完善

- [ ] 实现 `install.ps1` 的 profile junction/复制逻辑。
- [ ] 实现技能 junction、环境变量、计划任务、服务启动。
- [ ] 实现 `-Bootstrap` 新机器依赖安装。
- [ ] 加 `-DryRun` 与健康检查。
- [ ] 编写冒烟测试（在临时 `DSH_HOME` 下演练）。

### Phase 4：切换运行区

- [ ] 确认安装器在当前机器 dry-run 通过。
- [ ] 备份当前 `~/.dsh` 与 `F:\tools` 关键目录。
- [ ] 执行安装器，把线上 profile 切到 repo（junction/复制）。
- [ ] 重启 dsh，验证插件/技能/服务全部正常。
- [ ] 更新 `F:\tools\AGENTS.md` 维护记录，指向 dsh-local。

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| profile 目录迁移破坏当前运行环境 | 先备份；用 junction 而非直接删除；可随时回退 |
| submodule 指向 fork，上游同步复杂 | fork 只保留本地补丁分支，master 保持与上游同步；补丁用 cherry-pick |
| 插件源码直接入库后与线上副本漂移 | 以 dsh-local 为规范源，安装器负责同步；旧目录逐步退役 |
| 模型/缓存体积大、不适合 Git | 只存 manifest 和导入脚本；新机器从官方源或本地缓存导入 |
| 凭据泄露 | `.gitignore` 排除 credentials/secret；安装器从 Windows 凭据管理器读取 |
| pnpm lock 中 link 路径失效 | 改用相对 link；安装器在 profile 内重新 `pnpm install` |

## 9. 待确认事项

- [ ] `dsh-local` 仓库可见性：private / public？
- [ ] 自研插件是否各自独立 GitHub 仓，还是统一放在 dsh-local 内？
- [ ] `Deepseek-Harness-EAC` 是否也需要 fork 到 `xsoc1`？
- [ ] 新机器是否要自动安装 Node/pnpm/Ollama/Python，还是只做“检测+提示”？
- [ ] 是否保留 `F:\tools` 现有目录作为“运行区”，还是后续完全迁入 `dsh-local`？

## 10. 附录：当前已复制进骨架的文件

- `config/settings.yaml`（来自 `~/.dsh/settings.yaml`）
- `config/profiles/web/package.json`（改为相对 link）
- `config/profiles/web/cordis.patch.yml`
- `config/profiles/web/pnpm-workspace.yaml`
- `config/profiles/web/pnpm-lock.yaml`
- `config/agent-presets/router-standard/`
- `config/agent-presets/router-spec/`
- `scripts/dsh-control.ps1`、`dsh-control-gui.ps1`、`run-dsh-web.ps1`、`dsh-watchdog.ps1`、`ensure-dsh-watchdog.ps1`、`make-dsh-icon.ps1`
- `services/image-gen/server.py`、`start-image-gen.ps1`
