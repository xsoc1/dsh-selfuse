# config

`~/.dsh` 的“代码化”规范源。

- `settings.yaml`：用户级 dsh 配置（含模型能力声明、remote-web-ui 等）。
- `agent-presets/`：思维模式路由预设（router-standard、router-spec 等）。
- `profiles/web/`：web profile 的规范目录（package.json、cordis.patch.yml、pnpm lock 等）。

安装器会把本目录同步到 `%USERPROFILE%\.dsh`：

- `settings.yaml` → `~/.dsh/settings.yaml`
- `agent-presets/*` → `~/.dsh/.agent-presets/`
- `profiles/web` → `~/.dsh/profiles/web`（推荐 junction 或复制）

> 注意：`settings.yaml` 里可能有机器相关值（Tailscale 域名、端口、模型名）。
> 新机器部署时建议用 `local.overrides.yaml` 或环境变量覆盖。
