---
description: "通过 Windows 图形控制台管理并检查本机 WSL 中运行的 DSH Web 服务。"
kind: "package-reference"
---

# @dsh-selfuse/control-gui

[English](README.md) | 中文

## 概述

可以用这个 Windows 控制台启动或停止本机 WSL 中的 DSH Web 服务，并查看其状态。按需检查会展示本机 Tailnet 路由与上游 Git 状态，但不会修改 Serve 或工作树。控制台是原生 Web UI 的辅助工具，不管理插件，也不验证远程浏览器会话。

## 目录

- [功能](#controls)
- [状态](#status)
- [只读检查](#read-only-checks)
- [构建](#build)
- [已知限制与待办](#known-limitations-and-deferred-work)
- [开发备注](#dev-note)

<a id="controls"></a>
## 功能

- 启动、停止、重启本机 DSH watchdog 与 Web 进程链。
- 打开本机 Web UI、查看最近的 watchdog 与 Web 日志，并刷新状态。日志区也会跟随新输出；右键菜单和 Ctrl+L 只清除界面显示的文字。
- 打开活跃 WSL DSH 配置目录、复制状态诊断，并在设置中调整横幅和源码路径。主窗口尺寸会在重新打开时保留。
- 按需运行远程体检和更新预检，结果显示在日志区。

<a id="status"></a>
## 状态

控制台由后台 PowerShell 进程轮询。Web 只有返回 HTTP 200 才显示绿色；Tailscale 只有服务和后端运行且取得 Tailnet IP 才显示绿色。状态文件超过 15 秒未更新时显示未知。Tailscale 状态为只读信息，控制台不会修改 Serve 配置。

默认 DSH 配置路径为 `\\wsl.localhost\Ubuntu\home\huangzy\.dsh`。现有设置若仍指向旧 Windows `%USERPROFILE%\.dsh`，加载时会映射到该 WSL 路径；明确自定义的路径会保留。Windows 源码目录与 WSL DSH 配置目录是两个不同位置。

<a id="read-only-checks"></a>
## 只读检查

远程体检检查本机 Web HTTP、Windows Tailscale 服务与后端、Serve 的 HTTPS 根路径是否转发到回环端口 3080、该地址是否通过 Funnel 对公网开放，以及本机不经代理访问 Tailnet HTTPS 的结果。它只统计 Web 日志末尾 200 行中的错误和重连关键词，不复制日志正文。本机 Tailnet 探测通过，不代表 iPad 浏览器能加载或同步会话。

更新预检解析 `/home/huangzy/tools/deepseek-harness-current`，报告分支、版本、HEAD、未提交项数量，以及是否有备份分支指向该 HEAD。它在六秒时限内查询 `origin` HEAD，报告该提交是否已在本地对象库、是否已包含于当前工作树。预检不执行 fetch、合并、重置、构建或重启；若远端提交尚未进入本地对象库，就不能显示源码差异。

<a id="build"></a>
## 构建

在 Windows 的本包目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-gui-exe.ps1
```

生成的 `dsh-control-gui.exe` 使用同目录或已配置源码工作树中的 `dsh-gui-poller.ps1` 与 `dsh-gui-probes.ps1`。更新预检还需要活跃 WSL 源码树中的 `dsh-update-preflight.sh`。替换正在运行的程序后，需重新打开控制台。

<a id="known-limitations-and-deferred-work"></a>
## 已知限制与待办

- 控制台不提供自动更新 DSH 或修复 Tailscale Serve 的按钮。DSH 源码升级需走经过检查的维护流程；插件管理使用原生 `dsh plugin --profile web` CLI。
- 控制台只管理本机 DSH 部署；其检查不验证 iPad 等远程设备上的浏览器会话。若远端 HEAD 尚未进入本地 Git 对象库，须另行审查后获取提交才能计算差异。

<a id="dev-note"></a>
## 开发备注

`tests/console-features.ps1` 检查界面入口；`tests/status-regression.ps1`、`tests/diagnostic-routes.ps1`、`tests/diagnostic-actions.ps1` 和 `tests/update-preflight.sh` 检查状态判定与只读报告。
