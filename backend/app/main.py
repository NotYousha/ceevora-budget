"""Ceevora Budget API (FastAPI). OpenAPI at /docs and /openapi.json."""
from __future__ import annotations

import datetime as dt
import json
import logging
import os
import re
import sqlite3
from decimal import Decimal
from pathlib import Path
from typing import Annotated, Literal

import jwt
from fastapi import FastAPI, Header, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import analytics, reports, services as svc
from .db import TenantError, oracledb, registry, tenant_db
from .security import PERMISSIONS, ROLES, decode_token, issue_token, verify_password
from .services import ApiError

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("ceevora.api")
app = FastAPI(title="Ceevora Budget API", version="1.0.0",
              description="Budget Management Module: master, entry, approval, revision, history, dashboard, reports.")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o for o in os.environ.get("CORS_ORIGINS", "").split(",") if o],
    allow_origin_regex=None if os.environ.get("CORS_ORIGINS") else r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["GET", "POST", "PUT"], allow_headers=["Authorization", "Content-Type", "Idempotency-Key"])
API = "/api/v1"


# ---------------- plumbing ----------------

def plain(o):
    if isinstance(o, Decimal):
        return str(o)
    if isinstance(o, (dt.date, dt.datetime)):
        return o.isoformat()
    if isinstance(o, dict):
        return {k: plain(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [plain(v) for v in o]
    return o


def err(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status)


@app.exception_handler(ApiError)
def _api_error(_, e: ApiError):
    return err(e.status, e.code, e.message)


@app.exception_handler(RequestValidationError)
def _validation(_, e: RequestValidationError):
    first = e.errors()[0] if e.errors() else {}
    return err(422, "VALIDATION_ERROR", f"{'.'.join(str(x) for x in first.get('loc', []))}: {first.get('msg', 'invalid')}")


def _integrity(_, e):
    log.warning("integrity error: %s", e)
    return err(409, "CONFLICT", "The change conflicts with existing data (duplicate or locked record)")


for _exc in (sqlite3.IntegrityError, oracledb.IntegrityError if oracledb else None):
    if _exc:
        app.add_exception_handler(_exc, _integrity)


@app.exception_handler(Exception)
def _unexpected(_, e):
    log.exception("unhandled error")
    return err(500, "SERVER_ERROR", "Unexpected server error")


def claims_of(request: Request) -> dict:
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise ApiError(401, "UNAUTHENTICATED", "Sign in required")
    try:
        return decode_token(auth[7:])
    except jwt.ExpiredSignatureError:
        raise ApiError(401, "TOKEN_EXPIRED", "Session expired; sign in again") from None
    except jwt.PyJWTError:
        raise ApiError(401, "INVALID_TOKEN", "Invalid session") from None


def load_user(db, claims_or_row: dict) -> dict:
    u = db.one("SELECT USER_ID, USERNAME, FULL_NAME, ROLE_CODE, COMPANY_ID, ALL_BRANCHES FROM BX_USERS "
               "WHERE USERNAME = :u AND IS_ACTIVE = 'Y'", {"u": claims_or_row["sub"]})
    if not u:
        raise ApiError(401, "INVALID_TOKEN", "User is no longer active")
    perms = [r["permission_code"] for r in db.query(
        "SELECT PERMISSION_CODE FROM BUDGET_ROLE_PERMISSION WHERE ROLE_CODE = :r", {"r": u["role_code"]})]
    if u["all_branches"] == "Y":
        br = db.query("SELECT BRANCH_ID FROM BX_BRANCH WHERE COMPANY_ID = :c AND IS_ACTIVE = 'Y' ORDER BY BRANCH_ID",
                      {"c": u["company_id"]})
    else:
        br = db.query("SELECT ub.BRANCH_ID FROM BX_USER_BRANCH ub JOIN BX_BRANCH b ON b.BRANCH_ID = ub.BRANCH_ID "
                      "WHERE ub.USER_ID = :u AND b.IS_ACTIVE = 'Y' ORDER BY ub.BRANCH_ID", {"u": u["user_id"]})
    return {"user_id": int(u["user_id"]), "username": u["username"], "full_name": u["full_name"],
            "role": u["role_code"], "company_id": int(u["company_id"]), "tenant": claims_or_row["tenant"],
            "permissions": perms, "branch_ids": [int(r["branch_id"]) for r in br]}


def run(request: Request, fn, write: bool = False, idem_key: str | None = None):
    """Authenticate, resolve tenant from the token, run fn(db, user) in one transaction."""
    claims = claims_of(request)
    try:
        with tenant_db(claims["tenant"], write) as db:
            user = load_user(db, claims)
            if idem_key:
                if not re.fullmatch(r"[A-Za-z0-9_\-]{8,100}", idem_key):
                    raise ApiError(422, "INVALID_IDEMPOTENCY_KEY", "Idempotency-Key must be 8-100 safe characters")
                prev = db.one("SELECT USER_NAME, RESPONSE_JSON FROM BUDGET_IDEMPOTENCY WHERE IDEM_KEY = :k", {"k": idem_key})
                if prev:
                    if prev["user_name"] != user["username"]:
                        raise ApiError(409, "IDEMPOTENCY_CONFLICT", "Idempotency-Key already used")
                    return JSONResponse(json.loads(prev["response_json"]), headers={"Idempotent-Replay": "true"})
            result = plain(fn(db, user))
            if idem_key:
                db.insert("BUDGET_IDEMPOTENCY", {"IDEM_KEY": idem_key, "USER_NAME": user["username"],
                                                 "ENDPOINT": request.url.path, "RESPONSE_JSON": json.dumps(result),
                                                 "CREATED_AT": svc.now()})
    except TenantError:
        raise ApiError(401, "INVALID_TOKEN", "Invalid session") from None
    return JSONResponse(result)


IdemKey = Annotated[str | None, Header(alias="Idempotency-Key")]
Money = Annotated[Decimal, Field(ge=0, max_digits=16, decimal_places=2)]
Text = Annotated[str, Field(min_length=1, max_length=1000)]


# ---------------- models ----------------

class LoginIn(BaseModel):
    tenant: str = Field(min_length=1, max_length=30)
    username: str = Field(min_length=1, max_length=50)
    password: str = Field(min_length=1, max_length=200)


class BudgetCreate(BaseModel):
    budget_no: str = Field(min_length=1, max_length=30, pattern=r"^[A-Za-z0-9\-_/]+$")
    budget_name: str = Field(min_length=1, max_length=200)
    fin_year: int = Field(ge=2000, le=2100)
    start_date: dt.date | None = None
    end_date: dt.date | None = None
    currency_code: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")
    allocation_method: Literal["CALENDAR_DAYS", "WORKING_DAYS"] = "CALENDAR_DAYS"
    remarks: str | None = Field(default=None, max_length=1000)


class BudgetUpdate(BaseModel):
    row_version: int
    budget_name: str = Field(min_length=1, max_length=200)
    start_date: dt.date | None = None
    end_date: dt.date | None = None
    currency_code: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")
    allocation_method: Literal["CALENDAR_DAYS", "WORKING_DAYS"] | None = None
    remarks: str | None = Field(default=None, max_length=1000)


class EntryLine(BaseModel):
    gl_account_id: int
    amounts: list[Money] = Field(min_length=1, max_length=13)


class EntrySave(BaseModel):
    branch_id: int
    row_version: int
    lines: list[EntryLine] = Field(max_length=1000)


class ActionIn(BaseModel):
    row_version: int
    remarks: str | None = Field(default=None, max_length=1000)


class RejectIn(BaseModel):
    row_version: int
    reason: Text


class RevisionIn(BaseModel):
    branch_id: int
    gl_account_id: int
    period_no: int = Field(ge=1, le=13)
    revised_amount: Money
    reason: Text


class RevisionApprove(BaseModel):
    revision_ids: list[int] = Field(min_length=1, max_length=500)
    remarks: str | None = Field(default=None, max_length=1000)


class RevisionReject(BaseModel):
    revision_ids: list[int] = Field(min_length=1, max_length=500)
    reason: Text


class PermissionsIn(BaseModel):
    matrix: dict[str, list[str]]


class SettingsIn(BaseModel):
    sod_enforced: bool


# ---------------- auth & lookups ----------------

@app.get("/health", tags=["ops"])
def health():
    status = {}
    for code in registry():
        try:
            with tenant_db(code) as db:
                db.one("SELECT COUNT(*) AS N FROM BUDGET_SETTINGS")
            status[code] = "ok"
        except Exception as e:  # noqa: BLE001 - health must report, not raise
            log.warning("health %s: %s", code, e)
            status[code] = "down"
    ok = all(v == "ok" for v in status.values())
    return JSONResponse({"status": "ok" if ok else "degraded", "tenants": status}, status_code=200 if ok else 503)


@app.post(f"{API}/auth/login", tags=["auth"])
def login(body: LoginIn):
    bad = ApiError(401, "INVALID_CREDENTIALS", "Invalid tenant, username or password")
    try:
        with tenant_db(body.tenant) as db:
            row = db.one("SELECT USERNAME, PASSWORD_HASH FROM BX_USERS WHERE USERNAME = :u AND IS_ACTIVE = 'Y'",
                         {"u": body.username})
            if not row or not verify_password(body.password, row["password_hash"]):
                log.info("failed login tenant=%s user=%s", body.tenant, body.username)
                raise bad
            user = load_user(db, {"sub": row["username"], "tenant": body.tenant.upper()})
            company = db.one("SELECT COMPANY_ID, COMPANY_CODE, COMPANY_NAME, COMPANY_NAME_AR, BASE_CURRENCY FROM BX_COMPANY "
                             "WHERE COMPANY_ID = :c", {"c": user["company_id"]})
    except TenantError:
        raise bad from None
    token, exp = issue_token({"sub": user["username"], "tenant": user["tenant"]})
    return JSONResponse(plain({"token": token, "expires_at": exp, "user": user, "company": company}))


@app.get(f"{API}/auth/me", tags=["auth"])
def me(request: Request):
    return run(request, lambda db, u: u)


@app.get(f"{API}/lookups/branches", tags=["lookups"])
def branches(request: Request):
    def f(db, u):
        rows = analytics.branch_map(db, u["company_id"])
        return [r for k, r in rows.items() if k in u["branch_ids"]]
    return run(request, f)


@app.get(f"{API}/lookups/years", tags=["lookups"])
def years(request: Request):
    return run(request, lambda db, u: [int(r["fin_year"]) for r in db.query(
        "SELECT DISTINCT FIN_YEAR FROM BX_FIN_PERIOD WHERE COMPANY_ID = :c ORDER BY FIN_YEAR", {"c": u["company_id"]})])


@app.get(f"{API}/lookups/periods", tags=["lookups"])
def periods(request: Request, year: int):
    return run(request, lambda db, u: svc.periods(db, u["company_id"], year))


@app.get(f"{API}/lookups/gl-accounts", tags=["lookups"])
def gl_accounts(request: Request, q: str | None = None, category: str | None = None):
    def f(db, u):
        rows = svc.eligible_gl(db, u["company_id"]).values()
        ql = (q or "").lower()
        return [r for r in rows if (not category or r["budget_category"] == category)
                and (not ql or ql in r["gl_code"].lower() or ql in r["gl_name"].lower() or ql in (r["gl_name_ar"] or ""))]
    return run(request, f)


# ---------------- budgets ----------------

@app.get(f"{API}/budgets", tags=["budgets"])
def search(request: Request, q: str | None = None, year: int | None = None, status: str | None = None,
           page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=500)):
    def f(db, u):
        svc.require(u, "BUDGET_VIEW")
        return svc.search_budgets(db, u, q, year, status, page, page_size)
    return run(request, f)


@app.post(f"{API}/budgets", tags=["budgets"])
def create(request: Request, body: BudgetCreate, idem: IdemKey = None):
    return run(request, lambda db, u: svc.create_budget(db, u, body.model_dump()), True, idem)


@app.get(f"{API}/budgets/{{budget_id}}", tags=["budgets"])
def get_budget(request: Request, budget_id: int):
    def f(db, u):
        svc.require(u, "BUDGET_VIEW")
        return svc.get_master(db, u, budget_id)
    return run(request, f)


@app.put(f"{API}/budgets/{{budget_id}}", tags=["budgets"])
def update(request: Request, budget_id: int, body: BudgetUpdate):
    return run(request, lambda db, u: svc.update_budget(db, u, budget_id, body.model_dump()), True)


@app.get(f"{API}/budgets/{{budget_id}}/entry", tags=["entry"])
def get_entry(request: Request, budget_id: int, branch_id: int):
    return run(request, lambda db, u: svc.get_entry(db, u, budget_id, branch_id))


@app.put(f"{API}/budgets/{{budget_id}}/entry", tags=["entry"])
def save_entry(request: Request, budget_id: int, body: EntrySave):
    return run(request, lambda db, u: svc.save_entry(db, u, budget_id, body.model_dump()), True)


@app.get(f"{API}/budgets/{{budget_id}}/summary", tags=["approval"])
def summary(request: Request, budget_id: int):
    return run(request, lambda db, u: svc.budget_summary(db, u, budget_id))


@app.post(f"{API}/budgets/{{budget_id}}/submit", tags=["approval"])
def submit(request: Request, budget_id: int, body: ActionIn, idem: IdemKey = None):
    return run(request, lambda db, u: svc.submit(db, u, budget_id, body.row_version, body.remarks), True, idem)


@app.post(f"{API}/budgets/{{budget_id}}/approve", tags=["approval"])
def approve(request: Request, budget_id: int, body: ActionIn, idem: IdemKey = None):
    return run(request, lambda db, u: svc.approve(db, u, budget_id, body.row_version, body.remarks), True, idem)


@app.post(f"{API}/budgets/{{budget_id}}/reject", tags=["approval"])
def reject(request: Request, budget_id: int, body: RejectIn, idem: IdemKey = None):
    return run(request, lambda db, u: svc.reject(db, u, budget_id, body.row_version, body.reason), True, idem)


@app.get(f"{API}/budgets/{{budget_id}}/approval-history", tags=["history"])
def approval_history(request: Request, budget_id: int, version: int | None = None):
    return run(request, lambda db, u: svc.approval_history(db, u, budget_id, version))


@app.get(f"{API}/budgets/{{budget_id}}/revision-history", tags=["history"])
def revision_history(request: Request, budget_id: int, version: int | None = None, status: str | None = None):
    return run(request, lambda db, u: svc.revision_history(db, u, budget_id, version, status))


@app.get(f"{API}/budgets/{{budget_id}}/revision-line", tags=["revisions"])
def revision_line(request: Request, budget_id: int, branch_id: int, gl_account_id: int, period_no: int):
    return run(request, lambda db, u: svc.revision_line(db, u, budget_id, branch_id, gl_account_id, period_no))


@app.post(f"{API}/budgets/{{budget_id}}/revisions", tags=["revisions"])
def request_revision(request: Request, budget_id: int, body: RevisionIn, idem: IdemKey = None):
    return run(request, lambda db, u: svc.request_revision(db, u, budget_id, body.model_dump()), True, idem)


@app.post(f"{API}/revisions/approve", tags=["revisions"])
def approve_revisions(request: Request, body: RevisionApprove, idem: IdemKey = None):
    return run(request, lambda db, u: svc.approve_revisions(db, u, body.revision_ids, body.remarks), True, idem)


@app.post(f"{API}/revisions/reject", tags=["revisions"])
def reject_revisions(request: Request, body: RevisionReject, idem: IdemKey = None):
    return run(request, lambda db, u: svc.reject_revisions(db, u, body.revision_ids, body.reason), True, idem)


# ---------------- analytics ----------------

@app.get(f"{API}/dashboard", tags=["dashboard"])
def dashboard(request: Request, year: int, period_no: int | None = None, date_from: dt.date | None = None,
              date_to: dt.date | None = None, branch_id: int | None = None, category: str | None = None,
              gl_account_id: int | None = None):
    return run(request, lambda db, u: analytics.dashboard(db, u, year, period_no, date_from, date_to, branch_id,
                                                          category, gl_account_id))


@app.get(f"{API}/drilldown/gl", tags=["dashboard"])
def drill_gl(request: Request, date_from: dt.date, date_to: dt.date, branch_id: int | None = None,
             category: str | None = None):
    return run(request, lambda db, u: analytics.drill_gl(db, u, date_from, date_to, branch_id, category))


@app.get(f"{API}/drilldown/transactions", tags=["dashboard"])
def drill_tx(request: Request, date_from: dt.date, date_to: dt.date, gl_account_id: int, branch_id: int | None = None,
             page: int = Query(1, ge=1), page_size: int = Query(50, ge=1, le=500)):
    return run(request, lambda db, u: analytics.drill_transactions(db, u, date_from, date_to, branch_id, gl_account_id,
                                                                   page, page_size))


@app.get(f"{API}/daily/performance", tags=["daily"])
def daily_performance(request: Request, date: dt.date, branch_id: int | None = None):
    return run(request, lambda db, u: analytics.daily_performance(db, u, date, branch_id))


@app.get(f"{API}/daily/pl", tags=["daily"])
def daily_pl(request: Request, date: dt.date, branch_id: int | None = None, basis: Literal["DAY", "MTD"] = "DAY"):
    return run(request, lambda db, u: analytics.daily_pl(db, u, date, branch_id, basis))


@app.get(f"{API}/reports/{{code}}", tags=["reports"])
def report(request: Request, code: str,
           period_type: Literal["DAILY", "MTD", "MONTHLY", "YTD", "YEARLY", "CUSTOM"] = "MTD",
           date: dt.date | None = None, year: int | None = None, period_no: int | None = None,
           date_from: dt.date | None = None, date_to: dt.date | None = None, branch_id: int | None = None,
           category: str | None = None, sort: str | None = None, desc: bool = False,
           page: int = Query(1, ge=1), page_size: int = Query(100, ge=1, le=1000)):
    q = dict(period_type=period_type, date=date, year=year, period_no=period_no, date_from=date_from, date_to=date_to,
             branch_id=branch_id, category=category, sort=sort, desc=desc, page=page, page_size=page_size)
    if period_type in ("MONTHLY", "YEARLY") and not year:
        raise ApiError(422, "VALIDATION_ERROR", "year is required for MONTHLY and YEARLY")
    return run(request, lambda db, u: reports.build(db, u, code.upper(), q))


# ---------------- admin ----------------

@app.get(f"{API}/admin/permissions", tags=["admin"])
def get_permissions(request: Request):
    def f(db, u):
        svc.require(u, "ADMIN_CONFIG")
        rows = db.query("SELECT ROLE_CODE, PERMISSION_CODE FROM BUDGET_ROLE_PERMISSION")
        return {"roles": ROLES, "permissions": PERMISSIONS,
                "matrix": {r: [x["permission_code"] for x in rows if x["role_code"] == r] for r in ROLES},
                "sod_enforced": svc.setting(db, "SOD_ENFORCED", "Y") == "Y"}
    return run(request, f)


@app.put(f"{API}/admin/permissions", tags=["admin"])
def put_permissions(request: Request, body: PermissionsIn):
    def f(db, u):
        svc.require(u, "ADMIN_CONFIG")
        for role, perms in body.matrix.items():
            if role not in ROLES or any(p not in PERMISSIONS for p in perms):
                raise ApiError(422, "INVALID_PERMISSION", f"Unknown role or permission for {role}")
        if "ADMIN_CONFIG" not in body.matrix.get("ADMIN", ["ADMIN_CONFIG"]):
            raise ApiError(422, "LOCKOUT", "ADMIN must keep ADMIN_CONFIG")
        for role, perms in body.matrix.items():
            db.execute("DELETE FROM BUDGET_ROLE_PERMISSION WHERE ROLE_CODE = :r", {"r": role})
            for p in sorted(set(perms)):
                db.insert("BUDGET_ROLE_PERMISSION", {"ROLE_CODE": role, "PERMISSION_CODE": p})
        log.info("permissions changed by %s: %s", u["username"], body.matrix)
        return {"ok": True}
    return run(request, f, True)


@app.put(f"{API}/admin/settings", tags=["admin"])
def put_settings(request: Request, body: SettingsIn):
    def f(db, u):
        svc.require(u, "ADMIN_CONFIG")
        n = db.execute("UPDATE BUDGET_SETTINGS SET SETTING_VALUE = :v WHERE SETTING_KEY = 'SOD_ENFORCED'",
                       {"v": "Y" if body.sod_enforced else "N"})
        if n == 0:
            db.insert("BUDGET_SETTINGS", {"SETTING_KEY": "SOD_ENFORCED", "SETTING_VALUE": "Y" if body.sod_enforced else "N"})
        log.info("SOD_ENFORCED=%s by %s", body.sod_enforced, u["username"])
        return {"ok": True}
    return run(request, f, True)


# Optional: serve the Flutter web build from the same origin (standalone demo).
_web = Path(os.environ.get("WEB_DIR", Path(__file__).resolve().parents[2] / "frontend" / "build" / "web"))
if _web.is_dir():
    app.mount("/", StaticFiles(directory=_web, html=True), name="web")
