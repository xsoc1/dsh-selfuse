#!/usr/bin/env bash
# Patch @linxin666/dsh-remote-web-ui so Tailscale/tailnet devices can access
# without pairing when remote-web-ui.requirePairingForLan=false.
# Applies to both the bundled lib/ and the src/ tree in the installed package.
set -euo pipefail

profile="${1:-$HOME/.dsh/profiles/web}"
pkg="$profile/node_modules/@linxin666/dsh-remote-web-ui"
if [ ! -f "$pkg/lib/index.js" ]; then
    echo "patch-remote-web-ui: package not found: $pkg" >&2
    exit 1
fi

python3 - "$pkg" <<'PY'
import sys
from pathlib import Path
pkg = Path(sys.argv[1])
changed = []

def replace(path, pairs):
    p = Path(path)
    if not p.exists():
        return
    text = p.read_text(encoding='utf-8')
    original = text
    for old, new in pairs:
        if old in text:
            text = text.replace(old, new, 1)
    if text != original:
        p.write_text(text, encoding='utf-8')
        changed.append(str(p.relative_to(pkg)))

# ---- src/mobile-api.ts ----
src_mobile = pkg / 'src/mobile-api.ts'
if src_mobile.exists():
    text = src_mobile.read_text(encoding='utf-8')
    o = text
    text = text.replace(
        "  /** The resolved mobile composer preference (live per request). */\n  mobileEnterToSend: () => boolean\n",
        "  /** The resolved mobile composer preference (live per request). */\n  mobileEnterToSend: () => boolean\n  /** Live LAN-pairing requirement, resolved per request. */\n  requirePairingForLan?: () => boolean\n", 1)
    text = text.replace(
        "  const { service, apiProxy, mobileEnterToSend } = deps",
        "  const { service, apiProxy, mobileEnterToSend, requirePairingForLan } = deps", 1)
    # replace whatever gateOk exists (unpatched or previous wrong patch)
    if "requirePairingForLan?.() === false" in text:
        pass
    else:
        # remove any known previous form and insert correct
        import re
        text = re.sub(
            r"  const gateOk = \(req: IncomingMessage\): boolean => \{\n(?:.*\n)*?  \};",
            "  const gateOk = (req: IncomingMessage): boolean => {\n    if (requirePairingForLan?.() === false) return true\n    return touchDeviceFor(req)\n  };",
            text, count=1, flags=re.MULTILINE)
    if text != o:
        src_mobile.write_text(text, encoding='utf-8')
        changed.append('src/mobile-api.ts')

# ---- src/remote-api.ts ----
src_remote = pkg / 'src/remote-api.ts'
if src_remote.exists():
    text = src_remote.read_text(encoding='utf-8')
    o = text
    text = text.replace(
        "  /** The local webServer port the loopback proxy connects to. */\n  port: number\n}",
        "  /** The local webServer port the loopback proxy connects to. */\n  port: number\n  /** Live LAN-pairing requirement, resolved per request. */\n  requirePairingForLan?: () => boolean\n}", 1)
    text = text.replace("  const { service, port } = deps", "  const { service, port, requirePairingForLan } = deps")
    text = text.replace(
        "    const paired = deviceId !== undefined && service.touchDevice(deviceId)",
        "    const paired = requirePairingForLan?.() === false || (deviceId !== undefined && service.touchDevice(deviceId))", 1)
    text = text.replace(
        "    if (deviceId === undefined || !service.touchDevice(deviceId)) {",
        "    if (requirePairingForLan?.() !== false && (deviceId === undefined || !service.touchDevice(deviceId))) {", 1)
    if text != o:
        src_remote.write_text(text, encoding='utf-8')
        changed.append('src/remote-api.ts')

# ---- src/index.ts call sites ----
src_index = pkg / 'src/index.ts'
if src_index.exists():
    text = src_index.read_text(encoding='utf-8')
    o = text
    text = text.replace(
        "mobileEnterToSend: () => resolve().mobileEnterToSend })",
        "mobileEnterToSend: () => resolve().mobileEnterToSend, requirePairingForLan: () => resolve().requirePairingForLan })", 1)
    text = text.replace(
        "makeRemoteApiRoutes({ service, port: ctx.webServer.port })",
        "makeRemoteApiRoutes({ service, port: ctx.webServer.port, requirePairingForLan: () => resolve().requirePairingForLan })", 1)
    text = text.replace(
        "makeRemoteApiUpgradeRoutes({ service, port: ctx.webServer.port })",
        "makeRemoteApiUpgradeRoutes({ service, port: ctx.webServer.port, requirePairingForLan: () => resolve().requirePairingForLan })", 1)
    if text != o:
        src_index.write_text(text, encoding='utf-8')
        changed.append('src/index.ts')

