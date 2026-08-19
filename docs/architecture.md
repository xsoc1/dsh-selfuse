# dsh-local 架构说明

## 1. 运行时拓扑（现状）

```text
Windows 主机
├─ F:\tools\deepseek-harness        # dsh 源码运行区（pnpm dsh web）
├─ F:\tools\Deepseek-Harness-EAC    # EAC 桌面封装源码
├─ F:\tools\ollama                  # 便携 Ollama，qwen3-vl:4b，端口 11810
├─ F:\tools\image-gen               # SDXL-Turbo 生图服务，端口 17821
├─ F:\tools\community-plugins\*     # 第三方插件（部分被 profile link）
├─ F:\tools\plugins?                # 自研插件（当前散在 F:\tools 根）
└─ %USERPROFILE%\.dsh
   ├─ settings.yaml
   ├─ profiles\web\                 # 实际 web profile
   ├─ skills\                       # junction 到 mattpocock / math-research
   ├─ .agent-presets\               # router-standard 等
   └─ memory\                       # 本地记忆
```

## 2. 目标拓扑

```text
GitHub
├─ xsoc1/deepseek-harness   (fork, 源码)
└─ xsoc1/dsh-local          (管理仓, 本仓库)

本地
├─ F:\tools\dsh-local               # clone 管理仓
│  ├─ vendor\deepseek-harness       # submodule -> fork
│  ├─ plugins\...                   # 自研插件规范源
│  ├─ community-plugins\...         # 第三方补丁规范源
│  ├─ config\...                    # profile/settings/presets 规范源
│  ├─ scripts\...                   # 管理脚本规范源
│  └─ services\...                  # 本地服务代码规范源
└─ %USERPROFILE%\.dsh
   ├─ settings.yaml                 # 由 install.ps1 从 config 同步
   ├─ profiles\web -> junction -> F:\tools\dsh-local\config\profiles\web
   ├─ skills\... -> junction -> dsh-local 内技能源
   └─ .agent-presets\... -> junction/复制 -> config\agent-presets
```

## 3. 数据流

1. **维护**：人类/agent 修改 `dsh-local` 中对应文件。
2. **安装/同步**：`install.ps1` 把规范源同步到 `~/.dsh` 与运行区（junction 或复制）。
3. **运行**：dsh 读取 `~/.dsh`；插件通过 profile 的相对 link 指向 dsh-local 内源码。
4. **升级**：`git -C vendor/deepseek-harness pull` 等更新 submodule；本地补丁分支单独维护。

## 4. 关键设计决策

- **双仓分离**：源码 fork 与管理仓分离，避免个人内容污染上游同步。
- **相对 link**：profile package.json 用 `link:../../../...`，仓库可移动。
- **junction 优先**：技能/agent-presets/profile 用 Windows junction 指向仓库，`git pull` 后热更新。
- **二进制不入库**：模型通过 manifest + 下载/导入脚本管理。
- **manifest.json 驱动**：安装器与 agent 都从同一清单读取组件信息，避免文档漂移。
