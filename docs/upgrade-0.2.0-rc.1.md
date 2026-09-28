# DSH 0.2.0-rc.1 自用升级与第三方插件复建

本页记录 2026-09-29 的候选验证与随后完成的**本机切换**，区分云端子模块和真正运行的服务。官方 `deepseek-ai/deepseek-harness` 基线为 `4878cdabd87d4041bdaff61d04c966883b9fd07a`（`0.2.0-rc.1`）。本仓 `vendor/deepseek-harness` 锁定包含该提交及 selfuse 适配的 fork 提交 `bcf8c14b1927fb1ee3701e5e3852ff2c3ef25249`；本机活跃链接已指向该提交，但以后仍须用 `readlink -f /home/huangzy/tools/deepseek-harness-current` 单独核对。

## 归属与隐私边界

- `vendor/deepseek-harness/config/selfuse/` 是 profile 与设置模板源码；`scripts/selfuse/` 是生成与安装入口。`/home/huangzy/.dsh` 是用户数据，不入 Git，不可用仓库快照整目录覆盖。
- 原生 `dsh plugin --profile web add` 管理外部包。生成器保留 profile 的外部依赖和 bundle；`rowConfigs` 内的 `${DSH_HOME}/` 路径按选定用户目录展开。隔离测试必须指定临时 `DSH_HOME`，并为灵枢记忆设置临时 `MDCG_AUX_ROOT`。
- `@dsh-selfuse/content-risk-guard` 只在本机隔离检测到的网络配置、拦截受污染的模型请求。它不能关闭、规避或保证预测服务商的上游安全策略；旧会话若已含原文，应新建会话。
- 当前管理仓根目录的 `install.ps1`、旧 `config/` 与旧 `community-plugins/` 是历史快照，不用于本次 WSL 部署。

## 第三方版本锁定

