"""Budget master, entry, approval and revision workflows. Every write runs in one transaction with its audit rows."""
from __future__ import annotations

import datetime as dt
from decimal import Decimal

from .calc import money, pl_totals, revision_pct
from .db import Db, as_date


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


def now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(tzinfo=None, microsecond=0)


def require(user: dict, perm: str) -> None:
    if perm not in user["permissions"]:
        raise ApiError(403, "FORBIDDEN", f"Missing permission {perm}")


def check_branch(user: dict, branch_id: int) -> None:
    if branch_id not in user["branch_ids"]:
        raise ApiError(403, "BRANCH_FORBIDDEN", "You are not authorised for this branch")


def setting(db: Db, key: str, default: str = "") -> str:
    r = db.one("SELECT SETTING_VALUE FROM BUDGET_SETTINGS WHERE SETTING_KEY = :k", {"k": key})
    return r["setting_value"] if r else default


def sod_check(db: Db, user: dict, other_user: str | None, what: str) -> None:
    if setting(db, "SOD_ENFORCED", "Y") == "Y" and other_user == user["username"]:
        raise ApiError(409, "SEGREGATION_OF_DUTIES", f"You cannot {what} your own submission")


def history(db: Db, budget_id: int, action: str, prev: str | None, new: str, version: int, user: dict,
            remarks: str | None = None, rejection: str | None = None) -> None:
    db.insert("BUDGET_APPROVAL_HISTORY", {
        "BUDGET_ID": budget_id, "ACTION": action, "PREVIOUS_STATUS": prev, "NEW_STATUS": new,
        "VERSION_NO": version, "ACTION_BY": user["username"], "ACTION_AT": now(),
        "REMARKS": remarks, "REJECTION_REASON": rejection})


# ---------------- master ----------------

MASTER_COLS = ("BUDGET_ID, COMPANY_ID, BUDGET_NO, BUDGET_NAME, BUDGET_TYPE, FIN_YEAR, START_DATE, END_DATE, "
               "CURRENCY_CODE, ALLOCATION_METHOD, STATUS, VERSION_NO, REMARKS, ROW_VERSION, SUBMITTED_BY, "
               "SUBMITTED_AT, APPROVED_BY, APPROVED_AT, CREATED_BY, CREATED_AT, UPDATED_BY, UPDATED_AT")


def get_master(db: Db, user: dict, budget_id: int, lock: bool = False) -> dict:
    sql = f"SELECT {MASTER_COLS} FROM BUDGET_MASTER WHERE BUDGET_ID = :id AND COMPANY_ID = :c"
    m = db.one(db.for_update(sql) if lock else sql, {"id": budget_id, "c": user["company_id"]})
    if not m:
        raise ApiError(404, "NOT_FOUND", "Budget not found")
    return m


def check_version(m: dict, row_version: int) -> None:
    if int(m["row_version"]) != int(row_version):
        raise ApiError(409, "STALE_DATA", "The budget was changed by another user. Reload and try again.")


def bump(db: Db, user: dict, budget_id: int, row_version: int, **cols) -> None:
    sets = ", ".join(f"{k} = :{k}" for k in cols)
    n = db.execute(f"UPDATE BUDGET_MASTER SET {sets}{', ' if sets else ''}ROW_VERSION = ROW_VERSION + 1, "
                   "UPDATED_BY = :u_by, UPDATED_AT = :u_at WHERE BUDGET_ID = :id AND ROW_VERSION = :rv",
                   {**cols, "u_by": user["username"], "u_at": now(), "id": budget_id, "rv": row_version})
    if n != 1:
        raise ApiError(409, "STALE_DATA", "The budget was changed by another user. Reload and try again.")


def year_bounds(db: Db, company_id: int, year: int) -> tuple[dt.date, dt.date]:
    r = db.one("SELECT MIN(START_DATE) AS S, MAX(END_DATE) AS E FROM BX_FIN_PERIOD WHERE COMPANY_ID = :c AND FIN_YEAR = :y",
               {"c": company_id, "y": year})
    if not r or r["s"] is None:
        raise ApiError(422, "INVALID_YEAR", f"Financial year {year} is not configured")
    return as_date(r["s"]), as_date(r["e"])


