# 配置来源

当前仅 [Desktop profile 补丁模板](desktop/cordis.patch.yml) 用于本机官方 Windows Desktop：合并 `webserver` 动态 loopback 端口与 `agent-preset-registry` 官方 `standard` 新会话选择。应用前备份真实 `C:\Users\HuangZY\.dsh\profiles\desktop\cordis.patch.yml`，按行合并，不要覆盖用户已有设置。

本目录其余 `settings.yaml` 与预设是早期部署快照；原 WSL Web profile 已从仓库移除并在本机归档，不应复制这些文件到 Desktop。旧 [Safari/Tailscale 资料](../docs/safari-tailnet.md)仅供历史查询，不是当前远程入口操作指南。实际数据与归档位置见 [当前部署](../docs/current-deployment.md)。