# ---- lib/index.js (runtime loaded code) ----
lib = pkg / 'lib/index.js'
text = lib.read_text(encoding='utf-8')
o = text
text = text.replace("\tconst { service, apiProxy, mobileEnterToSend } = deps;", "\tconst { service, apiProxy, mobileEnterToSend, requirePairingForLan } = deps;", 1)
# replace any previous gateOk forms
import re
if "requirePairingForLan?.() === false" in text:
    pass
else:
    text = re.sub(
        r"\tconst gateOk = \(req\) => \{\n(?:.*\n)*?\t\};",
        "\tconst gateOk = (req) => {\n\t\tif (requirePairingForLan?.() === false) return true;\n\t\treturn touchDeviceFor(req);\n\t};",
        text, count=1, flags=re.MULTILINE)
text = text.replace(
    "mobileEnterToSend: () => resolve().mobileEnterToSend\n\t\t})",
    "mobileEnterToSend: () => resolve().mobileEnterToSend,\n\t\t\trequirePairingForLan: () => resolve().requirePairingForLan\n\t\t})", 1)
# replace previous wrong checks if present
text = text.replace(
    "\t\tif (service.config.requirePairingForLan !== false && !(deviceId !== void 0 && service.touchDevice(deviceId))) {",
    "\t\tif (requirePairingForLan?.() !== false && !(deviceId !== void 0 && service.touchDevice(deviceId))) {", 1)
text = text.replace(
    "\t\tif (service.config.requirePairingForLan !== false && (deviceId === void 0 || !service.touchDevice(deviceId))) {",
    "\t\tif (requirePairingForLan?.() !== false && (deviceId === void 0 || !service.touchDevice(deviceId))) {", 1)
# destructure remote routes (2 occurrences)
text = text.replace("\tconst { service, port } = deps;", "\tconst { service, port, requirePairingForLan } = deps;")
# remote route call
text = text.replace(
    "makeRemoteApiRoutes({\n\t\t\tservice,\n\t\t\tport: ctx.webServer.port\n\t\t})",
    "makeRemoteApiRoutes({\n\t\t\tservice,\n\t\t\tport: ctx.webServer.port,\n\t\t\trequirePairingForLan: () => resolve().requirePairingForLan\n\t\t})", 1)
# remote upgrade call
text = text.replace(
    "makeRemoteApiUpgradeRoutes({\n\t\tservice,\n\t\tport: ctx.webServer.port\n\t})",
    "makeRemoteApiUpgradeRoutes({\n\t\tservice,\n\t\tport: ctx.webServer.port,\n\t\trequirePairingForLan: () => resolve().requirePairingForLan\n\t})", 1)
if text != o:
    lib.write_text(text, encoding='utf-8')
    changed.append('lib/index.js')

# ---- src/client/index.ts: never install remote desktop channel ----
src_client = pkg / 'src/client/index.ts'
if src_client.exists():
    text = src_client.read_text(encoding='utf-8')
    o = text
    import re as _re
    if 'return false' in text and 'channelActive' in text:
        pass
    else:
        text = _re.sub(
            r"  const channelActive = \(\): boolean => \{\n(?:.*\n)*?  \}",
            "  const channelActive = (): boolean => {\n    // Local maintenance: Tailscale/tailnet is trusted; remote pairing is disabled.\n    return false\n  }",
            text, count=1, flags=_re.MULTILINE)
    if text != o:
        src_client.write_text(text, encoding='utf-8')
        changed.append('src/client/index.ts')

# ---- lib/client.js: server-served desktop bundle never uses remote channel ----
lib_client = pkg / 'lib/client.js'
if lib_client.exists():
    text = lib_client.read_text(encoding='utf-8')
    o = text
    if 'return false;' in text and 'channelActive' in text:
        pass
    else:
        text = _re.sub(
            r"\t\t\tconst channelActive = \(\) => \{\n(?:.*\n)*?\t\t\t\};",
            "\t\t\tconst channelActive = () => {\n\t\t\t\treturn false;\n\t\t\t};",
            text, count=1, flags=_re.MULTILINE)
    if text != o:
        lib_client.write_text(text, encoding='utf-8')
        changed.append('lib/client.js')

if changed:
    print('patch-remote-web-ui: applied to ' + ', '.join(changed))
else:
    print('patch-remote-web-ui: already patched')
PY
