# skills

技能集合规范源。

- `mattpocock-skills`（35 个技能）→ 建议 submodule 到 `xsoc1/skills` 或 vendored。
- `math-research-dsh`（4 个数学技能）→ submodule 到 `xsoc1/math-research-dsh`。

安装器会为每个技能在 `~/.dsh/skills/<name>` 创建 junction，使 `git pull` 后热更新。
