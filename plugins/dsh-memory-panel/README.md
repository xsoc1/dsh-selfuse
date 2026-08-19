# dsh-memory-panel

设置 → 插件 →「记忆」——**纯本地文件记忆**（Hindsight 云端记忆的本地替代）。

零依赖、零模型、永远离线可用：不加云、不调 LLM、数据不出本机。所有“记忆”都是
`~/.dsh/memory/` 下的 Markdown 文件，可以随时用编辑器直接添加/修改。

## 功能

- **本地存储概览**：存储位置、知识页 / 记忆条目数量、占用空间。
- **知识页**：浏览 `~/.dsh/memory/knowledge/*.md`（一个文件一页，可点开查看）。
- **记忆条目**：浏览 `~/.dsh/memory/notes/*.md`（一条一文件，按时间倒序）。
- **写一条记忆**：在条目标签页直接输入标题 + 内容保存为新条目。
- **搜索**：在知识页与记忆条目的标题 + 内容里做子串搜索。

## 存储结构

```
~/.dsh/memory/
  knowledge/   知识页：<名字>.md（标题取 frontmatter `title:` 或首个 # 标题，否则文件名）
  notes/       记忆条目：<时间戳>-<名字>.md
```

可用环境变量 `DSH_MEMORY_ROOT` 覆盖存储根目录（测试用；默认 `~/.dsh/memory`）。

## 结构

```
lib/index.js     宿主半边：/memory JSON 路由（node 内置，零第三方依赖）
lib/client.js    浏览器半边：CJS factory，react 组件（手工构建，无打包步骤）
cordis.patch.yml 装配行（dsh.bundle.patch）
scripts/         冒烟测试（node scripts/smoke.mjs / smoke-client.mjs）
```

## 安装（本工作区）

```text
dev_install_package 指向本目录 → profile package.json 加
link:F:/tools/dsh-memory-panel + bundles 加 dsh-memory-panel →
node_modules junction → loader.create；重启 dsh 或浏览器硬刷新后生效。
```

## 安全

- 文件 id 只允许 `[A-Za-z0-9\u4e00-\u9fa5._-]`，无分隔符/路径穿越；读取限定在
  存储根目录内。
- 只读 + 写本地条目的 JSON 路由，与 dsh web 同源，受 webserver 绑定范围保护。

## 历史

由 `dsh-hindsight-panel`（Hindsight 云端记忆查看面板）替换而来；已从 web
profile 移除 `@vectorize-io/hindsight-coding-agents` 与旧面板。
