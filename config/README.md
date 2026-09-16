# 历史配置快照

本目录保存早期 Windows/DSH 0.1.2 部署的 settings、预设和 Web profile，不是当前 WSL 服务的配置源。不要将这里的 `settings.yaml` 或 `profiles/web` 复制到活跃 `/home/huangzy/.dsh`。

当前配置模板位于 [`vendor/deepseek-harness/config/selfuse/`](../vendor/deepseek-harness/config/selfuse/)，profile 由子模块中的 `scripts/selfuse/generate-profile.mjs` 生成，并保留通过原生 `dsh plugin --profile web` 加入的显式插件。`/home/huangzy/.dsh` 是运行数据目录，含会话、记忆和可能的凭据；它不是要整体上传的代码目录。部署与备份边界见 [当前部署说明](../docs/current-deployment.md)。
