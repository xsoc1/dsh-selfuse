# Phase 4 预检报告（未实际切换）

> 日期：2026-08-19
> 状态：仅预检 + 备份，未修改线上 `~/.dsh`、未注册任务、未启动/停止服务。

## 1. 备份

- 使用 `backup_dsh` 创建：`C:/Users/HuangZY/Desktop/dsh-backups/dsh-20260819-213751821.tar.gz`
- SHA256：`cc942036fc5f6e87635a19460994bf350e36942dcc878ca182d616569c1ce946`

## 2. 当前线上健康基线

| 服务 | 地址 | 状态 |
|---|---|---|
| dsh web | http://127.0.0.1:3080/ | OK 200 |
| Ollama | http://127.0.0.1:11810/ | OK 200 |
| image-gen | http://127.0.0.1:17821/health | OK 200 |
| watchdog heartbeat | `F:\tools\deepseek-harness\dsh-watchdog.heartbeat` | 新鲜（21:38:52） |

## 3. install.ps1 -DryRun 预览

已执行完整 `install.ps1 -DryRun`，输出保存到 `/tmp/dsh-phase4-dryrun.txt`（本次会话临时文件）。
预览会执行（实际执行时）的动作：

1. `git submodule update --init --recursive`
2. 复制 `config/settings.yaml` → `~/.dsh/settings.yaml`
3. 同步 agent-presets（router-standard / router-spec）
4. 将 `~/.dsh/profiles/web` 迁移为指向 `F:\tools\dsh-local\config\profiles\web` 的 junction
5. 链接 39 个技能 junction
6. 设置用户环境变量 `DSH_ROOT` / `OLLAMA_MODELS` / `HF_HOME`
7. 注册计划任务 `dsh-watchdog`、`dsh-watchdog-ensure`
8. 启动 Ollama / image-gen（若未运行）
9. 健康检查 3080 / 11810 / 17821

## 4. 发现的风险 / 阻塞项

### 4.1 【阻塞】repo profile 的 node_modules 尚未完整安装

- `config/profiles/web/node_modules` 来自之前未跑完的 `pnpm install`，不完整。
- 若现在把 `~/.dsh/profiles/web` 直接 junction 到 `config/profiles/web`，dsh 启动可能因缺依赖失败。
- **必须先**完成 repo profile 的依赖安装，或改用“复制配置到现有 profile、不 junction”的安全模式。

### 4.2 submodule 尚未在 dsh-local 内实际 clone

- `vendor/deepseek-harness`、`vendor/awesome-dsh-plugin` 只有 gitlink 记录，未 clone。
- 实际切换时建议 `install.ps1 -SkipSubmodules`，或先在网络良好时 `git submodule update --init`。

### 4.3 系统级动作尚未在真实机器执行过

- 环境变量写入、`schtasks` 注册、服务启动/健康检查代码已实现，但只在 `-DryRun` 验证。
- 首次真实执行前应再做一次备份，并准备回滚命令。

## 5. 建议的真实切换步骤（待批准后执行）

1. 再次备份 `~/.dsh`。
2. **完成 repo profile 依赖安装**（用 npmmirror，或采用“复制配置不 junction”方案）。
3. 执行 `install.ps1 -Force -SkipSubmodules`（先不注册系统任务/服务？可按需分步）。
4. 重启 dsh，验证 web/插件/技能正常。
5. 确认正常后再注册计划任务、设置环境变量、启动服务。
6. 如异常，用备份回滚。

## 6. 结论

当前**不建议立即执行切换**，因为 repo profile 依赖未完整安装是硬阻塞。
建议先解决依赖安装问题，或选择“只同步配置、不 junction profile”的低风险方案。
