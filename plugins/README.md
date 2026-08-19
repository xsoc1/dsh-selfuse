# plugins

自研插件规范源。当前已从 `F:\tools\<name>` **复制**进本目录（保留 lib 构建产物，便于直接 link 使用）：

- `dsh-image-bridge/`：图片附件桥 + generate_image 工具
- `dsh-memory-panel/`：纯本地文件记忆面板
- `dsh-skill-router/`：技能路由提示段
- `dsh-image-vision/`：整合识图插件（已有独立 GitHub 仓 `xsoc1/dsh-image-vision`，后续可改 submodule）
- `dsh-routing-suite/`：注入器 + 路由预设套装（已去除 .gitmodules，作为 vendored 目录）

> 复制而非移动，目的是**不干扰当前运行中的 dsh**（线上 profile 仍 link 到 `F:\tools\...`）。
> 迁移完成后，安装器将改为 link 到本目录；确认无误后再退役旧目录。