def search_budgets(db: Db, user: dict, q: str | None, year: int | None, status: str | None,
                   page: int, page_size: int) -> dict:
    where, p = ["COMPANY_ID = :c"], {"c": user["company_id"]}
    if q:
        where.append("(UPPER(BUDGET_NO) LIKE :q OR UPPER(BUDGET_NAME) LIKE :q)")
        p["q"] = f"%{q.upper()}%"
    if year:
        where.append("FIN_YEAR = :y")
        p["y"] = year
    if status:
        where.append("STATUS = :s")
        p["s"] = status
    w = " AND ".join(where)
    total = db.one(f"SELECT COUNT(*) AS N FROM BUDGET_MASTER WHERE {w}", p)["n"]
    items = db.query(db.page(f"SELECT {MASTER_COLS} FROM BUDGET_MASTER WHERE {w} ORDER BY FIN_YEAR DESC, BUDGET_NO",
                             (page - 1) * page_size, page_size), p)
    return {"items": items, "total": int(total), "page": page, "page_size": page_size}


def create_budget(db: Db, user: dict, body: dict) -> dict:
    require(user, "BUDGET_CREATE")
    c = user["company_id"]
    start, end = year_bounds(db, c, body["fin_year"])
    start, end = body.get("start_date") or start, body.get("end_date") or end
    if end <= start:
        raise ApiError(422, "INVALID_DATES", "End date must be after start date")
    if db.one("SELECT 1 AS X FROM BUDGET_MASTER WHERE COMPANY_ID = :c AND FIN_YEAR = :y AND BUDGET_TYPE = 'OPERATING'",
              {"c": c, "y": body["fin_year"]}):
        raise ApiError(409, "DUPLICATE_BUDGET", f"An operating budget for {body['fin_year']} already exists")
    if db.one("SELECT 1 AS X FROM BUDGET_MASTER WHERE COMPANY_ID = :c AND BUDGET_NO = :n",
              {"c": c, "n": body["budget_no"]}):
        raise ApiError(409, "DUPLICATE_NUMBER", "Budget number already used")
    currency = body.get("currency_code") or db.one(
        "SELECT BASE_CURRENCY FROM BX_COMPANY WHERE COMPANY_ID = :c", {"c": c})["base_currency"]
    bid = db.insert("BUDGET_MASTER", {
        "COMPANY_ID": c, "BUDGET_NO": body["budget_no"], "BUDGET_NAME": body["budget_name"],
        "BUDGET_TYPE": "OPERATING", "FIN_YEAR": body["fin_year"], "START_DATE": start, "END_DATE": end,
        "CURRENCY_CODE": currency, "ALLOCATION_METHOD": body.get("allocation_method") or "CALENDAR_DAYS",
        "STATUS": "DRAFT", "VERSION_NO": 0, "REMARKS": body.get("remarks"), "ROW_VERSION": 1,
        "CREATED_BY": user["username"], "CREATED_AT": now()}, pk="BUDGET_ID")
    history(db, bid, "CREATE", None, "DRAFT", 0, user, body.get("remarks"))
    return get_master(db, user, bid)


def update_budget(db: Db, user: dict, budget_id: int, body: dict) -> dict:
    require(user, "BUDGET_CREATE")
    m = get_master(db, user, budget_id, lock=True)
    if m["status"] != "DRAFT":
        raise ApiError(409, "NOT_EDITABLE", "Only DRAFT budgets can be edited; use a revision after approval")
    check_version(m, body["row_version"])
    start = body.get("start_date") or as_date(m["start_date"])
    end = body.get("end_date") or as_date(m["end_date"])
    if end <= start:
        raise ApiError(422, "INVALID_DATES", "End date must be after start date")
    bump(db, user, budget_id, body["row_version"], BUDGET_NAME=body["budget_name"], REMARKS=body.get("remarks"),
         ALLOCATION_METHOD=body.get("allocation_method") or m["allocation_method"],
         CURRENCY_CODE=body.get("currency_code") or m["currency_code"], START_DATE=start, END_DATE=end)
    history(db, budget_id, "UPDATE", "DRAFT", "DRAFT", int(m["version_no"]), user, "Header updated")
    return get_master(db, user, budget_id)


