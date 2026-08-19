# vendor

外部源码仓库（submodule）规范区。

已登记 submodule：

- `deepseek-harness/` → `xsoc1/deepseek-harness`（fork，分支 `local/image-admission`）
- `awesome-dsh-plugin/` → `xsoc1/awesome-dsh-plugin`（fork，main）

> 当前工作区未实际 clone submodule 内容（只有 gitlink 记录），
> 安装/使用时执行：
> ```powershell
> git submodule update --init --recursive
> ```
> 或由 `install.ps1` 自动处理。

未登记：
- `deepseek-harness-eac/`：用户确认不 fork，暂不纳入。
- `mattpocock-skills/`、`math-research-dsh/`：已作为 vendored 副本放在 `skills/`，后续可改为 submodule。
