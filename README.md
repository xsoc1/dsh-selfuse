# dsh-selfuse

DeepSeek Harness 自用部署的云端管理仓。[`vendor/deepseek-harness`](vendor/deepseek-harness) 子模块锁定已通过文档门禁、构建和隔离启动检查的 `0.2.0-rc.1` 自用版本；本机于 2026-09-29 切换到该提交。本仓另外保存 Windows [图形控制台源码](console/README-selfuse.md)、[管理脚本快照](scripts/README.md)、[Safari/Tailscale 远程配置方法](docs/safari-tailnet.md)，以及 [0.2.0-rc.1 升级和第三方插件复建说明](docs/upgrade-0.2.0-rc.1.md)。

当前运行服务仍在本机：WSL `/home/huangzy/tools/deepseek-harness-current` + `/home/huangzy/.dsh`，Windows `F:\tools\deepseek-harness` 负责启动与桥接。本次已在本机单独完成切换与重启；今后的云端提交仍不会自动改动或重启该服务。

## 从云端取回

```powershell
git clone --recurse-submodules https://github.com/xsoc1/dsh-selfuse.git
cd dsh-selfuse
git submodule status vendor/deepseek-harness
```

完整的当前目录关系、候选/现用区别、配置来源和只读核验见 [当前部署说明](docs/current-deployment.md)；远程链路和可回退的网络设置见 [Safari/Tailscale 手册](docs/safari-tailnet.md)。组件索引见 [manifest.json](manifest.json)，历次维护见 [docs/maintenance.md](docs/maintenance.md)。

`install.ps1`、旧 `config/` 和旧 `plugins/` 属于早期 Windows/DSH 0.1.2 管理方案，不应覆盖当前 WSL `DSH_HOME`。当前 profile、settings 模板、预设和技能的维护入口是子模块中的 `config/selfuse/` 与 `scripts/selfuse/install.mjs`；安装前先核对差异并备份用户数据。API Key、登录凭据、会话、记忆和模型文件不入库。