# ---------------- entry ----------------

def periods(db: Db, company_id: int, year: int) -> list[dict]:
    return db.query("SELECT PERIOD_NO, PERIOD_NAME, START_DATE, END_DATE FROM BX_FIN_PERIOD "
                    "WHERE COMPANY_ID = :c AND FIN_YEAR = :y ORDER BY PERIOD_NO", {"c": company_id, "y": year})


def eligible_gl(db: Db, company_id: int) -> dict[int, dict]:
    rows = db.query("SELECT GL_ACCOUNT_ID, GL_CODE, GL_NAME, GL_NAME_AR, BUDGET_CATEGORY, EXPENSE_GROUP FROM BX_GL_ACCOUNT "
                    "WHERE COMPANY_ID = :c AND IS_ACTIVE = 'Y' AND IS_POSTING = 'Y' AND BUDGET_CATEGORY IS NOT NULL "
                    "AND IS_VAT = 'N' AND IS_INTERNAL_TRANSFER = 'N' ORDER BY GL_CODE", {"c": company_id})
    return {int(r["gl_account_id"]): r for r in rows}


def get_entry(db: Db, user: dict, budget_id: int, branch_id: int) -> dict:
    require(user, "BUDGET_VIEW")
    check_branch(user, branch_id)
    m = get_master(db, user, budget_id)
    per = periods(db, user["company_id"], m["fin_year"])
    rows = db.query("SELECT d.DETAIL_ID, d.GL_ACCOUNT_ID, d.PERIOD_NO, d.ORIGINAL_AMOUNT, d.CURRENT_AMOUNT, "
                    "g.GL_CODE, g.GL_NAME, g.GL_NAME_AR, g.BUDGET_CATEGORY FROM BUDGET_DETAILS d "
                    "JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = d.GL_ACCOUNT_ID "
                    "WHERE d.BUDGET_ID = :b AND d.BRANCH_ID = :br ORDER BY g.GL_CODE, d.PERIOD_NO",
                    {"b": budget_id, "br": branch_id})
    lines: dict[int, dict] = {}
    for r in rows:
        gid = int(r["gl_account_id"])
        line = lines.setdefault(gid, {"gl_account_id": gid, "gl_code": r["gl_code"], "gl_name": r["gl_name"],
                                      "gl_name_ar": r["gl_name_ar"], "category": r["budget_category"],
                                      "amounts": [money(0)] * len(per)})
        line["amounts"][int(r["period_no"]) - 1] = money(r["current_amount"])
    out = list(lines.values())
    for line in out:
        line["annual_total"] = sum(line["amounts"], money(0))
    return {"budget": m, "branch_id": branch_id, "periods": per, "lines": out, "summary": entry_summary(out, len(per))}


def entry_summary(lines: list[dict], n: int) -> dict:
    def tot(idx):
        by = {}
        for ln in lines:
            v = ln["amounts"][idx] if idx is not None else ln["annual_total"]
            b, _ = by.get(ln["category"], (money(0), money(0)))
            by[ln["category"]] = (b + v, money(0))
        return {k: v[0] for k, v in pl_totals(by).items()}
    return {"annual": tot(None), "monthly": [tot(i) for i in range(n)]}


