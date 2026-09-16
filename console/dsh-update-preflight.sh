#!/usr/bin/env bash
set -u
trap 'printf "预检只读: 未 fetch、合并、重置、构建或重启\\n"' EXIT

repo_path=${1:-/home/huangzy/tools/deepseek-harness-current}
resolved_path=$(readlink -f -- "$repo_path" 2>/dev/null) || resolved_path=
if [[ -z "$resolved_path" || ! -d "$resolved_path/.git" && ! -f "$resolved_path/.git" ]]; then
  printf '工作树: 不可用（%s）\n' "$repo_path"
  exit 1
fi
cd -- "$resolved_path" || exit 1

printf '活跃 WSL 工作树: %s\n' "$resolved_path"
printf '当前分支: %s\n' "$(git branch --show-current)"
local_head=$(git rev-parse HEAD) || exit 1
printf '当前 HEAD: %.12s\n' "$local_head"
version=$(node -p 'require("./package.json").version' 2>/dev/null) || version=unknown
printf '当前版本: %s\n' "$version"

dirty_count=$(GIT_OPTIONAL_LOCKS=0 git status --porcelain=v1 | wc -l) || dirty_count=unknown
printf '未提交项: %s\n' "$dirty_count"
if [[ "$dirty_count" != 0 ]]; then
  printf '更新条件: 先审查并保存未提交更改\n'
fi

backup_ref=
while IFS=' ' read -r ref object; do
  if [[ "$object" == "$local_head" ]]; then
    backup_ref=$ref
    break
  fi
done < <(git for-each-ref --format='%(refname:short) %(objectname)' refs/heads/backup/)
if [[ -n "$backup_ref" ]]; then
  printf '代码回退锚点: %s（当前 HEAD）\n' "$backup_ref"
else
  printf '代码回退锚点: 尚无指向当前 HEAD 的备份分支；更新前需建立\n'
fi

origin_url=$(git remote get-url origin 2>/dev/null) || origin_url=
if [[ -z "$origin_url" ]]; then
  printf 'origin: 未配置；无法查询上游\n'
  exit 0
fi
origin_display=$origin_url
if [[ "$origin_url" == *://*@* ]]; then
  origin_display="${origin_url%%://*}://${origin_url##*@}"
fi
printf 'origin: %s\n' "$origin_display"

remote_status=$(timeout -k 1s 6s env GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never git ls-remote --symref origin HEAD 2>/dev/null)
remote_exit=$?
if [[ $remote_exit -ne 0 ]]; then
  if [[ $remote_exit -eq 124 || $remote_exit -eq 137 ]]; then
    printf '远端 HEAD: 查询超时；未判断是否有更新\n'
  else
    printf '远端 HEAD: 查询失败；未判断是否有更新\n'
  fi
  exit 0
fi

remote_ref=$(awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }' <<< "$remote_status")
remote_head=$(awk '$2 == "HEAD" && $1 != "ref:" { print $1; exit }' <<< "$remote_status")
if [[ ! "$remote_head" =~ ^[0-9a-fA-F]{40}$ ]]; then
  printf '远端 HEAD: 格式不可识别；未判断是否有更新\n'
  exit 0
fi
printf '远端分支: %s\n' "${remote_ref:-unknown}"
printf '远端 HEAD: %.12s\n' "$remote_head"

if git cat-file -e "${remote_head}^{commit}" 2>/dev/null; then
  if git merge-base --is-ancestor "$remote_head" HEAD; then
    printf '上游状态: 远端 HEAD 已包含于当前工作树\n'
  else
    printf '上游状态: 远端 HEAD 未包含；需人工审查提交差异\n'
  fi
else
  printf '上游状态: 远端提交不在本地对象库；需人工获取并审查差异\n'
fi
