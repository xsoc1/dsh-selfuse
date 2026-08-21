# deepseek-harness 本地补丁

本目录保存对 `deepseek-ai/deepseek-harness` 的本地适配补丁。

## 当前基线

- 上游版本：`0.1.1-rc.1`
- 上游 master：`528c682e06`
- 本地维护分支：`local/image-admission`（基于新 master，包含以下补丁）

## 补丁列表

### 1. `spawn-windows-hide.patch`

文件：`packages/subprocess/subprocess-local/src/spawn.ts`

内容：`spawnSubprocess` 的 `spawn()` 增加 `windowsHide: true`，避免 dsh 在 Windows 上隐藏子进程时闪控制台窗口。

> 同时需要同步修改 `packages/subprocess/subprocess-local/lib/index.js`（dsh 运行实际加载 lib）。

### 2. `local/image-admission` 分支补丁

文件：`packages/llm/llm-deepseek/src/adapter.ts`

内容：让 deepseek-official 目录模型与 uncatalogued fallback 声明 `inputModalities: ['text', 'image']`，配合 dsh-image-bridge + view_image 使 text-only 模型也能承载带图会话。

> 同时需要同步修改 `packages/llm/llm-deepseek/lib/index.js`。

## 应用方式

在 `deepseek-harness` 仓库：

```powershell
# 更新到上游并保留本地补丁
git fetch origin
git checkout master
git merge --ff-only origin/master
git checkout local/image-admission
git rebase master
git apply F:\tools\dsh-local\patches\deepseek-harness\spawn-windows-hide.patch
# 然后运行 build:lib:host 重新生成 lib
npm run build:lib:host
```