def save_entry(db: Db, user: dict, budget_id: int, body: dict) -> dict:
    require(user, "BUDGET_CREATE")
    branch_id = body["branch_id"]
    check_branch(user, branch_id)
    m = get_master(db, user, budget_id, lock=True)
    if m["status"] != "DRAFT":
        raise ApiError(409, "NOT_EDITABLE", "Budget lines can only be edited while DRAFT")
    check_version(m, body["row_version"])
    if not db.one("SELECT 1 AS X FROM BX_BRANCH WHERE BRANCH_ID = :b AND COMPANY_ID = :c AND IS_ACTIVE = 'Y'",
                  {"b": branch_id, "c": user["company_id"]}):
        raise ApiError(422, "INVALID_BRANCH", "Branch is not active")
    n = len(periods(db, user["company_id"], m["fin_year"]))
    gl = eligible_gl(db, user["company_id"])
    wanted: dict[tuple[int, int], Decimal] = {}
    for line in body["lines"]:
        gid = line["gl_account_id"]
        if gid not in gl:
            raise ApiError(422, "INVALID_ACCOUNT", f"GL account {gid} is not an active budget posting account")
        if len(line["amounts"]) != n:
            raise ApiError(422, "INVALID_PERIODS", f"Each line needs exactly {n} monthly amounts")
        for p, amt in enumerate(line["amounts"], 1):
            if (gid, p) in wanted:
                raise ApiError(422, "DUPLICATE_LINE", f"GL {gl[gid]['gl_code']} appears more than once")
            if money(amt) < 0:
                raise ApiError(422, "NEGATIVE_AMOUNT", "Budget amounts cannot be negative")
            wanted[(gid, p)] = money(amt)
    existing = {(int(r["gl_account_id"]), int(r["period_no"])): r for r in db.query(
        db.for_update("SELECT DETAIL_ID, GL_ACCOUNT_ID, PERIOD_NO, CURRENT_AMOUNT FROM BUDGET_DETAILS "
                      "WHERE BUDGET_ID = :b AND BRANCH_ID = :br"), {"b": budget_id, "br": branch_id})}
    ts = now()
    for key, row in existing.items():
        if key not in wanted:
            db.execute("DELETE FROM BUDGET_DETAILS WHERE DETAIL_ID = :d", {"d": row["detail_id"]})
        elif money(row["current_amount"]) != wanted[key]:
            db.execute("UPDATE BUDGET_DETAILS SET CURRENT_AMOUNT = :a, ROW_VERSION = ROW_VERSION + 1, UPDATED_BY = :u, "
                       "UPDATED_AT = :t WHERE DETAIL_ID = :d",
                       {"a": wanted[key], "u": user["username"], "t": ts, "d": row["detail_id"]})
    for (gid, p), amt in wanted.items():
        if (gid, p) not in existing:
            db.insert("BUDGET_DETAILS", {"BUDGET_ID": budget_id, "BRANCH_ID": branch_id, "GL_ACCOUNT_ID": gid,
                                         "PERIOD_NO": p, "CURRENT_AMOUNT": amt, "ROW_VERSION": 1,
                                         "CREATED_BY": user["username"], "CREATED_AT": ts})
    bump(db, user, budget_id, body["row_version"])
    return get_entry(db, user, budget_id, branch_id)


