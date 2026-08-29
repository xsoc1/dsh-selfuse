#!/usr/bin/env bash
# Launch dsh web inside WSL with a clean Linux PATH.
# This avoids passing Windows PATH (C:\Program Files (x86)\...) into bash,
# which can break inline `bash -lc` commands. Use this script from Windows:
#   wsl.exe -d Ubuntu -- bash /home/huangzy/tools/dsh-local/scripts/run-dsh-wsl.sh [...]
set -euo pipefail

export PATH="/home/huangzy/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DSH_HOME="/home/huangzy/.dsh"
unset DSH_SESSION_ID DSH_SESSION_JSONL DSH_WEB_URL DSH_WSL_DISTRO NODE_OPTIONS

cd /home/huangzy/tools/deepseek-harness
exec node --import tsx/esm apps/cli/src/bin.ts web --host 127.0.0.1 --no-open "$@"
