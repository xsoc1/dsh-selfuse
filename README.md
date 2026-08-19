# dsh-local

本地 DeepSeek Harness（dsh）自用管理仓。

把本机 dsh 依赖的 **源码 fork、自研插件、第三方补丁插件、技能、图形控制台脚本、
本地小模型服务、profile 配置** 统一收进一个可维护、可重装、可给 agent 协作的代码库。

> 当前状态：**GitHub 仓库已建、插件/技能已入库、install.ps1 已实现；全面弃用 junction，一律真实复制**。
> 详细计划见 [`docs/PLAN.md`](docs/PLAN.md)，最近维护见 [`docs/maintenance.md`](docs/maintenance.md)。

## 设计目标

- **一切皆代码**：配置、插件、技能、脚本都纳入 Git 版本管理。
- **人/agent 双友好**：根 `AGENTS.md` 给 agent 看，`docs/` 给人看，`manifest.json` 给安装器/工具读。
- **双仓结构**：
  - `xsoc1/deepseek-harness`：上游 `deepseek-ai/deepseek-harness` 的 fork，只保留源码 + 少量本地补丁。
  - 本仓（`dsh-local`）：聚合所有个人内容，通过 submodule 引用 fork 与其他外部仓库。
- **一键安装/配置**：`install.ps1` 可在当前机器重建配置，也可在新机器上部署完整环境。
- **不存大模型二进制**：模型只存 manifest 与下载/导入脚本。

## 目录结构

```text
dsh-local/
├─ AGENTS.md                 # 本仓 agent 维护基线
├─ install.ps1               # 一键安装/配置入口（支持 -DryRun/-ProfileMode/-NoSystem 等）
├─ manifest.json             # 组件清单（机器可读）
├─ config/                   # 规范化配置（~/.dsh 的“代码化”副本）
│  ├─ settings.yaml
│  ├─ agent-presets/         # router-standard / router-spec 等预设
│  └─ profiles/web/          # web profile：package.json / cordis.patch.yml / pnpm-lock
├─ scripts/                  # 管理脚本（图形控制台、看门狗、启动器等）
├─ plugins/                  # 自研插件源码
├─ community-plugins/        # 第三方插件（含本地补丁）
├─ skills/                   # 技能集合（submodule 或 vendored）
├─ vendor/                   # 外部源码仓库 submodule（deepseek-harness fork、EAC、awesome 等）
├─ services/                 # 本地服务（image-gen、ollama 编排）
└─ docs/                     # 方案、架构、维护手册、ADR
```

## 快速开始（当前骨架阶段）

```powershell
# 查看方案
notepad .\docs\PLAN.md

# 初始化本地 git（可选）
git init
git add .
git commit -m "chore: dsh-local skeleton"
```

完整安装器尚未实现；见 `docs/PLAN.md` 的迁移步骤。