def budget_summary(db: Db, user: dict, budget_id: int) -> dict:
    """Branch and company P&L totals of current amounts (approval screen)."""
    require(user, "BUDGET_VIEW")
    m = get_master(db, user, budget_id)
    br_in, p = db.in_list("br", user["branch_ids"])
    rows = db.query("SELECT d.BRANCH_ID, b.BRANCH_NAME, b.BRANCH_NAME_AR, g.BUDGET_CATEGORY, SUM(d.CURRENT_AMOUNT) AS AMT "
                    "FROM BUDGET_DETAILS d JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = d.GL_ACCOUNT_ID "
                    "JOIN BX_BRANCH b ON b.BRANCH_ID = d.BRANCH_ID "
                    f"WHERE d.BUDGET_ID = :b AND d.BRANCH_ID IN {br_in} "
                    "GROUP BY d.BRANCH_ID, b.BRANCH_NAME, b.BRANCH_NAME_AR, g.BUDGET_CATEGORY ORDER BY d.BRANCH_ID",
                    {"b": budget_id, **p})
    branches: dict[int, dict] = {}
    company: dict[str, tuple] = {}
    for r in rows:
        b = branches.setdefault(int(r["branch_id"]), {"branch_id": int(r["branch_id"]), "branch_name": r["branch_name"],
                                                      "branch_name_ar": r["branch_name_ar"], "cat": {}})
        b["cat"][r["budget_category"]] = (money(r["amt"]), 0)
        prev = company.get(r["budget_category"], (money(0), 0))[0]
        company[r["budget_category"]] = (prev + money(r["amt"]), 0)
    out = []
    for b in branches.values():
        out.append({k: v for k, v in b.items() if k != "cat"} | {k: v[0] for k, v in pl_totals(b.pop("cat")).items()})
    return {"budget": m, "branches": out, "company": {k: v[0] for k, v in pl_totals(company).items()}}


# ---------------- workflow ----------------

def submit(db: Db, user: dict, budget_id: int, row_version: int, remarks: str | None) -> dict:
    require(user, "BUDGET_SUBMIT")
    m = get_master(db, user, budget_id, lock=True)
    if m["status"] != "DRAFT":
        raise ApiError(409, "INVALID_STATE", f"Cannot submit a {m['status']} budget")
    check_version(m, row_version)
    if not db.one("SELECT 1 AS X FROM BUDGET_DETAILS WHERE BUDGET_ID = :b", {"b": budget_id}):
        raise ApiError(422, "EMPTY_BUDGET", "Enter budget lines before submitting")
    bump(db, user, budget_id, row_version, STATUS="SUBMITTED", SUBMITTED_BY=user["username"], SUBMITTED_AT=now())
    history(db, budget_id, "SUBMIT", "DRAFT", "SUBMITTED", int(m["version_no"]), user, remarks)
    return get_master(db, user, budget_id)


def approve(db: Db, user: dict, budget_id: int, row_version: int, remarks: str | None) -> dict:
    require(user, "BUDGET_APPROVE")
    m = get_master(db, user, budget_id, lock=True)
    if m["status"] != "SUBMITTED":
        raise ApiError(409, "INVALID_STATE", f"Cannot approve a {m['status']} budget")
    check_version(m, row_version)
    sod_check(db, user, m["submitted_by"], "approve")
    # Initial approval freezes original amounts and establishes version 1.
    db.execute("UPDATE BUDGET_DETAILS SET ORIGINAL_AMOUNT = CURRENT_AMOUNT, ROW_VERSION = ROW_VERSION + 1, "
               "UPDATED_BY = :u, UPDATED_AT = :t WHERE BUDGET_ID = :b AND ORIGINAL_AMOUNT IS NULL",
               {"u": user["username"], "t": now(), "b": budget_id})
    bump(db, user, budget_id, row_version, STATUS="APPROVED", VERSION_NO=1, APPROVED_BY=user["username"], APPROVED_AT=now())
    history(db, budget_id, "APPROVE", "SUBMITTED", "APPROVED", 1, user, remarks)
    return get_master(db, user, budget_id)


def reject(db: Db, user: dict, budget_id: int, row_version: int, reason: str) -> dict:
    require(user, "BUDGET_APPROVE")
    if not (reason or "").strip():
        raise ApiError(422, "REASON_REQUIRED", "Rejection remarks are required")
    m = get_master(db, user, budget_id, lock=True)
    if m["status"] != "SUBMITTED":
        raise ApiError(409, "INVALID_STATE", f"Cannot reject a {m['status']} budget")
    check_version(m, row_version)
    sod_check(db, user, m["submitted_by"], "reject")
    bump(db, user, budget_id, row_version, STATUS="DRAFT")
    history(db, budget_id, "REJECT", "SUBMITTED", "DRAFT", int(m["version_no"]), user, None, reason.strip())
    return get_master(db, user, budget_id)


