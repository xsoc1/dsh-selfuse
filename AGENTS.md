# AGENTS.md — dsh-local 维护基线

本文件是 `F:\tools\dsh-local` 的维护基线。任何 agent/human 进入本仓库先读本文件；
每次变更后更新 `docs/maintenance.md` 中的“维护记录”。

## 工作方法

1. 进入仓库先读 `README.md`、`AGENTS.md`、`docs/PLAN.md`；了解整体结构与当前阶段。
2. 改动前先看 `manifest.json`：组件类型、来源、安装目标、当前状态。
3. 不把密钥/凭据/大模型二进制提交进 Git（见 `.gitignore`）。
4. 任何路径改写、插件升级、配置变更都要同步更新：
   - `manifest.json`
   - `config/profiles/web/package.json` / `cordis.patch.yml` / `settings.yaml`
   - `docs/maintenance.md`
5. 本仓与 `F:\tools` 工作区是“管理仓 / 运行区”关系：
   - 本仓是**规范源**（canonical）。
   - 运行区里的实际目录（`F:\tools\deepseek-harness` 等）目前仍是线上运行副本；
     迁移完成前，修改本仓不代表线上生效，需按 `docs/PLAN.md` 执行安装/同步。

## 关键约束

- **全面弃用 Junction/符号链接**：agent-presets、skills、web profile 一律使用真实复制。
  - agent-presets：dsh 扫描时 `Dirent.isDirectory()` 对 Windows Junction 返回 false，
    preset 会从 roster 消失，WSL 变体也不再生成。
  - skills：同样改为真实目录，避免 watcher/junction 解析问题。
  - web profile：只复制 `cordis.patch.yml` / `pnpm-workspace.yaml`，不 junction。
- `install.ps1` 已按真实复制实现；`ProfileMode` 仅保留 `Copy`。

## 组件分类速查

| 类型 | 目录 | 说明 |
|---|---|---|
| 外部源码 | `vendor/` | submodule：deepseek-harness fork、EAC、awesome 等 |
| 自研插件 | `plugins/` | dsh-memory-panel、dsh-skill-router、dsh-routing-suite |
| 第三方补丁 | `community-plugins/` | dsh-backup、DSH-better-sidebar、git-workflow、undo-fixed、wsl-workspace |
| 技能 | `skills/` | mattpocock skills、math-research-dsh skills（submodule 或 vendored） |
| 配置 | `config/` | settings.yaml、agent-presets、profiles/web |
| 脚本 | `scripts/` | 图形控制台、watchdog、run-dsh-web 等 |
| 服务 | `services/` | 已随识图/生图/Ollama 退役，暂留空目录 |
| 文档 | `docs/` | 方案、架构、维护手册、ADR |

## 待办（当前阶段）

- [ ] 细化 `install.ps1`：profile junction/复制、技能 junction、环境变量、计划任务、服务启动。
- [ ] 把 `plugins/` 下自研插件源码从 `F:\tools\<name>` 迁入本仓（或 submodule）。
- [ ] 把 `community-plugins/` 第三方补丁整理为可重建的 fork/submodule + patch。
- [ ] 创建 GitHub 仓库与 fork（待用户确认执行）。
- [ ] 在 `docs/PLAN.md` 中更新实际迁移进度。
