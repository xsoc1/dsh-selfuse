# Safari 经 Tailscale 访问 DSH

> 历史资料：用户于 2026-09-30 决定放弃 DSH 远程插件；当前 Serve 映射已清空，WSL Web profile 已归档。下述配置和“当前”均指退役前状态，不是现行操作指南。参见 [当前部署](current-deployment.md)。

本机采用 iPad Safari → Tailnet HTTPS（Windows Tailscale Serve）→ `127.0.0.1:3080` → WSL DSH Web 的链路。`xsoc.tail6cf486.ts.net` 是本机当前 MagicDNS 主机名，并非通用安装常量。Tailscale Serve 只给 Tailnet 内设备访问；不启用 Funnel。配置与验收要分开：本机 HTTP/WS 检查成功不能证明 iPad 的页面、思考过程和最终状态同步正常。

## 运行配置

当前默认模板在锁定 Harness 的 `config/selfuse/settings.yaml`：

```yaml
remote-web-ui:
  autoTunnel: false
  publicBaseUrl: 'https://xsoc.tail6cf486.ts.net'
  requirePairingForLan: false
```

`publicBaseUrl` 必须与本机 `tailscale serve status --json` 的 HTTPS 主机名一致。`requirePairingForLan: false` 意味着不再由 DSH 配对栅栏阻挡能到达 Serve 的请求，因此应依靠严格的 Tailnet 成员和 ACL 控制访问；若需额外设备配对，改回 `true` 并单独测试移动端流程。禁止把这个设置误当成可公开开启 Funnel 的许可。

Windows `scripts/run-dsh-web.ps1` 为启动的 DSH 传入 `--trusted-host`。Tailscale CLI 暂时离线时，它仅接受活跃 WSL settings 中 `remote-web-ui.publicBaseUrl` 的 HTTPS、无路径/凭据/端口的 `*.ts.net` 主机名作为兜底；这修复了“启动时 Tailnet 未就绪，后来 iPad WebSocket 仍报 403/反复重连”的启动顺序问题。相应回归在 `scripts/run-dsh-web.test.ps1`。变更 Web profile 时同时检查 `config/selfuse/profiles.build.yml`：当前禁用重复的文件预览侧栏，并将 `typert-gateway.websocketHeartbeatIntervalMs` 设为 `10000` 毫秒；这降低空闲连接长时间无反馈的风险，但不是 Safari 端到端同步的保证。

Windows 系统代理对 `*.ts.net`、Tailnet IP 和 localhost 应直连；本机环境变量/Windows ProxyOverride 已设置这些排除项。若使用 Clash Verge，仍需单独检查它的实际配置：2026-09-16 检查到 `verge.yaml` 的 `system_proxy_bypass` 为 `null`，不能声称 Verge 自身已经配置了绕过。不要把 Tailnet WebSocket 送进普通公网 HTTP 代理。

本机 `C:\ProgramData\Tailscale\tailscaled-env.txt` 曾设置 `TS_DEBUG_ALWAYS_USE_DERP=1` 用于隔离链路波动；这是 Tailscale 的调试开关，并非推荐的常态“Safari 优化”，本仓不收录该受保护文件。若实际 `tailscale ping` 已稳定 direct，先用设备侧测试判断是否需要撤销强制 DERP；更改前备份原文件、记录现状，管理员权限重启服务后复测，回退时只删除该调试行。不要为了“修复网页”盲目关闭 TUN 或 Tailscale。

## 核验顺序

1. Windows 检查 DSH 本地 `http://127.0.0.1:3080/` 返回 200，并确认 `tailscale status`、`tailscale serve status --json`：Serve 转发到本机 3080，Funnel 关闭。
2. 从 Tailnet HTTPS 域名取页面，确认不是仅有静态 HTML 而 API/WebSocket 握手也成功；不能用 `ping direct` 代替应用层检查。
3. iPad 保持 Tailscale 已连接，用 Safari 打开域名，发送**仅在 iPad 输入**的独特测试消息；核对 PC 收到该消息、iPad 可见思考/响应流、会话结束后双方状态一致，并观察一段时间是否重连。
4. 如果仅 iPad 失败，分别记录时间、Safari 报错、`tailscale ping` 路径、Windows watchdog/Web 日志与浏览器网络请求；不要把 PC 上重复输入的消息误当作远程发送成功。

依据：[Tailscale Serve 官方说明](https://tailscale.com/docs/reference/tailscale-cli/serve)、[tailscaled 环境文件说明](https://tailscale.com/docs/reference/tailscaled)、[Tailscale 调试开关源码](https://github.com/tailscale/tailscale/blob/main/wgengine/magicsock/debugknobs.go)。
