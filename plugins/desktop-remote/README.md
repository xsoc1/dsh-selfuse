# Desktop remote relay

Private, dependency-free Host plugin for official Windows Desktop rc.2.
Streams HTTP and native `/api/remote.mux` WebSocket to the same Host's dynamic
loopback port. Native DSH owns authentication, UI, sessions, tools and permissions.

Read [deployment and recovery](../../docs/desktop-remote-20261003.md) before
installation. An exact Tailscale HTTPS authority, port and an
installer-protected state directory are mandatory; legacy owner-browser mode
additionally requires an exact user identity. No usable public defaults.

Run `node --test test.mjs tailnet.test.mjs` in this directory. Unit tests, native installation, real HTTPS, official
Desktop activation and human Safari/mobile acceptance are separate gates.
This is not a remote desktop or file sandbox.

Version 0.2.0 adds explicit `authorizationMode: tailnet`: devices admitted by
the private Serve carrier and network policy can enter the clean root directly.
The relay verifies loopback, exact HTTPS authority, the actual Serve peer address,
no Funnel and allowed Origin before adding a native signed cookie only upstream.
Cookies are minted through native DSH, cached/refreshed in memory, and never sent
to the browser or written to state. Tagged peers do not require a user-login header.
Tailnet members gain the existing Host's file/command/model privileges; no separate
user sandbox or per-device approval is added. Local Desktop authentication is unchanged.
The default remains legacy `owner-browser` unless explicitly switched.

Run `node --test plugins/desktop-remote/test.mjs plugins/desktop-remote/tailnet.test.mjs`
from the manager root. Switch an existing deployment only after normal Desktop exit
using `scripts/desktop-remote-mode.mjs tailnet` in bundled Electron Node mode;
the helper backs up payload/profile, preserves unrelated patch rows and CLI links.
Plain URL QR is optional, not a login credential. See the deployment document.

Version 0.1.1 commits a minimal same-origin document after native authentication
of a browser navigation, before navigating to the clean root. This keeps native
HttpOnly/Secure/SameSite=Strict cookies usable after an external link handoff;
anonymous index, RPC, mux, owner and Origin gates remain unchanged. It does not
implement device pairing. Non-navigation token exchange still returns native 303.
Run `node scripts/verify-desktop-remote-login.mjs` from the manager root against
the installed relay; `--source-relay` checks a temporary source relay without
altering active Serve. Both use fresh browser contexts and make no model calls.