| 插件 | 上游来源 | 本次锁定 | 获取方式 |
|---|---|---|---|
| 提示词优化器 | [WestFox-AwA/dsh-prompt-optimizer](https://github.com/WestFox-AwA/dsh-prompt-optimizer) | Release `v0.7.6`，包 SHA-256 `e98ec8ea935cea4c8634b07ad3daffde35d1194f0132a9c1f68f3c31f95bbdee` | 仅取上游 Release `dsh-external-dsh-po06-0.7.6.tgz`，对照同版 `SHA256SUMS-0.7.6.txt` |
| 灵枢记忆 | [FuRongJun-1999/dsh-memory](https://github.com/FuRongJun-1999/dsh-memory) | 上游提交 `a84e78d2d5024fef60e9244201323baae1f0b8ee`、版本 `0.6.0`，本地构建版 `0.6.0-selfuse.1` | 对该提交应用 [`dsh-memory-0.6.0-selfuse.1.patch`](../community-plugins/patches/dsh-memory-0.6.0-selfuse.1.patch) 后构建；本机 tarball SHA-256 `c75d703c052facb0112a2477caef79194210fd4163736f8c0b7ff877ff5e9d6c` |

灵枢的补丁保留本地要求：包含代理 URI、带账户密码 URL 或代理 YAML 块的文本不进入自动记忆；旧记忆的自动时间线预览也先过滤。它不是通用秘密检测器，手动读取旧记忆仍需 `content-risk-guard` 在工具结果与模型请求处检查。补丁测试使用虚构的 `example.test`，不含真实节点或凭据。

## 从锁定源码复建并验证

以下命令在**独立目录和临时用户目录**运行；不要把现用 `/home/huangzy/.dsh` 当作试验目录。克隆本仓后先检查 `git submodule status vendor/deepseek-harness`，在子模块根目录安装锁定依赖并运行：

```bash
pnpm install --frozen-lockfile
pnpm run build
pnpm run doc-sync
node --test scripts/selfuse/install.test.mjs
node node_modules/vitest/vitest.mjs run packages/selfuse/content-risk-guard/tests
```

提示词优化器只使用上游 Release 附件，按其同版校验文件核对哈希；不要误装 npm 上旧名 `@dsh-external/dsh-prompt-optimizer`。灵枢复建如下（`<selfuse>` 换成管理仓绝对路径）。补丁为零上下文格式，仅对上表锁定的上游提交使用；若 `--check` 失败，应停下核对版本，不要强行套用。

```bash
git clone https://github.com/FuRongJun-1999/dsh-memory.git dsh-memory-0.6.0-selfuse
cd dsh-memory-0.6.0-selfuse
git checkout a84e78d2d5024fef60e9244201323baae1f0b8ee
git apply --check --unidiff-zero <selfuse>/community-plugins/patches/dsh-memory-0.6.0-selfuse.1.patch
git apply --unidiff-zero <selfuse>/community-plugins/patches/dsh-memory-0.6.0-selfuse.1.patch
npm ci --include=dev
npm test
node --import tsx test/verify_desensitize.ts
npm pack --ignore-scripts
```

生成临时 profile 后，先用原生 CLI 将两个校验过的 tarball 安装到**该临时 profile**，再运行 `dsh --profile web --dump-config`；清单必须出现 `@dsh-external/dsh-po06`、`@furongjun1999/dsh-memory` 和 `@dsh-selfuse/content-risk-guard`。`profiles.build.yml` 的记忆行在外部包尚未安装时会报 `entry "furongjun1999-dsh-memory" not found`，所以不要把安装前的 dump 当作升级失败。隔离启动时要在生成的 profile 核对灵枢 `mdcg.root` 位于临时 `DSH_HOME`，且 `MDCG_AUX_ROOT` 也指向临时目录；用程序打印的登录链接换取 Cookie，再核对首页 HTTP 200，而非只看 3080 端口已监听。

向现用环境切换前，应备份 profile、设置与记忆，核对两个外部包的版本和来源，再用 `node scripts/selfuse/install.mjs --dry-run --dsh-home /home/huangzy/.dsh` 预览。实际切换源码链接、安装插件和重启服务是独立步骤；云端提交本身不会执行它们。重启后还需检查插件列表、会话恢复、远程 WebSocket 与 iPad Safari 的真实交互。未做这些检查时，不得声称现用服务或 iPad 已完成升级。

## 本次验证与已知事件

在候选源码中，`doc-sync` 42/42、全量构建、profile 生成器定向测试 9/9、内容隔离插件测试 20/20 均通过。灵枢 `0.6.0-selfuse.1` 的隐私样例 19/19、其上游 Node 测试 71 通过、3 跳过；上游提示词优化器 Release 校验文件与包 SHA-256 一致。隔离 Web 在原样打印的登录链接上返回 303，再带 Cookie 取首页返回 200；这只证明该本机装配与入口工作，不证明 iPad/Tailnet 或真实模型调用。

全仓 `pnpm run lint` 仍报告 1417 项错误及 5 项警告，主要来自既有自用源码；本次变更的 staged lint 和提交 hook 通过。文档门禁 42/42 通过不等于全仓 lint 通过，后者是单独的待清理技术债。

随后停止旧 Web 进程，备份现用 profile、settings、会话和记忆至 `/home/huangzy/.dsh/maintenance-backups/upgrade-20260929-FvYBA5`（约 171 MiB）；使用原生 `dsh plugin` CLI 在现用 profile 装入上述两个新包，切换源码链接并重启。一次旧进程自动重启占用了 3080，导致首个新版启动报 `EADDRINUSE`；停止该旧进程后重启成功。复核进程工作目录为新提交、插件实际版本分别为 `0.7.6` 与 `0.6.0-selfuse.1`、`--dump-config` 含内容隔离插件与两个外部插件、本机登录链路为 303→200（HTML 39178 字节），Tailnet HTTPS 入口返回预期的未登录 401（约 72 ms），Tailscale 正在运行且 Serve 指向 3080、未发现 Funnel。未从 iPad 发消息，也未作真实模型请求；这些结论不得延伸为设备端会话同步已验证。

当前远程配置显式使用 `requirePairingForLan: false` 与 Tailnet trusted-host，启动日志因普通 `/api` 对该主机开放发出 CRITICAL 告警。这是既有“只依赖 Tailnet 成员身份”的部署选择，不是安全的默认配对模式；不得开放 Funnel 或把该入口变为公网地址。若希望恢复设备配对与 `/remote/api` 围栏，须联动去掉对应 `--trusted-host` 并进行 iPad 端到端复测，不能只改一个开关。

第一次隔离启动前，旧 profile 模板仍把灵枢 `mdcg.root` 写死到现用目录。日志报告 1 项索引哈希漂移并进行了增量修复；随即停止进程。只读检查显示当时 3 个近期写入文件位于索引日志、锁和对账日志，未观察到记忆正文文件近期写入；不能据此声称该操作已回滚。随后把模板改为 `${DSH_HOME}` 展开，并以先失败后通过的回归测试固定此行为，第二次启动确认记忆根和凭据辅助根都在临时目录。