# ---------------- revisions ----------------

def revision_line(db: Db, user: dict, budget_id: int, branch_id: int, gl_id: int, period_no: int) -> dict:
    require(user, "BUDGET_VIEW")
    check_branch(user, branch_id)
    m = get_master(db, user, budget_id)
    d = db.one("SELECT DETAIL_ID, ORIGINAL_AMOUNT, CURRENT_AMOUNT, ROW_VERSION FROM BUDGET_DETAILS WHERE BUDGET_ID = :b "
               "AND BRANCH_ID = :br AND GL_ACCOUNT_ID = :g AND PERIOD_NO = :p",
               {"b": budget_id, "br": branch_id, "g": gl_id, "p": period_no})
    pending = None
    if d:
        pending = db.one("SELECT REVISION_ID, REVISED_AMOUNT, REASON, REVISED_BY FROM BUDGET_REVISION_HISTORY "
                         "WHERE DETAIL_ID = :d AND STATUS = 'PENDING'", {"d": d["detail_id"]})
    return {"budget_status": m["status"], "version_no": m["version_no"],
            "original_amount": money(d["original_amount"]) if d else money(0),
            "current_amount": money(d["current_amount"]) if d else money(0), "pending": pending}


def request_revision(db: Db, user: dict, budget_id: int, body: dict) -> dict:
    require(user, "REVISION_REQUEST")
    check_branch(user, body["branch_id"])
    if not body["reason"].strip():
        raise ApiError(422, "REASON_REQUIRED", "A revision reason is required")
    m = get_master(db, user, budget_id, lock=True)
    if m["status"] != "APPROVED":
        raise ApiError(409, "INVALID_STATE", "Revisions apply to approved budgets only")
    if body["gl_account_id"] not in eligible_gl(db, user["company_id"]):
        raise ApiError(422, "INVALID_ACCOUNT", "GL account is not an active budget posting account")
    if not 1 <= body["period_no"] <= len(periods(db, user["company_id"], m["fin_year"])):
        raise ApiError(422, "INVALID_PERIOD", "Invalid period")
    revised = money(body["revised_amount"])
    if revised < 0:
        raise ApiError(422, "NEGATIVE_AMOUNT", "Budget amounts cannot be negative")
    key = {"b": budget_id, "br": body["branch_id"], "g": body["gl_account_id"], "p": body["period_no"]}
    sel = ("SELECT DETAIL_ID, ORIGINAL_AMOUNT, CURRENT_AMOUNT, ROW_VERSION FROM BUDGET_DETAILS WHERE BUDGET_ID = :b "
           "AND BRANCH_ID = :br AND GL_ACCOUNT_ID = :g AND PERIOD_NO = :p")
    d = db.one(db.for_update(sel), key)
    if not d:  # new line after approval: original budget for it is zero
        db.insert("BUDGET_DETAILS", {"BUDGET_ID": budget_id, "BRANCH_ID": body["branch_id"],
                                     "GL_ACCOUNT_ID": body["gl_account_id"], "PERIOD_NO": body["period_no"],
                                     "ORIGINAL_AMOUNT": money(0), "CURRENT_AMOUNT": money(0), "ROW_VERSION": 1,
                                     "CREATED_BY": user["username"], "CREATED_AT": now()})
        d = db.one(sel, key)
    if db.one("SELECT 1 AS X FROM BUDGET_REVISION_HISTORY WHERE DETAIL_ID = :d AND STATUS = 'PENDING'",
              {"d": d["detail_id"]}):
        raise ApiError(409, "PENDING_EXISTS", "This line already has a pending revision")
    prev = money(d["current_amount"])
    if revised == prev:
        raise ApiError(422, "NO_CHANGE", "Revised amount equals the current approved amount")
    rid = db.insert("BUDGET_REVISION_HISTORY", {
        "BUDGET_ID": budget_id, "DETAIL_ID": d["detail_id"], "BRANCH_ID": body["branch_id"],
        "GL_ACCOUNT_ID": body["gl_account_id"], "PERIOD_NO": body["period_no"],
        "BASE_VERSION_NO": m["version_no"], "ORIGINAL_AMOUNT": money(d["original_amount"]),
        "PREVIOUS_APPROVED_AMOUNT": prev, "REVISED_AMOUNT": revised, "DIFFERENCE_AMOUNT": revised - prev,
        "DIFFERENCE_PCT": revision_pct(revised, prev), "DETAIL_ROW_VERSION": d["row_version"], "STATUS": "PENDING",
        "REASON": body["reason"].strip(), "REVISED_BY": user["username"], "REVISED_AT": now()}, pk="REVISION_ID")
    return {"revision_id": rid}


