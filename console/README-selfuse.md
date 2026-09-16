# 图形控制台云端源码

本目录镜像当前 `@dsh-selfuse/control-gui` 的 WinForms 源码、后台轮询、只读远程体检、更新预检和回归测试。Git 不收录生成的 EXE、安装包、个人壁纸或图标；完整的同版本包也可从固定的 Harness 子模块 `packages/selfuse/control-gui/` 获取。

在 Windows 上从本目录运行 `build-gui-exe.ps1` 可用 .NET Framework `csc.exe` 生成 `dsh-control-gui.exe`。没有自定义 `dsh.ico` 时仍可编译，但程序使用默认图标。使用前核对源码中的 `F:\tools`、WSL 路径及横幅默认路径；现有用户设置文件不会由源码快照自动上传。构建完成后在本目录启动 EXE，控制台通过同目录的 `dsh-gui-poller.ps1` 和 `dsh-gui-probes.ps1` 工作。

状态只在本机 Web HTTP 200、Tailscale 服务及 backend 运行且有 Tailnet IP 时显示可用；超过 15 秒的状态文件不保留旧绿色。远程体检检查 Serve 是否仅转发到本机 3080 且未开启 Funnel，但本机检查不能替代 iPad Safari 的实际会话验证。更新预检只读取 Git 状态，不执行更新。

定向测试在 `tests/`。部分诊断动作测试假定原包仍位于 Harness 的 `packages/selfuse/control-gui/`；此云端镜像用于审计与重建，完整包测试应在固定子模块中运行。不要用仓库根目录的旧 `scripts/dsh-control-gui.ps1` 替代当前 WinForms 程序。
