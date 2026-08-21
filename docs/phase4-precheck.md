# Phase 4 预检报告（未实际切换）

> 日期：2026-08-19
> 状态：仅预检 + 备份，未修改线上 `~/.dsh`、未注册任务、未启动/停止服务。
> 2026-08-21 更新：Ollama 与 image-gen 已退役，本文原基线仅作历史参考。

## 1. 备份

- 使用 `backup_dsh` 创建：`C:/Users/HuangZY/Desktop/dsh-backups/dsh-20260819-213751821.tar.gz`
- SHA256：`cc942036fc5f6e87635a19460994bf350e36942dcc878ca182d616569c1ce946`

## 2. 当前线上健康基线

| 服务 | 地址 | 状态 |
|---|---|---|
| dsh web | http://127.0.0.1:3080/ | OK 200 |
| watchdog heartbeat | `F:\tools\deepseek-harness\dsh-watchdog.heartbeat` | 新鲜（21:38:52） |

## 3. install.ps1 -DryRun 预览

已执行完整 `install.ps1 -DryRun`，输出保存到 `/tmp/dsh-phase4-dryrun.txt`（本次会话临时文件）。
预览会执行（实际执行时）的动作：

1. `git submodule update --init --recursive`
2. 复制 `config/settings.yaml` → `~/.dsh/settings.yaml`
3. 同步 agent-presets（router-standard / router-spec）
4. 将 `~/.dsh/profiles/web` 迁移为指向 `F:\tools\dsh-local\config\profiles\web` 的 junction
5. 链接 39 个技能 junction
6. 设置用户环境变量 `DSH_ROOT`
7. 注册计划任务 `dsh-watchdog`、`dsh-watchdog-ensure`
8. 健康检查 3080

## 4. 发现的风险 / 阻塞项

### 4.1 【已解决】repo profile 的 node_modules 现已完整安装

- 已用 `pnpm install --registry=https://registry.npmmirror.com --ignore-scripts` 完成安装（233 包，6.6s）。
- `node_modules` 大小 253MB，相对 link 插件均正确链接。
- 注意：`--ignore-scripts` 跳过了 cloudflared postinstall，remote-web-ui 公网隧道如需使用，需后续单独补装 cloudflared 二进制；不影响 dsh 核心启动。

### 4.2 submodule 尚未在 dsh-local 内实际 clone

- `vendor/deepseek-harness`、`vendor/awesome-dsh-plugin` 只有 gitlink 记录，未 clone。
- 实际切换时建议 `install.ps1 -SkipSubmodules`，或先在网络良好时 `git submodule update --init`。

### 4.3 系统级动作尚未在真实机器执行过

- 环境变量写入、`schtasks` 注册/健康检查代码已实现，但只在 `-DryRun` 验证；服务启动已随 Ollama/image-gen 退役移除。
- 首次真实执行前应再做一次备份，并准备回滚命令。

## 5. 建议的真实切换步骤（待批准后执行）

1. 再次备份 `~/.dsh`。
2. **完成 repo profile 依赖安装**（用 npmmirror，或采用“复制配置不 junction”方案）。
3. 执行 `install.ps1 -Force -SkipSubmodules`（先不注册系统任务/服务？可按需分步）。
4. 重启 dsh，验证 web/插件/技能正常。
5. 确认正常后再注册计划任务、设置环境变量。
6. 如异常，用备份回滚。

## 6. 结论与当前进度

原硬阻塞（repo profile 依赖未完整）已通过 `--ignore-scripts` 解决；`node_modules` 已完整。

### 已执行（2026-08-19，junction 方案已回滚）

- 再次备份：`C:/Users/HuangZY/Desktop/dsh-backups/dsh-20260819-215715900.tar.gz`
- 曾新建 junction，但因相对 link 通过 junction 解析失败导致重启问题；已回滚：
  - 恢复原 `~/.dsh/profiles/web` 实体目录
  - 清理坏 junction（`web.junction-broken-...`）
- 当前 dsh web 200；线上 profile 为原始实体目录，未使用 repo junction。

### 当前结论

- 本机**不再使用 Junction 模式**，`install.ps1` 默认 `-ProfileMode Copy`。
- Copy 模式只同步 `settings.yaml` / `cordis.patch.yml` / `pnpm-workspace.yaml`，不覆盖 `package.json` / `pnpm-lock.yaml`，避免破坏现有 node_modules。
- 系统级动作（env/schtasks/services）仍未执行；如需执行，应先 `-DryRun` 确认。
