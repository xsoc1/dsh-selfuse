# community-plugins

第三方插件（含本地补丁）规范源。当前已从 `F:\tools\community-plugins\<name>` **复制**进本目录。

| 目录 | 版本 | 上游仓库 | 本地补丁/说明 |
|---|---|---|---|
| `dsh-backup/` | 0.5.0 | https://github.com/xiaoyuyu6420/dsh-backup | backupPanel/remove → deleteBackup 冲突修复 |
| `DSH-better-sidebar/` | 0.12.2 | https://github.com/omdsh-dev/DSH-better-sidebar | 默认不自动打开；node-pty 补丁见 `patches/node-pty` |
| `dsh-plugin-git-workflow/` | 0.1.1 | https://github.com/truelove-dreamer/dsh-plugin-git-workflow | 无本地改动 |
| `dsh-undo-plugin-fixed/` | 0.3.3 | 上游 `dsh-undo-plugin`（本地修复副本） | main 指向 `lib/index2.js`，用于绕过 ESM 缓存问题 |
| `dsh-wsl-workspace/` | 0.2.3 | https://github.com/6Mikao9/dsh-wsl-workspace | 无本地改动 |

策略：vendored 副本，优先记录上游与本地 patch；复制而非移动，避免干扰线上运行。
