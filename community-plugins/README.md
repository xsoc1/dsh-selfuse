# community-plugins

第三方插件（含本地补丁）规范源。当前已从 `F:\tools\community-plugins\<name>` **复制**进本目录：

- `dsh-backup/`：备份插件（本地修复 backupPanel/remove 冲突）
- `DSH-better-sidebar/`：右侧工作台
- `dsh-plugin-git-workflow/`：Git 工作流工具
- `dsh-undo-plugin-fixed/`：undo/回滚插件（本地修复副本，main 指向 lib/index2.js）
- `dsh-wsl-workspace/`：WSL 工作区

策略：优先保留上游 git 并记录本地 patch；当前为 vendored 副本，后续可改为 fork/submodule + patch。
复制而非移动，避免干扰线上运行。
