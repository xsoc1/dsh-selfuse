# community-plugins

第三方插件（含本地补丁）规范源。计划包含：

- `dsh-backup/`：备份插件（本地修复 backupPanel/remove 冲突）
- `DSH-better-sidebar/`：右侧工作台
- `dsh-plugin-git-workflow/`：Git 工作流工具
- `dsh-undo-plugin-fixed/`：undo/回滚插件（本地修复副本）
- `dsh-wsl-workspace/`：WSL 工作区

策略：优先保留上游 git 并记录本地 patch；无法 fork 时以 vendored 方式入库。
