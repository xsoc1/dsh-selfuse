---
description: "Operate and inspect the local WSL-hosted DSH Web deployment from the Windows control console."
kind: "package-reference"
---

# @dsh-selfuse/control-gui

English | [中文](README.zh.md)

## Summary

Use this Windows console to start or stop the local WSL-hosted DSH Web service and inspect its status. On-demand checks show the local Tailnet route and preview upstream Git state without changing Serve or the checkout. The console complements the native Web UI; it does not manage plugins or verify a remote browser session.

## Table of Contents

- [Controls](#controls)
- [Status](#status)
- [Read-only checks](#read-only-checks)
- [Build](#build)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)
- [Dev Note](#dev-note)

## Controls

- Start, stop, and restart the local DSH watchdog and Web process chain.
- Open the local Web UI, view recent watchdog and Web logs, and refresh status. The log panel also follows new output; its context menu and Ctrl+L clear only the displayed text.
- Open the active WSL DSH configuration directory, copy a status diagnostic, and adjust the banner and source paths in Settings. The main window size persists across launches.
- Run remote health and update preflight checks on demand. Their reports appear in the log panel.

## Status

The console polls in a background PowerShell process. Web is green only after HTTP 200, and Tailscale is green only when its service and backend are running with a Tailnet IP. A status file older than 15 seconds produces an unknown state. Tailscale status is read-only: the console does not change Serve configuration.

The default DSH configuration path is `\\wsl.localhost\Ubuntu\home\huangzy\.dsh`. Existing settings that still name the old Windows `%USERPROFILE%\.dsh` path are mapped to this WSL path when loaded; an explicitly customized path is preserved. The Windows source directory and WSL DSH configuration directory are different locations.

## Read-only checks

Remote health checks local Web HTTP, the Windows Tailscale service and backend, the Serve HTTPS root route to loopback port 3080, Funnel public exposure for that address, and HTTPS reachability from this PC without a proxy. It counts error and reconnect keywords in the last 200 Web log lines without copying log bodies. A local Tailnet result does not establish whether an iPad browser can load or synchronize a Session.

Update preflight resolves `/home/huangzy/tools/deepseek-harness-current`, reports its branch, version, HEAD, uncommitted-item count, and any backup branch pointing at that exact HEAD. It queries `origin` HEAD with a six-second limit and reports whether that commit is already in the local object database and included in the checkout. It does not fetch, merge, reset, build, or restart; if the remote commit is absent locally, it cannot show a source diff.

## Build

From this package directory on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-gui-exe.ps1
```

The resulting `dsh-control-gui.exe` uses `dsh-gui-poller.ps1` and `dsh-gui-probes.ps1` beside it or in the configured source checkout. Update preflight also requires `dsh-update-preflight.sh` in the active WSL source tree. Reopen the console after replacing a running executable.

## Known Limitations and Deferred Work

- The console deliberately has no automatic DSH updater or Tailscale Serve repair button. DSH source upgrades require a reviewed maintenance workflow; plugin management belongs to the native `dsh plugin --profile web` CLI.
- The console controls only this machine's DSH deployment. Its checks do not verify an iPad or other remote client's browser session, and a remote HEAD absent from local Git objects cannot be diffed until a separate reviewed fetch.

## Dev Note

`tests/console-features.ps1` checks visible controls. `tests/status-regression.ps1`, `tests/diagnostic-routes.ps1`, `tests/diagnostic-actions.ps1`, and `tests/update-preflight.sh` check status decisions and read-only reports.
