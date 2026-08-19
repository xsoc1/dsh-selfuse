# dsh-local 排障手册

> **重要**：已全面弃用 Junction/符号链接。agent-presets、skills、web profile 一律真实复制，
> `install.ps1 -ProfileMode` 只接受 `Copy`。

## 1. dsh 极卡 / 反复 `lake build` 子进程

**现象**：dsh 卡顿；任务管理器出现多个 `lake.exe` / `git.exe` 反复 clone/fetch `mathlib4`。

**根因**：某个 dsh 会话的 agent 循环调用 `lake build`（常见于 Lean 数学任务），网络不佳时反复拉取 mathlib。

**定位**：通过临时 staging 工具访问内部服务：

```js
// dev_stage_add 一个工具，执行：
const sessions = ctx.get('sessions').list()
const agents = ctx.get('agents').list()
```

找到 `status: "running"` 且事件数巨大、含大量 `lake build` 的会话。

**处理**：

```js
// dev_stage_add 一个工具，执行：
ctx.get('agents').get('<sessionId>').cancel()
```

必要时临时重命名 `C:\Users\HuangZY\.elan\bin\lake.exe` 阻止重生成，处理完恢复。

## 2. profile junction 后启动失败 / `cannot resolve profile bundle`

**现象**：把 `~/.dsh/profiles/web` 换成指向 `dsh-local/config/profiles/web` 的 junction 后，dsh 启动报 `cannot resolve profile bundle "@dsh-external/dsh-super-injector"` 等。

**根因**：repo profile 的 `package.json` 使用相对 `link:../../../plugins/...`，通过 junction 访问时相对路径按 junction 可见路径解析到 `C:\Users\HuangZY\plugins\...`，找不到。

**处理**：
- 回滚：恢复原实体 profile，删除坏 junction。
- 加固：`package.json` 本地依赖使用绝对 `link:F:/tools/dsh-local/...`；`node_modules` 内链接改为绝对 junction。
- **已全面弃用 junction**：`install.ps1 -ProfileMode` 只允许 `Copy`，skills/agent-presets 也改为真实复制。

## 3. node-pty `AttachConsole failed`

**现象**：dsh-web.log 反复出现 `conpty_console_list_agent.ts` 的 `AttachConsole failed`。

**原因**：better-sidebar 在隐藏/无控制台环境创建终端时，node-pty 的 Windows console-list agent 无法 AttachConsole。通常非致命。

**缓解**：
- `settings.yaml` 设置 `dsh-better-sidebar.bottomPanelAutoTerminal: false`。
- 如仍出现，可关闭已打开的终端标签页；若影响使用，考虑禁用 better-sidebar 的终端功能或升级 node-pty。

## 4. pnpm 安装卡在 `cloudflared` / 个别 tarball

**现象**：`pnpm install` 在 `cloudflared` postinstall 或 `pdfjs-dist` 等下载时卡住/超时。

**处理**：
- 使用国内镜像：`--registry=https://registry.npmmirror.com`
- 跳过 scripts：`--ignore-scripts`（会跳过 cloudflared 二进制下载；远程隧道需单独补装）

## 5. 环境变量 / 计划任务 / 服务

- 用户环境变量：`DSH_ROOT`、`OLLAMA_MODELS`、`HF_HOME`。
- 计划任务：`dsh-watchdog`、`dsh-watchdog-ensure`。
- 服务：Ollama `127.0.0.1:11810`、image-gen `127.0.0.1:17821`。
- 检查：`install.ps1 -DryRun` 预览，`dsh-control.ps1 status` 查看。
