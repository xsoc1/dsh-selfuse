#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
fixture_root=$(mktemp -d)
trap 'rm -rf -- "$fixture_root"' EXIT
bare="$fixture_root/origin.git"
repo="$fixture_root/worktree"
other="$fixture_root/upstream"
git init -q --bare "$bare"
git init -q -b master "$repo"
printf '{"version":"0.0.1"}\n' > "$repo/package.json"
git -C "$repo" add package.json
git -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
git -C "$repo" remote add origin "$bare"
git -C "$repo" push -q -u origin master
git -C "$bare" symbolic-ref HEAD refs/heads/master

before=$(git -C "$repo" show-ref)
clean=$(bash "$script_dir/../dsh-update-preflight.sh" "$repo")
[[ "$clean" == *'未提交项: 0'* ]]
[[ "$clean" == *'远端 HEAD 已包含于当前工作树'* ]]
[[ "$clean" == *'代码回退锚点: 尚无'* ]]
[[ "$(git -C "$repo" show-ref)" == "$before" ]]

git -C "$repo" branch backup/preflight
printf 'not committed\n' > "$repo/dirty.txt"
dirty=$(bash "$script_dir/../dsh-update-preflight.sh" "$repo")
[[ "$dirty" == *'未提交项: 1'* ]]
[[ "$dirty" == *'代码回退锚点: backup/preflight'* ]]

git clone -q "$bare" "$other"
printf 'upstream\n' > "$other/new.txt"
git -C "$other" add new.txt
git -C "$other" -c user.name=Test -c user.email=test@example.invalid commit -qm upstream
git -C "$other" push -q origin master
before=$(git -C "$repo" show-ref)
ahead=$(bash "$script_dir/../dsh-update-preflight.sh" "$repo")
[[ "$ahead" == *'远端提交不在本地对象库'* ]]
[[ "$(git -C "$repo" show-ref)" == "$before" ]]

git -C "$repo" remote set-url origin 'https://user:secret@127.0.0.1:1/repo.git'
redacted=$(bash "$script_dir/../dsh-update-preflight.sh" "$repo")
[[ "$redacted" == *'origin: https://127.0.0.1:1/repo.git'* ]]
[[ "$redacted" != *secret* ]]
[[ "$redacted" == *'预检只读:'* ]]

printf 'GREEN read-only update preflight cases passed\n'
