"""In-browser demo backend: runs the real FastAPI app (backend/app) inside Pyodide.

Pyodide has no threads, so FastAPI's threadpool hop is replaced by a direct call, and requests are fed to the
ASGI app directly instead of over a socket. Used only by the GitHub Pages demo build.
"""
import json
import os
import secrets
import sqlite3
from urllib.parse import urlsplit

os.environ.setdefault("JWT_SECRET", secrets.token_urlsafe(48))
os.environ["CEEVORA_TENANTS_FILE"] = "/demo/tenants.json"
os.environ["WEB_DIR"] = "/nonexistent"
with open("/demo/tenants.json", "w") as f:
    json.dump({"DEMO": {"dialect": "sqlite", "path": "/demo/demo.db"}}, f)


async def _direct(func, *args, **kwargs):
    return func(*args, **kwargs)


import starlette.concurrency  # noqa: E402

starlette.concurrency.run_in_threadpool = _direct
import fastapi.dependencies.utils  # noqa: E402
import fastapi.routing  # noqa: E402
import starlette._exception_handler  # noqa: E402
import starlette.routing  # noqa: E402

for mod in (fastapi.routing, fastapi.dependencies.utils, starlette._exception_handler, starlette.routing):
    if hasattr(mod, "run_in_threadpool"):
        mod.run_in_threadpool = _direct

from app.main import app  # noqa: E402
from app.security import hash_password  # noqa: E402

# Pure-Python PBKDF2 at 210,000 rounds takes minutes in WebAssembly. The demo password is public anyway, so the
# in-browser copy re-hashes the seeded demo users with 1,000 rounds (the server build keeps 210,000).
_con = sqlite3.connect("/demo/demo.db")
for _uid, _hash in _con.execute("SELECT USER_ID, PASSWORD_HASH FROM DM_USERS").fetchall():
    if _hash.split("$")[1] != "1000":
        _con.execute("UPDATE DM_USERS SET PASSWORD_HASH = ? WHERE USER_ID = ?",
                     (hash_password("Demo@2027", salt=f"ceevora-demo-{_uid}".encode(), iterations=1000), _uid))
_con.commit()
_con.close()


async def handle(method: str, url: str, headers_json: str, body: str | None) -> str:
    u = urlsplit(url)
    raw = (body or "").encode()
    headers = [(k.lower().encode(), str(v).encode()) for k, v in json.loads(headers_json or "{}").items()]
    if raw and not any(k == b"content-type" for k, _ in headers):
        headers.append((b"content-type", b"application/json"))
    headers.append((b"content-length", str(len(raw)).encode()))
    scope = {"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": method.upper(),
             "scheme": "https", "path": u.path, "raw_path": u.path.encode(), "query_string": u.query.encode(),
             "root_path": "", "headers": headers, "client": ("127.0.0.1", 0), "server": ("demo", 443)}
    sent = {"body": False}

    async def receive():
        if sent["body"]:
            return {"type": "http.disconnect"}
        sent["body"] = True
        return {"type": "http.request", "body": raw, "more_body": False}

    out = {"status": 500, "headers": {}, "body": b""}

    async def send(msg):
        if msg["type"] == "http.response.start":
            out["status"] = msg["status"]
            out["headers"] = {k.decode(): v.decode() for k, v in msg.get("headers", [])}
        elif msg["type"] == "http.response.body":
            out["body"] += msg.get("body", b"")

    await app(scope, receive, send)
    return json.dumps({"status": out["status"], "headers": out["headers"], "body": out["body"].decode("utf-8")})
