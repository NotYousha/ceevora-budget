"""Password hashing, JWT tokens and permission/branch authorisation."""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import hmac
import logging
import os
import secrets

import jwt

log = logging.getLogger("ceevora.security")

PERMISSIONS = [
    "BUDGET_VIEW", "BUDGET_CREATE", "BUDGET_SUBMIT", "BUDGET_APPROVE",
    "REVISION_REQUEST", "REVISION_APPROVE", "DASHBOARD_VIEW", "REPORT_VIEW",
    "DRILLDOWN_VIEW", "ADMIN_CONFIG",
]
ROLES = ["ADMIN", "ACCOUNTANT", "FINANCE_MANAGER", "BRANCH_MANAGER"]
DEFAULT_ROLE_PERMISSIONS = {
    "ADMIN": PERMISSIONS,
    "ACCOUNTANT": ["BUDGET_VIEW", "BUDGET_CREATE", "BUDGET_SUBMIT", "REVISION_REQUEST",
                   "DASHBOARD_VIEW", "REPORT_VIEW", "DRILLDOWN_VIEW"],
    "FINANCE_MANAGER": ["BUDGET_VIEW", "BUDGET_APPROVE", "REVISION_APPROVE",
                        "DASHBOARD_VIEW", "REPORT_VIEW", "DRILLDOWN_VIEW"],
    "BRANCH_MANAGER": ["DASHBOARD_VIEW", "REPORT_VIEW", "DRILLDOWN_VIEW"],
}

_secret = os.environ.get("JWT_SECRET")
if not _secret:
    _secret = secrets.token_urlsafe(48)
    log.warning("JWT_SECRET not set: using a random per-process secret (tokens die on restart).")
TOKEN_TTL = dt.timedelta(minutes=int(os.environ.get("TOKEN_TTL_MINUTES", "60")))


def _pbkdf2(password: bytes, salt: bytes, iterations: int) -> bytes:
    if hasattr(hashlib, "pbkdf2_hmac"):
        return hashlib.pbkdf2_hmac("sha256", password, salt, iterations)
    # shortcut: pure-Python PBKDF2 for the in-browser demo (Pyodide has no pbkdf2_hmac); slow, demo only.
    inner, outer = hashlib.sha256(), hashlib.sha256()
    key = password if len(password) <= 64 else hashlib.sha256(password).digest()
    key += bytes(64 - len(key))
    inner.update(bytes(x ^ 0x36 for x in key))
    outer.update(bytes(x ^ 0x5C for x in key))

    def prf(msg: bytes) -> bytes:
        i, o = inner.copy(), outer.copy()
        i.update(msg)
        o.update(i.digest())
        return o.digest()

    u = prf(salt + (1).to_bytes(4, "big"))
    acc = int.from_bytes(u, "big")
    for _ in range(iterations - 1):
        u = prf(u)
        acc ^= int.from_bytes(u, "big")
    return acc.to_bytes(32, "big")


def hash_password(password: str, salt: bytes | None = None, iterations: int = 210_000) -> str:
    salt = salt or os.urandom(16)
    digest = _pbkdf2(password.encode(), salt, iterations)
    return f"pbkdf2_sha256${iterations}${base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _, iterations, salt, digest = stored.split("$")
        calc = _pbkdf2(password.encode(), base64.b64decode(salt), int(iterations))
        return hmac.compare_digest(calc, base64.b64decode(digest))
    except (ValueError, TypeError):
        return False


def issue_token(claims: dict) -> tuple[str, dt.datetime]:
    exp = dt.datetime.now(dt.timezone.utc) + TOKEN_TTL
    return jwt.encode({**claims, "exp": exp}, _secret, algorithm="HS256"), exp


def decode_token(token: str) -> dict:
    return jwt.decode(token, _secret, algorithms=["HS256"])
