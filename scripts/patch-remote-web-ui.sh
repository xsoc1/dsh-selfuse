#!/usr/bin/env bash
# Patch @linxin666/dsh-remote-web-ui so Tailscale/tailnet devices can access
# without pairing when remote-web-ui.requirePairingForLan=false.
# This is a local maintenance patch for the npm-installed plugin.
set -euo pipefail

profile="${1:-$HOME/.dsh/profiles/web}"
file="$profile/node_modules/@linxin666/dsh-remote-web-ui/lib/index.js"

if [ ! -f "$file" ]; then
    echo "patch-remote-web-ui: file not found: $file" >&2
    exit 1
fi

python3 - "$file" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
changed = False

old1 = "\tconst gateOk = (req) => {\n\t\treturn touchDeviceFor(req);\n\t};"
new1 = "\tconst gateOk = (req) => {\n\t\tif (service.config.requirePairingForLan === false) return true;\n\t\treturn touchDeviceFor(req);\n\t};"
if old1 in text:
    text = text.replace(old1, new1, 1)
    changed = True

old2 = "\t\tconst deviceId = readCookie(req.headers.cookie, service.config.cookieName);\n\t\tif (!(deviceId !== void 0 && service.touchDevice(deviceId))) {"
new2 = "\t\tconst deviceId = readCookie(req.headers.cookie, service.config.cookieName);\n\t\tif (service.config.requirePairingForLan !== false && !(deviceId !== void 0 && service.touchDevice(deviceId))) {"
if old2 in text:
    text = text.replace(old2, new2, 1)
    changed = True

old3 = "\t\tconst deviceId = readCookie(req.headers.cookie, service.config.cookieName);\n\t\tif (deviceId === void 0 || !service.touchDevice(deviceId)) {"
new3 = "\t\tconst deviceId = readCookie(req.headers.cookie, service.config.cookieName);\n\t\tif (service.config.requirePairingForLan !== false && (deviceId === void 0 || !service.touchDevice(deviceId))) {"
if old3 in text:
    text = text.replace(old3, new3, 1)
    changed = True

if changed:
    open(path, 'w', encoding='utf-8').write(text)
    print('patch-remote-web-ui: applied pairing-bypass patch')
else:
    print('patch-remote-web-ui: already patched or patterns not found')
PY
