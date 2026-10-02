# 2026-10-01 原生 UI 精简

用户先要求“按你的方案办”，随后明确选择“归档三个条件项，优先原生功能”。该阶段归档四个旧 UI/兼容包及 SSH、任务板、MinerU，优先使用官方 SSH 与计划任务；当时保留 Git 图、皮肤中心、memory-panel、git-workflow、备份、撤销、通知、灵枢、提示词优化器和本地隐私隔离。2026-10-02 又批准归档 undo，保留备份与原生恢复；提示词优化器及灵枢旧 profile 没有迁入正式 Desktop，不能把该历史名单当作现用插件清单。正式 CLI 当前安装十包但面板验收未通过，外置依赖修复等待正常退出；以[当前部署](current-deployment.md)和[安装与运行验收](../scripts/README.md)为准。

## 当前结构

| 旧包 | 处理与替代 |
|---|---|
| `@dsh-selfuse/web-ui-settings` | 源码归档；使用官方设置入口 |
| `@dsh-selfuse/web-ui-community-plugins` | 源码归档；插件管理使用官方 CLI/原生界面，不保留第二个社区目录页 |
| `@dsh-selfuse/skins` | 源码归档；皮肤资源仍由 `skin-center` 管理 |
| `@dsh-selfuse/web-ui-all` | 源码归档；候选配置直接列出 `web-ui-git-graph` 和 `skin-center` |
| `@dsh-selfuse/ssh` | 源码归档；使用官方 SSH 能力，不保留第二套 SSH 管理界面 |
| `@dsh-selfuse/web-ui-task-board` | 源码归档；使用官方计划任务，不移植独立看板 |
| `@dsh-selfuse/mineru` | 源码归档；不部署其外部 OCR 服务，未宣称官方预览具备等价 OCR |
| `@deepseek-ai/dsh-client-runtime` / `dsh-host-apiproxy` | 无保留包消费后归档；保留包改接当前拆分服务 |

原聚合器还提供皮肤资源实际使用的 `data-pane`、`data-dsh-frame` 属性，不能把它连同必要适配一起丢掉。保留的 `skin-layout-compat` 是小型浏览器叶子包，不含聚合设置页、社区市场或模型工具。它由皮肤中心 bundle 挂载；已有属性不覆盖，卸载取消待执行帧、断开 MutationObserver，并只撤回仍归它所有的属性。已脱离页面的节点释放引用。后续从 dsh-web 固定 `v0.2.7` 提交 `314f9ea7524c1a8fa2bb6c9a2c3bcaaa440cee5f` 恢复皮肤中心 34 个源码文件，逐个记录恢复时的 SHA-256，不覆盖本地改动；随后迁移原生 ConfigForms 并实际重建 Host/Client 产物。构建成功仍不代表全部皮肤和壁纸视觉交互已经验收。

`config/selfuse/profiles.build.yml` 的 `retiredPackages` 现在列出上述九项依赖。生成器从旧候选 profile 的依赖和 bundle 中移除它们，保留其他通过原生 CLI 安装的插件和本机覆盖后缀；清单若把退役包再次加入 bundle 或普通插件行，会在写入前拒绝。只在临时 `DSH_HOME` 验证生成器，没有对真实 Desktop home 运行。本机覆盖后缀仍由用户维护，不自动重写其中的任意配置。

任务板和 SSH 的旧接口迁移工作随完整目录保存在归档，不再参与当前构建。撤去其候选配置、CLI 依赖、模块种子及目录生成结果；不为已退役功能继续维护另一套原生能力。

## 归档与保护

源码目录为 `/home/huangzy/tools/deepseek-harness-upgrade-20260929`。四个完整目录移至 `/home/huangzy/tools/dsh-retired-20261001/native-ui-packages`，未提交文件和依赖一起保留。移动前后校验 46 个受 Git 跟踪文件，共 389754 字节，SHA-256 全部一致。

执行脚本、移动前清单和验后清单位于 `F:\tools\dsh-retired-20261001\native-ui-retirement`，文件分别为 `archive-ui.ps1`、`archive-before.json`、`archive-verified.json`。这次归档操作前后，真实 Desktop 的 `package.json`、`cordis.patch.yml`、锁文件保持一致；当时 profile 的第三方依赖为空，只列官方 bundle。未改动签名安装包、工作区、会话、记忆或运行进程。这是归档阶段的保护证据，不是 10 月 2 日 CLI 安装后的当前配置。

三个条件插件及两个闲置 SDK 的完整目录移至 `/home/huangzy/tools/dsh-retired-20261001/conditional-packages`。764 个文件/符号链接记录、共 7359945 字节，改名前后内容哈希及链接目标全部一致；包括未提交文件、构建产物与依赖。复核使用源码脚本 `scripts/selfuse/archive-conditional.mjs --verify`，此模式不写入；记录副本见 `F:\tools\dsh-retired-20261001\completion-repair\conditional-inventory` 和 `conditional-verified.json`。没有移走插件用户数据或会话。

另将 240 个未跟踪、错误落在 `src` 旁的编译文件移到 `generated-src-residue`：只有 source map 明确对应现存 TypeScript 原文件的编译输出才入选，1084269 字节逐项校验。原始 TS 和受跟踪文件不动；此项解决了重复扫描 JSDoc/持久类型的问题，不是隐藏未实现源码。

## 验收边界

- 真实 Loader 读取临时 `cordis.yml`，验证布局属性的激活、禁用后重载；另外验证节点替换、属性归属、取消待执行帧和脱离节点清理。
- 生成器回归把四个旧依赖写入临时 profile，再生成后确认它们消失，其他 CLI 插件仍在，Git 图与皮肤中心独立加载。
- 构建后的浏览器工厂在 jsdom 中实际执行，验证激活与清理；不是只读取源代码或检查导出名称。
- 原生 UI 精简阶段回归为 40/40；后续条件项归档及保留产物检查单独记录，不混算。浏览器工厂加载不等于实际调用全部 UI 或真实 Desktop 插件验收；最终测试数值见维护记录。
- 文档与全仓门禁的最终数值见本轮[维护记录](maintenance.md#2026-10-01-按方案精简旧-ui-兼容包)。完整要求通过前仍不提交、推送或更新子模块 pin。

`memory-panel` 管理本地 Markdown 给人阅读，不向模型自动检索；它和灵枢存储也不能在未验证数据迁移的情况下视作同一套记忆。`git-workflow` 提供五个结构化 Git 工具，包含受沙箱约束的提交操作，官方 shell 可以实现同类操作，但返回格式与使用方式不同。因此两项本轮保留；若以后退役，先确认替代流程和数据处理，而不是删除记忆或工具后称为等价替换。

## 回退方法

先核验当前源码链接和上述归档根目录；逐包确认源码目标不存在，再将相应完整目录移回，禁止覆盖新文件。条件项及 SDK 的原路径见各包 `*.before.json` 的 `source` 字段；复原前先校验归档。随后只审阅并撤回对应的候选清单、依赖、模块种子、皮肤 patch 和生成器改动；不要用 `git reset --hard` 覆盖此前修复。重新安装工作区依赖、生成目录并运行测试。源码回退不代表需要恢复远程服务或修改官方 Desktop profile。
