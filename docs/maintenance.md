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
