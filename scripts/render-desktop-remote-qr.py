"""Render the current entry locally: plain URL for tailnet mode, private URL for legacy mode."""
import json
import sys
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

sys.path.insert(0, "F:/Apps/DeepSeekHarnessRemote/qr-helper")
import qrcode

state = json.load(sys.stdin)
tailnet_mode = state.get("authorizationMode") == "tailnet"
entry = state["publicUrl"] if tailnet_mode else state["loginUrl"]
url = urlsplit(entry)
assert url.scheme == "https" and url.netloc == urlsplit(state["publicUrl"]).netloc
assert url.path == "/" and not url.fragment
assert not url.query if tailnet_mode else len(parse_qs(url.query).get("token", [])) == 1
assert state["status"] == "running"
qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=4)
qr.add_data(entry)
qr.make(fit=True)
destination = Path("F:/Apps/DeepSeekHarnessRemote/state/login-qr.png")
qr.make_image(fill_color="black", back_color="white").save(destination)
print("Tailnet entry QR generated locally; no login token." if tailnet_mode else "Private login QR generated locally; do not publish or share outside your devices.")