def _pending(db: Db, user: dict, ids: list[int]) -> list[dict]:
    if not ids:
        raise ApiError(422, "NO_SELECTION", "Select at least one revision")
    ids_in, p = db.in_list("r", ids)
    revs = db.query(db.for_update(f"SELECT * FROM BUDGET_REVISION_HISTORY WHERE REVISION_ID IN {ids_in}"), p)
    if len(revs) != len(set(ids)):
        raise ApiError(404, "NOT_FOUND", "Revision not found")
    if len({r["budget_id"] for r in revs}) != 1:
        raise ApiError(422, "MIXED_BUDGETS", "Approve revisions of one budget at a time")
    if any(r["status"] != "PENDING" for r in revs):
        raise ApiError(409, "ALREADY_DECIDED", "One or more revisions are no longer pending")
    for r in revs:
        check_branch(user, int(r["branch_id"]))
        sod_check(db, user, r["revised_by"], "approve or reject")
    return revs


def approve_revisions(db: Db, user: dict, ids: list[int], remarks: str | None) -> dict:
    require(user, "REVISION_APPROVE")
    revs = _pending(db, user, ids)
    budget_id = int(revs[0]["budget_id"])
    m = get_master(db, user, budget_id, lock=True)
    ts, approved, stale = now(), [], []
    new_version = int(m["version_no"]) + 1
    for r in revs:
        d = db.one(db.for_update("SELECT CURRENT_AMOUNT, ROW_VERSION FROM BUDGET_DETAILS WHERE DETAIL_ID = :d"),
                   {"d": r["detail_id"]})
        if int(d["row_version"]) != int(r["detail_row_version"]) or money(d["current_amount"]) != money(r["previous_approved_amount"]):
            db.execute("UPDATE BUDGET_REVISION_HISTORY SET STATUS = 'REJECTED', REJECTION_REASON = :why, "
                       "APPROVED_BY = :u, APPROVED_AT = :t WHERE REVISION_ID = :r",
                       {"why": "Stale: the line changed after this revision was requested", "u": user["username"],
                        "t": ts, "r": r["revision_id"]})
            stale.append(int(r["revision_id"]))
            continue
        db.execute("UPDATE BUDGET_DETAILS SET CURRENT_AMOUNT = :a, ROW_VERSION = ROW_VERSION + 1, UPDATED_BY = :u, "
                   "UPDATED_AT = :t WHERE DETAIL_ID = :d",
                   {"a": money(r["revised_amount"]), "u": user["username"], "t": ts, "d": r["detail_id"]})
        db.execute("UPDATE BUDGET_REVISION_HISTORY SET STATUS = 'APPROVED', VERSION_NO = :v, APPROVED_BY = :u, "
                   "APPROVED_AT = :t WHERE REVISION_ID = :r",
                   {"v": new_version, "u": user["username"], "t": ts, "r": r["revision_id"]})
        approved.append(int(r["revision_id"]))
    if approved:
        bump(db, user, budget_id, int(m["row_version"]), VERSION_NO=new_version)
        history(db, budget_id, "REVISION_APPROVED", "APPROVED", "APPROVED", new_version, user,
                remarks or f"Revisions {', '.join(map(str, approved))} approved")
    if stale:
        history(db, budget_id, "REVISION_REJECTED", "APPROVED", "APPROVED", new_version if approved else int(m["version_no"]),
                user, f"Stale revisions {', '.join(map(str, stale))} rejected", "Stale revision")
    return {"approved": approved, "stale_rejected": stale,
            "version_no": new_version if approved else int(m["version_no"])}


