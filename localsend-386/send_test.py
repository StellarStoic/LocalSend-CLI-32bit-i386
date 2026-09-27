#!/usr/bin/env python3
"""send_test.py — a minimal LocalSend protocol v2 sender, stdlib only.

Purpose: verify that a peer's LocalSend receiver actually works, without needing the official GUI
app, a browser, or any dependency. This is the check that proved the 32-bit build works: it spoke
to a freshly installed `localsend-cli` on an Atom netbook over the LAN and the received file's
sha256 matched byte-for-byte.

    python3 send_test.py <host> [port] [filename] [content]

Protocol flow implemented (LocalSend v2):
    1. GET  /api/localsend/v2/info                    -> identify the peer
    2. POST /api/localsend/v2/prepare-upload          -> {info, files} -> {sessionId, files: {id: token}}
    3. POST /api/localsend/v2/upload?sessionId&fileId&token   -> raw file body

TLS: LocalSend peers use self-signed certificates pinned by fingerprint (trust-on-first-use), so
verification is disabled here. That is fine for a LAN test client and NOT fine for anything else.
"""
import hashlib
import json
import ssl
import sys
import urllib.request

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 53317
NAME = sys.argv[3] if len(sys.argv) > 3 else "localsend-protocol-test.txt"
BODY = (sys.argv[4].encode() if len(sys.argv) > 4
        else b"LocalSend protocol test\n")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
FINGERPRINT = "a" * 64          # our own identity; a real client would generate a keypair


def post(path: str, data: bytes, ctype: str = "application/json"):
    req = urllib.request.Request(f"https://{HOST}:{PORT}{path}", data=data,
                                 headers={"Content-Type": ctype}, method="POST")
    with urllib.request.urlopen(req, context=CTX, timeout=30) as r:
        return r.status, r.read()


def main() -> int:
    with urllib.request.urlopen(f"https://{HOST}:{PORT}/api/localsend/v2/info",
                                context=CTX, timeout=10) as r:
        info = json.loads(r.read())
    print(f"peer    : {info.get('alias')} ({info.get('deviceModel')}, protocol {info.get('version')})")

    payload = json.dumps({
        "info": {"alias": "send_test.py", "version": "2.1", "deviceModel": "python",
                 "deviceType": "desktop", "fingerprint": FINGERPRINT, "port": PORT,
                 "protocol": "https", "download": False},
        "files": {"1": {"id": "1", "fileName": NAME, "size": len(BODY),
                        "fileType": "text/plain",
                        "sha256": hashlib.sha256(BODY).hexdigest(), "preview": None}},
    }).encode()

    status, resp = post("/api/localsend/v2/prepare-upload", payload)
    print(f"prepare : HTTP {status} {resp[:120]!r}")
    session = json.loads(resp)
    token = session["files"]["1"]

    status, _ = post(
        f"/api/localsend/v2/upload?sessionId={session['sessionId']}&fileId=1&token={token}",
        BODY, ctype="application/octet-stream")
    print(f"upload  : HTTP {status} ({len(BODY)} bytes)")
    print(f"sha256  : {hashlib.sha256(BODY).hexdigest()}")
    print("\nNow check the receiving side really got it (compare the sha256 above):")
    print(f"  ssh <target> 'ls -la ~/Downloads/localsend-cli/ ; sha256sum ~/Downloads/localsend-cli/{NAME}'")
    return 0 if status < 300 else 1


if __name__ == "__main__":
    raise SystemExit(main())
