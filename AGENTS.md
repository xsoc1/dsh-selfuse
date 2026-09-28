# AGENTS.md — dsh-local 维护基线

本文件是 `xsoc1/dsh-selfuse` 管理仓的维护基线。任何 agent/human 进入本仓库先读本文件；每次变更后更新 `docs/maintenance.md` 中的维护记录。

## 工作方法

1. 进入仓库先读 `README.md`、`AGENTS.md`、`docs/current-deployment.md`；历史方案单独见 `docs/PLAN.md`。
2. 改动前先看 `manifest.json` 和活跃 Harness 工作树；区分云端快照、运行源码、用户配置与旧安装器。
3. 不把密钥/凭据/大模型二进制提交进 Git（见 `.gitignore`）。
4. 修改当前部署方法时，同步核对 fork 中的 `config/selfuse/`、`scripts/selfuse/` 和 `packages/selfuse/`，更新本仓 `manifest.json`、相关快照及 `docs/maintenance.md`。
5. 活跃 DSH 源码在 WSL `/home/huangzy/tools/deepseek-harness-current`，实际 `DSH_HOME` 为 `/home/huangzy/.dsh`；Windows `F:\tools\deepseek-harness` 运行管理脚本和桥接。本仓记录可重建的源码引用、管理脚本与步骤，但仅修改本仓不会改变当前服务。
6. `F:\tools\dsh-local` 旧工作树有用户未提交改动；以云端最新分支的干净工作树维护本仓，不覆盖旧工作树。旧 `install.ps1` 和 `scripts/update-dsh.ps1` 不适用于当前 WSL 部署，未经核验不得执行其应用/更新动作。
7. 子模块 pin、活跃源码链接、活跃 `DSH_HOME` 和第三方包是四种状态；版本升级要先跑全部文档门禁、构建、定向测试和隔离启动，再分别记录云端同步与本机切换。第三方上游包只通过原生 `dsh plugin` CLI 装入 profile，补丁与校验值由 [升级说明](docs/upgrade-0.2.0-rc.1.md)记录。

## 关键约束

- agent-presets 与 skills 使用真实目录；现役 WSL profile 由 fork 的 `scripts/selfuse/generate-profile.mjs` 管理，并保留原生 `dsh plugin --profile web` 加入的依赖。
- 远程入口仅通过 Tailscale Serve 暴露给 Tailnet；确认 `serve status --json` 没有 Funnel，再核对 HTTPS、WebSocket 与 iPad 设备侧状态。DERP debug 变量只是本机临时隔离措施，不能当作默认优化。

## 组件分类速查

| 类型 | 目录 | 说明 |
|---|---|---|
| 外部源码 | `vendor/` | submodule：deepseek-harness fork、EAC、awesome 等 |
| 自研插件 | `plugins/` | dsh-memory-panel、dsh-skill-router、dsh-routing-suite |
| 第三方补丁 | `community-plugins/` | dsh-backup、DSH-better-sidebar、git-workflow、undo-fixed、wsl-workspace |
| 技能 | `skills/` | mattpocock skills、math-research-dsh skills（submodule 或 vendored） |
| 配置 | `config/` | settings.yaml、agent-presets、profiles/web |
| 控制台 | `console/` | WinForms 源码、只读诊断及测试，不存预编译 EXE |
| 脚本 | `scripts/` | 当前 Windows 启动/看门狗快照；旧自动更新脚本不适用于现役 WSL |
| 服务 | `services/` | 已随识图/生图/Ollama 退役，暂留空目录 |
| 文档 | `docs/` | 方案、架构、维护手册、ADR |

## 维护边界

- 当前版本的完整 selfuse profile、插件与构建源以锁定的 Harness fork 提交为准；本仓旧 `config/`、`plugins/`、`community-plugins/` 是历史快照，不能覆盖现役 WSL 配置。
- 控制台源码与 Windows 管理脚本同时镜像到本仓，更新时比较其与 Harness fork 对应文件的内容哈希，并运行定向回归。
- `docs/PLAN.md` 和 `docs/architecture.md` 是历史设计记录；当前进度以 `docs/current-deployment.md` 和 `docs/maintenance.md` 为准。

## 对话记录（2026-09-29）

用户要求先更新 DSH 官方最新版、保留插件适配，特别核对本地网络内容隔离插件，再把配置方法同步到 `xsoc1/dsh-selfuse`。候选合并官方 `0.2.0-rc.1` 后，用户被告知完整文档门禁有 19 项失败，明确回复“修完全部门禁再发布”。候选后来通过 `doc-sync` 42/42、构建和隔离 Web 验证；首个临时 profile 仍错误指向现用灵枢记忆目录，启动日志记录 1 项索引对账，随后修复为 `${DSH_HOME}` 路径展开并通过回归测试。同步本仓时发现旧 manifest schema 的 `action` 枚举未收录已有值，补齐并验证。不能把云端候选、隔离测试或本地隐私检查误报为现用服务升级、iPad 端到端验证或绕过服务商策略。

本日后续：完整门禁通过后先发布 fork 分支和本仓 pin，再独立备份、更新现用 profile 的两个外部插件、切换活跃源码链接并重启。现用进程已核对为 `0.2.0-rc.1` 提交，PC 本机登录与 Tailnet HTTPS 登录均为 303→200；iPad 会话及真实模型调用尚未验证。当前 Tailnet 直通模式关闭远程设备配对，启动日志因此提示普通 `/api` 对受信主机开放；不得将它误称为配对保护或公网安全配置。详细步骤、备份与回退边界见 `docs/upgrade-0.2.0-rc.1.md`。
