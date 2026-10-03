# 官方 Desktop 插件安装

本目录不提供旧 WSL Web、控制台或看门狗启动器；新专用远程是同一官方 Desktop Host 内的小型扩展，不是独立后台服务。

## 当前专用远程

发布此管理层扩展前，运行 `node scripts/check-remote-publication.mjs`（暂存后加 `--staged`），检查候选常规文件、MJS语法、JSON/schema/模板、相对文档链接/锚和当前私网标识/常见凭据特征；只输出文件名/类别，不输出真实值。此脚本是本机发布预检，依赖既有受限state和已安装Tailscale，不能当作通用完整安全扫描。另执行两类回归、原生隔离、暂存空白检查，普通快进push后再读回ref/blob；真实运行目录不暂存。

连接不稳时先运行 `node scripts/verify-desktop-remote-stability.mjs --seconds=90`：只读观察前台 mux 开关事件和 RPC 耗时，报告在受限部署根，不收集消息正文。它不能代替实际 iPad/手机链路。管理员只读 `inspect-tailscale-service-env.ps1` 会验证原生文件路径并报告是否仍有强制 DERP 调试项；确认后才运行 `remove-tailscale-forced-derp.ps1 -Apply`，精确备份/移除单条开关并有界重启。正常停止超过 60 秒且仍为 Stop Pending 时，`recover-stopping-tailscale.ps1 -Apply` 才允许恢复，逐项校验签名、服务 PID 和子进程；不得用于其他程序或正常运行的服务。回退、现场失败和实测边界见[连接稳定性](../docs/desktop-remote-20261003.md#连接稳定性与旧调试项)。

先读[部署/认证/退役与回退](../docs/desktop-remote-20261003.md#当前模式tailnet-直接访问)。源码由本管理仓 `plugins/desktop-remote` 所有，测试 `node --test plugins/desktop-remote/test.mjs plugins/desktop-remote/tailnet.test.mjs`。`verify-desktop-remote-install.mjs --tailnet` 以官方 Electron Node 模式验证隔离 CLI、实际激活和原生服务器端认证；`verify-desktop-remote-seam.mjs --tailscale-relay` 为历史 legacy 检查，会额外创建并关闭测试 Serve 映射，要求原无 Serve 配置，不在正式映射已上线时运行。

`desktop-remote.mjs install` 用随包 Electron Node 模式执行，须正常退出 Desktop；默认路径已经存在时拒绝覆盖。使用 `--expose-internals` 直接运行随包 JS CLI，不调用 CMD/.cmd。状态用相同运行模式执行 `desktop-remote.mjs status`，不输出凭据。启动后以普通 Node 运行 `verify-desktop-remote-live.mjs`，它执行正式只读 RPC/资源与两个移动尺寸 Chromium 的鉴权、mux 空闲/重连检查，结果在受限部署根 live-acceptance.json；不发送模型请求，真 Safari/手机仍由用户验收。

当前为显式 tailnet 模式：新安装传 `install --tailnet`；现有安装正常退出后以同一 Electron Node 方式执行 `desktop-remote-mode.mjs tailnet`，备份、更新零依赖 payload，只改远程授权行并保留核心配置与 CLI link。`owner-browser` 参数可切回旧模式，仍须正常退出。不要通过重复 install 覆盖现有部署，或关掉全局 Connection 鉴权。模式 helper 是本机专用路径，迁移到别的机器先核对 receipt/profile/安装路径，不假装跨机即用。

`verify-desktop-remote-login.mjs` 普通 Node 验证实际 HTTPS 的全新 Chrome context 直接/合成外链打开入口；依据 state mode，tailnet 模式要求根地址 200 且无 native cookie，legacy 模式检查凭据交换与 Strict cookie。仅输出脱敏状态，不打印 token/cookie 或会话内容，不等同 Android 实机。`--source-relay` 仅供 legacy 的临时源 relay 对照；tailnet 源检查使用上述原生隔离模式，不能用历史身份头代替当前 peer-address gate。

可选二维码（本机已将 qrcode 8.2 装在 F 盘 qr-helper，Python/Pillow 是 Codex 随包工具；不是 Host 依赖）：

```powershell
Get-Content -LiteralPath 'F:\Apps\DeepSeekHarnessRemote\state\connection.json' -Raw |
    & 'C:\Users\HuangZY\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
      'F:\tools\dsh-selfuse-sync-20260928\scripts\render-desktop-remote-qr.py'
```

仅本地生成受限 state/login-qr.png。当前 tailnet 模式只编码固定根地址，无登录 token，重启不需换码；二维码不是必需。Legacy 模式才携带启动凭据并须重启后重新生成。私有 state、地址、日志及真实身份仍不提交；无 Python 直接打开 connect.html 的固定地址，Host 不依赖二维码工具。

RustDesk 三份脚本与模板已转入 `retired/rustdesk-trial-20261003`，不能当活跃安装器；实际程序/配置和专属规则已退役，完整证据见上面的部署说明。

## 已保留插件安装

`install-desktop-plugins.mjs` 只适用于已验证的官方 Windows Desktop `0.2.0-rc.2`。先在固定 Harness 源码提交运行完整检查并构建；源码可以在 WSL，但部署复制的仅是包清单、构建产物和静态资源，不复制 `node_modules`。默认产物和可恢复配置备份在新的 `F:\Apps\DeepSeekHarnessPlugins\selfuse-*` 目录。

先正常退出 Desktop。用随包 Electron 的 Node 模式执行；默认只预检，只有明确传 `--apply` 才安装。下面 `--source` 需改为已构建的 Harness 根目录；云端取回后通常为本仓 `vendor\deepseek-harness`。

```powershell
$env:ELECTRON_RUN_AS_NODE = '1'
try {
    $InstallerProcess = Start-Process `
        -FilePath 'F:\Apps\DeepSeekHarness\DeepSeek Harness.exe' `
        -ArgumentList @(
            'scripts\install-desktop-plugins.mjs',
            '--source', 'vendor\deepseek-harness'
            # 全部门禁和隔离验收通过后添加 '--apply'
        ) `
        -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput 'desktop-install.stdout.log' `
        -RedirectStandardError 'desktop-install.stderr.log'
    if($InstallerProcess.ExitCode -ne 0) { throw '安装/预检失败，请检查日志' }
} finally {
    Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
}
```

不要只用 PowerShell `&` 后读 `$LASTEXITCODE` 判断 GUI 子系统可执行文件的结果；必须等待实际进程退出。路径有空格时，在 `Start-Process` 的 `ArgumentList` 中额外保留参数引号。

正常启动桌面窗口前，用 `Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue` 真正移除 Node 模式变量；不要用当前 PowerShell 的 `[Environment]::SetEnvironmentVariable(..., $null, 'Process')` 代替。本机差分探针显示后者保留长度为零的环境项，桌面程序随即退出 0、没有 Host 日志；真正移除后正常启动。正常启动的 stdout/stderr 仍须接到受限持久文件，验收器必须读取该新实例的日志。

安装器拒绝仍运行的 Desktop 和已有产物目录，先复制并哈希核对五类 profile 文件，再使用官方 `dsh plugin --profile desktop add link:...` 安装十个明确保留包。普通插件行只补 task-notify 和 content-risk-guard；模型、权限、预设、其他用户配置及原注释不改。已有禁用选择不改。

F 盘外置 `link:` 包不能依赖 profile 内的普通查找路径。部署根的私有 package.json 明确声明官方安装器已提供的运行库版本为 peer，使用官方 linked-package resolver 的祖先项目规则；不复制 ASAR 运行库、不改变源码包的依赖分类。非官方共享辅助包及原生第三方依赖以逐包绝对 junction 连接到本次产物或 profile 内的真实目录，并逐个 realpath 读回。第三方依赖由官方 CLI 安装，不把整个 node_modules 连接到别处；目录中相对符号链接在不同祖先路径下不能保证可用。

日志和配置备份只允许当前用户、Administrators 和 SYSTEM 访问，不提交到 Git。失败时停止后续操作，查看私有目录中的 `installation-failed.json`；不要强杀程序或盲目覆盖配置。

回退时先正常退出 Desktop，按 `_profile-before/manifest.json` 逐项核对并恢复原 profile 文件；原本不存在的 lock/workspace 文件仅在确认确属本次生成时移出 profile 归档。重新使用原 package/lock 的官方 CLI 依赖安装，不删除用户数据或会话，不删除旧部署目录。CLI 安装及组合成功不是 Host、图形界面或模型验收；这些结果另见维护记录。

测试用相同 Electron Node 模式执行 `--test scripts\install-desktop-plugins.test.mjs`，同样等待真实退出码。

正式启动后，用相同 Node 模式运行 `scripts\verify-desktop-plugins.mjs --log <当前实例的desktop.stdout.log>`。它只向认证 loopback 发起只读 inventory RPC 和页面/插件 GET，要求九个 Host 激活、五个 Client 行存在且 bundle 可获取；失败退出非零。URL 令牌不进入报告。这仍不是实际面板渲染或模型验收。其正反例用 `--test scripts\verify-desktop-plugins.test.mjs` 执行。

实际界面验收位置：设置 → 内置插件 → 备份 / 记忆；皮肤为设置 → 皮肤中心。要确认面板内容实际渲染、无加载错误，并在明确的测试数据目录验证一次保存和读回；不要以插件列表中 enabled 或程序窗口出现代替激活结果。

## Desktop 同 Host 的第二浏览器隔离验证

`verify-desktop-remote-seam.mjs` 只验证安装版 rc.2 的官方 Desktop 配置组合，不安装远程功能，不连接正式 IPC，也不启动第二个正式 profile。按上文 Electron Node 模式，以受限持久文件重定向启动并等待真实退出；除退出码外，必须读回唯一 F 盘 fixture 的 `result.json` 中 `passed`、`checks`、`liveProfileUnchanged`。它使用本机已有 Chrome 与 WSL 源码目录中的 Playwright，只为固定本机验收；程序或依赖迁移后先调整锚点并重新核对版本。

测试创建独立 home/workspace、隔离凭据路径，并注册纯本地测试模型。两个真正浏览器 context 经公开 Host API 认证，验证移动 RPC 输入、同会话可见思考/完成、原生 WS 断开恢复、刷新持久化及手机视口。所有测试会话留在受限 `F:\tools\dsh-remote-validation-20261003`，日志可能含仅该临时实例的启动凭据，不能提交。此脚本不代替正式 Electron 生命周期、Tailscale HTTPS 或真 Safari/手机验收；当前能力与限制见[专用接入研究](../docs/remote-dsh-only-20261003.md)。
