# node-pty 本地补丁

node-pty 最新 npm 版本仍为 `1.1.0`，无法通过升级解决 `AttachConsole failed`。
本目录保存已打补丁的文件，供离线/版本化参考。

## 文件

- `lib/conpty_console_list_agent.js`：编译后 JS，已补丁。
- `src/conpty_console_list_agent.ts`：TypeScript 源，已补丁。

## 补丁内容

`AttachConsole` 失败时不再抛错，而是返回空列表：

```js
var consoleProcessList = [];
try {
  consoleProcessList = getConsoleProcessList(shellPid);
} catch (err) {
  consoleProcessList = [];
}
```

## 应用方式

推荐使用幂等脚本：

```powershell
powershell -ExecutionPolicy Bypass -File F:\tools\dsh-local\scripts\patch-node-pty.ps1
```

或手动覆盖：

```text
F:\tools\community-plugins\DSH-better-sidebar\node_modules\.pnpm\node-pty@1.1.0\node_modules\node-pty\lib\conpty_console_list_agent.js
F:\tools\community-plugins\DSH-better-sidebar\node_modules\.pnpm\node-pty@1.1.0\node_modules\node-pty\src\conpty_console_list_agent.ts
```

> 注意：`pnpm install` 重装依赖后补丁可能丢失，需重新执行 `scripts/patch-node-pty.ps1`。
