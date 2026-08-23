#!/usr/bin/env bash
# Keep unused @linxin666/dsh-web-ui-all sub-plugins out of the loader patch.
# This is the WSL/Linux counterpart of prune-web-ui.ps1. It only strips
# loader rows; it never deletes package directories (dsh client-modules needs
# them by dependency path).
set -euo pipefail

profile="${1:-$HOME/.dsh/profiles/web}"
if [ "$1" = "-p" ] && [ -n "$2" ]; then profile="$2"; fi
patch="$profile/node_modules/@linxin666/dsh-web-ui-all/cordis.patch.yml"

if [ ! -f "$patch" ]; then
    echo "prune-web-ui: no aggregate patch at $patch"
    exit 0
fi

tmp="$patch.tmp"
awk '
    /^# from .*(dsh-pet|dsh-tool-describe-image|dsh-client-ui-aionui-panel|dsh-liangshen|dsh-client-ui-skill-explorer|dsh-desktop-launcher|dsh-client-ui-plugin-manager)/ {
        skip=1
        next
    }
    skip && /^- insert:/ { insert=1; next }
    skip && insert && /^    - id:/ { next }
    skip && insert && /^      name:/ { skip=0; insert=0; next }
    { print }
' "$patch" > "$tmp"

if cmp -s "$patch" "$tmp"; then
    rm -f "$tmp"
    echo "prune-web-ui: already clean"
else
    mv "$tmp" "$patch"
    echo "prune-web-ui: stripped unwanted loader rows from $patch"
fi
