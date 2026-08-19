# web profile（规范源）

本目录是 `~/.dsh/profiles/web` 的代码化副本。

- `package.json`：依赖使用**相对 link**（`link:../../../plugins/...`），仓库可移动。
- `cordis.patch.yml`：patch 装配层（dsh-vision、image-bridge、skill-router、EAC 配套等）。
- `pnpm-workspace.yaml`：pnpm 工作区与 allowBuilds 配置。
- `pnpm-lock.yaml`：锁文件，保证可复现安装。

安装器推荐把 `~/.dsh/profiles/web` 建为指向本目录的 junction，实现“profile as code”。
