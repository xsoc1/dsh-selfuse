# deepseek-harness 本地补丁

本目录保存对 `deepseek-ai/deepseek-harness` 的本地适配补丁。

## 当前基线

- 上游版本：`0.1.1-rc.2`
- 上游 master：`b150a551b8`
- 本地维护分支：`local/image-admission`（基于新 master，包含以下补丁）

## 补丁列表

### 1. `spawn-windows-hide.patch`

文件：`packages/subprocess/subprocess-local/src/spawn.ts`

内容：`spawnSubprocess` 的 `spawn()` 增加 `windowsHide: true`，避免 dsh 在 Windows 上隐藏子进程时闪控制台窗口。

> 同时需要同步修改 `packages/subprocess/subprocess-local/lib/index.js`（dsh 运行实际加载 lib）。
> 配套测试：`packages/subprocess/subprocess-local/tests/spawn-windows.spec.ts`（本目录也有副本 `spawn-windows.spec.ts`）。

### 2. 已删除：adapter image-admission 补丁

> 旧版为了让 text-only DeepSeek 模型承载带图会话而修改 `packages/llm/llm-deepseek/src/adapter.ts`。
> **上游 0.1.1-rc.2 已原生支持多模态/文件上传，该补丁不再需要，已在 rebase 时丢弃。**

## 应用方式

在 `deepseek-harness` 仓库：

```powershell
# 更新到上游并保留本地补丁
git fetch origin
git checkout master
git merge --ff-only origin/master
git checkout local/image-admission
git rebase master
# 然后运行 build:lib:host 重新生成 lib
npm run build:lib:host
```