def reject_revisions(db: Db, user: dict, ids: list[int], reason: str) -> dict:
    require(user, "REVISION_APPROVE")
    if not (reason or "").strip():
        raise ApiError(422, "REASON_REQUIRED", "Rejection remarks are required")
    revs = _pending(db, user, ids)
    budget_id = int(revs[0]["budget_id"])
    m = get_master(db, user, budget_id, lock=True)
    ts = now()
    for r in revs:
        db.execute("UPDATE BUDGET_REVISION_HISTORY SET STATUS = 'REJECTED', REJECTION_REASON = :why, APPROVED_BY = :u, "
                   "APPROVED_AT = :t WHERE REVISION_ID = :r",
                   {"why": reason.strip(), "u": user["username"], "t": ts, "r": r["revision_id"]})
    history(db, budget_id, "REVISION_REJECTED", "APPROVED", "APPROVED", int(m["version_no"]), user,
            f"Revisions {', '.join(str(r['revision_id']) for r in revs)} rejected", reason.strip())
    return {"rejected": [int(r["revision_id"]) for r in revs]}


# ---------------- history ----------------

def approval_history(db: Db, user: dict, budget_id: int, version: int | None) -> list[dict]:
    require(user, "BUDGET_VIEW")
    get_master(db, user, budget_id)
    p = {"b": budget_id}
    extra = ""
    if version is not None:
        extra, p["v"] = " AND VERSION_NO = :v", version
    return db.query("SELECT HISTORY_ID, ACTION, PREVIOUS_STATUS, NEW_STATUS, VERSION_NO, ACTION_BY, ACTION_AT, REMARKS, "
                    f"REJECTION_REASON FROM BUDGET_APPROVAL_HISTORY WHERE BUDGET_ID = :b{extra} ORDER BY ACTION_AT, HISTORY_ID", p)


def revision_history(db: Db, user: dict, budget_id: int, version: int | None = None, status: str | None = None) -> list[dict]:
    require(user, "BUDGET_VIEW")
    get_master(db, user, budget_id)
    br_in, p = db.in_list("br", user["branch_ids"])
    p["b"] = budget_id
    extra = ""
    if version is not None:
        extra += " AND (r.VERSION_NO = :v OR r.BASE_VERSION_NO = :v)"
        p["v"] = version
    if status:
        extra += " AND r.STATUS = :s"
        p["s"] = status
    return db.query(
        "SELECT r.REVISION_ID, r.VERSION_NO, r.BASE_VERSION_NO, r.BRANCH_ID, b.BRANCH_NAME, b.BRANCH_NAME_AR, r.PERIOD_NO, "
        "r.GL_ACCOUNT_ID, g.GL_CODE, g.GL_NAME, g.GL_NAME_AR, r.ORIGINAL_AMOUNT, r.PREVIOUS_APPROVED_AMOUNT, "
        "r.REVISED_AMOUNT, r.DIFFERENCE_AMOUNT, r.DIFFERENCE_PCT, r.STATUS, r.REASON, r.REJECTION_REASON, "
        "r.REVISED_BY, r.REVISED_AT, r.APPROVED_BY, r.APPROVED_AT "
        "FROM BUDGET_REVISION_HISTORY r JOIN BX_BRANCH b ON b.BRANCH_ID = r.BRANCH_ID "
        "JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = r.GL_ACCOUNT_ID "
        f"WHERE r.BUDGET_ID = :b AND r.BRANCH_ID IN {br_in}{extra} ORDER BY r.REVISED_AT DESC, r.REVISION_ID DESC", p)
