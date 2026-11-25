"""Tenant-resolved database access. Oracle (python-oracledb thin, pooled) or SQLite (standalone demo).

The client never supplies connection details: the tenant code inside the signed token is looked up
in the server-side registry (tenants.json) which names environment variables holding credentials.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sqlite3
import threading
from contextlib import contextmanager
from decimal import Decimal
from pathlib import Path

try:
    import oracledb
    oracledb.defaults.fetch_decimals = True
except ImportError:  # in-browser demo (Pyodide) has no Oracle driver; SQLite tenants only
    oracledb = None

sqlite3.register_adapter(Decimal, str)
sqlite3.register_adapter(dt.date, lambda d: d.isoformat())
sqlite3.register_adapter(dt.datetime, lambda d: d.isoformat(sep=" ", timespec="seconds"))

BACKEND_DIR = Path(__file__).resolve().parent.parent
_pools: dict = {}
_lock = threading.Lock()


class TenantError(Exception):
    pass


def registry() -> dict:
    path = Path(os.environ.get("CEEVORA_TENANTS_FILE", BACKEND_DIR / "tenants.json"))
    # Keys starting with "_" are documentation examples, never live tenants.
    return {k: v for k, v in json.loads(path.read_text(encoding="utf-8")).items() if not k.startswith("_")}


def tenant_config(code: str) -> dict:
    cfg = registry().get((code or "").upper())
    if not cfg:
        raise TenantError("Unknown tenant")
    return cfg


def as_date(v) -> dt.date | None:
    if v is None or isinstance(v, dt.date) and not isinstance(v, dt.datetime):
        return v
    if isinstance(v, dt.datetime):
        return v.date()
    return dt.date.fromisoformat(str(v)[:10])


class Db:
    def __init__(self, conn, dialect: str):
        self.conn, self.dialect = conn, dialect

    def _cur(self, sql, params):
        cur = self.conn.cursor()
        cur.execute(sql, params or {})
        return cur

    def query(self, sql: str, params: dict | None = None) -> list[dict]:
        cur = self._cur(sql, params)
        cols = [c[0].lower() for c in cur.description]
        rows = cur.fetchall()
        if self.dialect == "sqlite":
            return [{k: (Decimal(repr(v)) if isinstance(v, float) else v) for k, v in zip(cols, r)} for r in rows]
        return [{k: (v.read() if isinstance(v, oracledb.LOB) else v) for k, v in zip(cols, r)} for r in rows]

    def one(self, sql: str, params: dict | None = None) -> dict | None:
        rows = self.query(sql, params)
        return rows[0] if rows else None

    def execute(self, sql: str, params: dict | None = None) -> int:
        return self._cur(sql, params).rowcount

    def insert(self, table: str, row: dict, pk: str | None = None) -> int | None:
        cols = ", ".join(row)
        binds = ", ".join(f":{k}" for k in row)
        sql = f"INSERT INTO {table} ({cols}) VALUES ({binds})"
        cur = self.conn.cursor()
        if pk and self.dialect == "oracle":
            out = cur.var(int)
            cur.execute(f"{sql} RETURNING {pk} INTO :out_id", {**row, "out_id": out})
            return out.getvalue()[0]
        cur.execute(sql, row)
        return cur.lastrowid if pk else None

    def for_update(self, sql: str) -> str:
        # SQLite serialises writers with BEGIN IMMEDIATE instead of row locks.
        return sql + " FOR UPDATE" if self.dialect == "oracle" else sql

    def page(self, sql: str, offset: int, limit: int) -> str:
        if self.dialect == "oracle":
            return f"{sql} OFFSET {int(offset)} ROWS FETCH NEXT {int(limit)} ROWS ONLY"
        return f"{sql} LIMIT {int(limit)} OFFSET {int(offset)}"

    def in_list(self, name: str, values) -> tuple[str, dict]:
        """Bind-variable IN list: returns ('(:b0,:b1)', {'b0':..}). Never interpolates values."""
        values = list(values) or [None]
        params = {f"{name}{i}": v for i, v in enumerate(values)}
        return "(" + ", ".join(f":{k}" for k in params) + ")", params


def _oracle_pool(code: str, cfg: dict):
    with _lock:
        if code not in _pools:
            _pools[code] = oracledb.create_pool(
                user=os.environ[cfg["user_env"]], password=os.environ[cfg["password_env"]],
                dsn=os.environ[cfg["dsn_env"]], min=int(cfg.get("pool_min", 1)),
                max=int(cfg.get("pool_max", 8)), increment=1)
        return _pools[code]


def sqlite_path(cfg: dict) -> Path:
    p = Path(os.environ.get(cfg.get("path_env", ""), "") or cfg["path"])
    return p if p.is_absolute() else BACKEND_DIR / p


@contextmanager
def tenant_db(code: str, write: bool = False):
    """Yields a Db inside one transaction: commit on success, rollback on any error."""
    cfg = tenant_config(code)
    if cfg["dialect"] == "oracle":
        conn = _oracle_pool(code.upper(), cfg).acquire()
        db = Db(conn, "oracle")
    else:
        conn = sqlite3.connect(sqlite_path(cfg), timeout=15, isolation_level=None, check_same_thread=False)
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("BEGIN IMMEDIATE" if write else "BEGIN")
        db = Db(conn, "sqlite")
    try:
        yield db
        conn.commit() if cfg["dialect"] == "oracle" else conn.execute("COMMIT")
    except BaseException:
        conn.rollback() if cfg["dialect"] == "oracle" else conn.execute("ROLLBACK")
        raise
    finally:
        conn.close()
