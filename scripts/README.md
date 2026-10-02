# 官方 Desktop 插件安装

本目录不再提供旧 Web、远程、控制台或看门狗启动器。

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
