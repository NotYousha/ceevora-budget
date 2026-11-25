"""Budget vs actual engine shared by dashboard, daily reports, management reports and drill-down.

Budget = approved monthly amounts (V_BUDGET_APPROVED) allocated to days with calc.allocate.
Actual = posted JV amounts (V_BUDGET_ACTUAL). Both sides use the same filters, so every screen reconciles.
"""
from __future__ import annotations

import datetime as dt
from collections import defaultdict
from decimal import Decimal

from .calc import ZERO, allocate, money, pct, pl_lines, pl_totals, remaining_target, variance
from .db import Db, as_date
from .services import ApiError, check_branch, require

EXPENSE = {"COGS", "OPEX"}


def branch_scope(user: dict, branch_id: int | None) -> list[int]:
    if branch_id:
        check_branch(user, branch_id)
        return [branch_id]
    return list(user["branch_ids"])


def gl_map(db: Db, company_id: int) -> dict[int, dict]:
    return {int(r["gl_account_id"]): r for r in db.query(
        "SELECT GL_ACCOUNT_ID, GL_CODE, GL_NAME, GL_NAME_AR, BUDGET_CATEGORY, EXPENSE_GROUP FROM BX_GL_ACCOUNT "
        "WHERE COMPANY_ID = :c AND BUDGET_CATEGORY IS NOT NULL", {"c": company_id})}


def branch_map(db: Db, company_id: int) -> dict[int, dict]:
    return {int(r["branch_id"]): r for r in db.query(
        "SELECT BRANCH_ID, BRANCH_CODE, BRANCH_NAME, BRANCH_NAME_AR FROM BX_BRANCH WHERE COMPANY_ID = :c "
        "ORDER BY BRANCH_ID", {"c": company_id})}


def facts(db: Db, company_id: int, d_from: dt.date, d_to: dt.date, branches: list[int],
          category: str | None = None, gl_id: int | None = None) -> list[dict]:
    """Rows of (branch, gl, category, year, period, budget, actual) for the date range."""
    if d_to < d_from:
        raise ApiError(422, "INVALID_RANGE", "Date to must not be before date from")
    br_in, p = db.in_list("br", branches)
    p.update({"c": company_id, "f": d_from, "t": d_to})
    extra = ""
    if category:
        extra += " AND g.BUDGET_CATEGORY = :cat"
        p["cat"] = category
    if gl_id:
        extra += " AND g.GL_ACCOUNT_ID = :gl"
        p["gl"] = gl_id
    acc: dict[tuple, list[Decimal]] = defaultdict(lambda: [ZERO, ZERO])
    budget = db.query(
        "SELECT a.BRANCH_ID, a.GL_ACCOUNT_ID, g.BUDGET_CATEGORY, a.FIN_YEAR, a.PERIOD_NO, a.BUDGET_AMOUNT, "
        "p.START_DATE, p.END_DATE, m.ALLOCATION_METHOD FROM V_BUDGET_APPROVED a "
        "JOIN BUDGET_MASTER m ON m.BUDGET_ID = a.BUDGET_ID "
        "JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = a.GL_ACCOUNT_ID "
        "JOIN BX_FIN_PERIOD p ON p.COMPANY_ID = a.COMPANY_ID AND p.FIN_YEAR = a.FIN_YEAR AND p.PERIOD_NO = a.PERIOD_NO "
        f"WHERE a.COMPANY_ID = :c AND a.BRANCH_ID IN {br_in} AND p.START_DATE <= :t AND p.END_DATE >= :f{extra}", p)
    for r in budget:
        k = (int(r["branch_id"]), int(r["gl_account_id"]), r["budget_category"], int(r["fin_year"]), int(r["period_no"]))
        acc[k][0] += allocate(r["budget_amount"], as_date(r["start_date"]), as_date(r["end_date"]),
                              r["allocation_method"], d_from, d_to)
    actual = db.query(
        "SELECT a.BRANCH_ID, a.GL_ACCOUNT_ID, g.BUDGET_CATEGORY, a.FIN_YEAR, a.PERIOD_NO, SUM(a.ACTUAL_AMOUNT) AS AMT "
        "FROM V_BUDGET_ACTUAL a JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = a.GL_ACCOUNT_ID "
        f"WHERE a.COMPANY_ID = :c AND a.BRANCH_ID IN {br_in} AND a.JV_DATE BETWEEN :f AND :t{extra} "
        "GROUP BY a.BRANCH_ID, a.GL_ACCOUNT_ID, g.BUDGET_CATEGORY, a.FIN_YEAR, a.PERIOD_NO", p)
    for r in actual:
        k = (int(r["branch_id"]), int(r["gl_account_id"]), r["budget_category"], int(r["fin_year"]), int(r["period_no"]))
        acc[k][1] += money(r["amt"])
    return [{"branch_id": k[0], "gl_account_id": k[1], "category": k[2], "fin_year": k[3], "period_no": k[4],
             "budget": v[0], "actual": v[1]} for k, v in acc.items()]


def group(rows: list[dict], key) -> dict:
    out: dict = defaultdict(lambda: [ZERO, ZERO])
    for r in rows:
        k = key(r)
        out[k][0] += r["budget"]
        out[k][1] += r["actual"]
    return out


def by_category(rows: list[dict]) -> dict[str, tuple]:
    return {k: tuple(v) for k, v in group(rows, lambda r: r["category"]).items()}


def provisional(db: Db, company_id: int, d_from: dt.date, d_to: dt.date, branches: list[int]) -> bool:
    """True when unposted vouchers exist in the range: actuals are incomplete."""
    br_in, p = db.in_list("br", branches)
    return db.one(f"SELECT COUNT(*) AS N FROM BX_JV_HEADER WHERE COMPANY_ID = :c AND BRANCH_ID IN {br_in} "
                  "AND JV_DATE BETWEEN :f AND :t AND STATUS = 'DRAFT'",
                  {**p, "c": company_id, "f": d_from, "t": d_to})["n"] > 0


def period_of(db: Db, company_id: int, day: dt.date) -> dict:
    r = db.one("SELECT FIN_YEAR, PERIOD_NO, START_DATE, END_DATE FROM BX_FIN_PERIOD WHERE COMPANY_ID = :c "
               "AND START_DATE <= :d AND END_DATE >= :d", {"c": company_id, "d": day})
    if not r:
        raise ApiError(422, "NO_PERIOD", f"No financial period configured for {day}")
    return {**r, "start_date": as_date(r["start_date"]), "end_date": as_date(r["end_date"])}


def year_range(db: Db, company_id: int, year: int, period_no: int | None = None) -> tuple[dt.date, dt.date]:
    p = {"c": company_id, "y": year}
    extra = ""
    if period_no:
        extra, p["p"] = " AND PERIOD_NO = :p", period_no
    r = db.one(f"SELECT MIN(START_DATE) AS S, MAX(END_DATE) AS E FROM BX_FIN_PERIOD WHERE COMPANY_ID = :c AND FIN_YEAR = :y{extra}", p)
    if not r or r["s"] is None:
        raise ApiError(422, "NO_PERIOD", "Financial year/period is not configured")
    return as_date(r["s"]), as_date(r["e"])


def resolve_range(db: Db, company_id: int, q: dict) -> tuple[dt.date, dt.date, str]:
    t = (q.get("period_type") or "MTD").upper()
    day = q.get("date") or dt.date.today()
    if t == "DAILY":
        return day, day, f"Day {day}"
    if t == "MTD":
        p = period_of(db, company_id, day)
        return p["start_date"], day, f"MTD to {day}"
    if t == "YTD":
        p = period_of(db, company_id, day)
        s, _ = year_range(db, company_id, int(p["fin_year"]))
        return s, day, f"YTD to {day}"
    if t == "MONTHLY":
        s, e = year_range(db, company_id, q["year"], q.get("period_no") or 1)
        return s, e, f"Period {q.get('period_no') or 1}/{q['year']}"
    if t == "YEARLY":
        s, e = year_range(db, company_id, q["year"])
        return s, e, f"Year {q['year']}"
    if t == "CUSTOM":
        if not q.get("date_from") or not q.get("date_to"):
            raise ApiError(422, "INVALID_RANGE", "Custom range needs date_from and date_to")
        return q["date_from"], q["date_to"], f"{q['date_from']} to {q['date_to']}"
    raise ApiError(422, "INVALID_PERIOD_TYPE", "period_type must be DAILY, MTD, MONTHLY, YTD, YEARLY or CUSTOM")


def bva(b, a, category: str) -> dict:
    v = variance(category, b, a)
    return {"budget": money(b), "actual": money(a), "variance": v, "achievement_pct": pct(a, b), "favourable": v >= 0}


# ---------------- dashboard ----------------

def dashboard(db: Db, user: dict, year: int, period_no: int | None, d_from: dt.date | None, d_to: dt.date | None,
              branch_id: int | None, category: str | None, gl_id: int | None) -> dict:
    require(user, "DASHBOARD_VIEW")
    c = user["company_id"]
    branches = branch_scope(user, branch_id)
    if d_from and d_to:
        f, t = d_from, d_to
    else:
        f, t = year_range(db, c, year, period_no)
    rows = facts(db, c, f, t, branches, category, gl_id)
    pl = pl_totals(by_category(rows))
    exp_b = pl["COGS"][0] + pl["OPEX"][0]
    exp_a = pl["COGS"][1] + pl["OPEX"][1]
    kpis = {"net_sales": bva(*pl["NET_SALES"], "SALES"), "expenses": bva(exp_b, exp_a, "OPEX"),
            "gross_profit": bva(*pl["GROSS_PROFIT"], "SALES"), "operating_profit": bva(*pl["OPERATING_PROFIT"], "SALES")}
    names = branch_map(db, c)
    per_branch = defaultdict(list)
    for r in rows:
        per_branch[r["branch_id"]].append(r)
    branch_rows = []
    for b in branches:
        bpl = pl_totals(by_category(per_branch.get(b, [])))
        eb, ea = bpl["COGS"][0] + bpl["OPEX"][0], bpl["COGS"][1] + bpl["OPEX"][1]
        branch_rows.append({"branch_id": b, "branch_name": names[b]["branch_name"],
                            "branch_name_ar": names[b]["branch_name_ar"],
                            "sales_budget": bpl["NET_SALES"][0], "sales_actual": bpl["NET_SALES"][1],
                            "expense_budget": eb, "expense_actual": ea, "utilization_pct": pct(ea, eb),
                            "profit_budget": bpl["OPERATING_PROFIT"][0], "profit_actual": bpl["OPERATING_PROFIT"][1]})
    ys, ye = year_range(db, c, year)
    trend_rows = facts(db, c, ys, ye, branches, category, gl_id)
    trend = []
    by_period = defaultdict(list)
    for r in trend_rows:
        if r["fin_year"] == year:
            by_period[r["period_no"]].append(r)
    for p in sorted({int(x["period_no"]) for x in db.query(
            "SELECT PERIOD_NO FROM BX_FIN_PERIOD WHERE COMPANY_ID = :c AND FIN_YEAR = :y", {"c": c, "y": year})}):
        tp = pl_totals(by_category(by_period.get(p, [])))
        trend.append({"period_no": p, "sales_budget": tp["NET_SALES"][0], "sales_actual": tp["NET_SALES"][1],
                      "profit_budget": tp["OPERATING_PROFIT"][0], "profit_actual": tp["OPERATING_PROFIT"][1]})
    gl = gl_map(db, c)
    pie = group([r for r in rows if r["category"] in EXPENSE],
                lambda r: gl[r["gl_account_id"]]["expense_group"] or r["category"])
    return {"date_from": f, "date_to": t, "kpis": kpis, "branches": branch_rows, "trend": trend,
            "expense_categories": [{"group": k, "budget": v[0], "actual": v[1]} for k, v in sorted(pie.items())],
            "provisional": provisional(db, c, f, t, branches)}


def drill_gl(db: Db, user: dict, d_from: dt.date, d_to: dt.date, branch_id: int | None, category: str | None) -> list[dict]:
    require(user, "DRILLDOWN_VIEW")
    c = user["company_id"]
    gl = gl_map(db, c)
    g = group(facts(db, c, d_from, d_to, branch_scope(user, branch_id), category), lambda r: r["gl_account_id"])
    return [{"gl_account_id": k, "gl_code": gl[k]["gl_code"], "gl_name": gl[k]["gl_name"], "gl_name_ar": gl[k]["gl_name_ar"],
             "category": gl[k]["budget_category"], **bva(v[0], v[1], gl[k]["budget_category"])}
            for k, v in sorted(g.items(), key=lambda kv: gl[kv[0]]["gl_code"])]


def drill_transactions(db: Db, user: dict, d_from: dt.date, d_to: dt.date, branch_id: int | None, gl_id: int,
                       page: int, page_size: int) -> dict:
    require(user, "DRILLDOWN_VIEW")
    br_in, p = db.in_list("br", branch_scope(user, branch_id))
    p.update({"c": user["company_id"], "f": d_from, "t": d_to, "g": gl_id})
    base = ("FROM BX_JV_HEADER h JOIN BX_JV_DETAILS l ON l.JV_ID = h.JV_ID JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = l.GL_ACCOUNT_ID "
            f"WHERE h.COMPANY_ID = :c AND COALESCE(l.BRANCH_ID, h.BRANCH_ID) IN {br_in} AND l.GL_ACCOUNT_ID = :g "
            "AND h.JV_DATE BETWEEN :f AND :t AND h.STATUS = 'POSTED' "
            "AND h.JV_TYPE NOT IN ('INTERNAL_TRANSFER', 'CREDIT_SETTLEMENT')")
    total = db.one(f"SELECT COUNT(*) AS N {base}", p)["n"]
    items = db.query(db.page(
        "SELECT h.JV_ID, h.JV_NO, h.JV_DATE, h.JV_TYPE, h.DESCRIPTION, COALESCE(l.BRANCH_ID, h.BRANCH_ID) AS BRANCH_ID, "
        "l.LINE_NO, l.DEBIT, l.CREDIT, CASE WHEN g.NORMAL_BALANCE = 'C' THEN l.CREDIT - l.DEBIT ELSE l.DEBIT - l.CREDIT END AS AMOUNT "
        f"{base} ORDER BY h.JV_DATE, h.JV_ID, l.LINE_NO", (page - 1) * page_size, page_size), p)
    return {"items": items, "total": int(total), "page": page, "page_size": page_size}


# ---------------- daily ----------------

def daily_performance(db: Db, user: dict, day: dt.date, branch_id: int | None) -> dict:
    require(user, "REPORT_VIEW")
    c = user["company_id"]
    branches = branch_scope(user, branch_id)
    per = period_of(db, c, day)
    names = branch_map(db, c)
    sales = ("SALES", "DISCOUNT", "RETURN")

    def net(rows, b=None):
        return pl_totals(by_category([r for r in rows if (b is None or r["branch_id"] == b) and r["category"] in sales]))["NET_SALES"]

    d_rows = facts(db, c, day, day, branches)
    m_rows = facts(db, c, per["start_date"], day, branches)
    full = facts(db, c, per["start_date"], per["end_date"], branches)

    def row(b, label, label_ar):
        db_, da = net(d_rows, b)
        mb, ma = net(m_rows, b)
        monthly = net(full, b)[0]
        rt = remaining_target(monthly, ma, day, per["end_date"])
        return {"branch_id": b, "branch_name": label, "branch_name_ar": label_ar,
                "daily_budget": db_, "daily_actual": da, "daily_variance": da - db_, "daily_achievement_pct": pct(da, db_),
                "mtd_budget": mb, "mtd_actual": ma, "mtd_variance": ma - mb, "mtd_achievement_pct": pct(ma, mb),
                "monthly_budget": monthly, **rt,
                "provisional": provisional(db, c, day, day, [b] if b else branches)}
    rows = [row(b, names[b]["branch_name"], names[b]["branch_name_ar"]) for b in branches]
    return {"business_date": day, "period": per, "rows": rows,
            "consolidated": row(None, "Consolidated", "الإجمالي الموحد")}


def daily_pl(db: Db, user: dict, day: dt.date, branch_id: int | None, basis: str) -> dict:
    require(user, "REPORT_VIEW")
    c = user["company_id"]
    branches = branch_scope(user, branch_id)
    f = period_of(db, c, day)["start_date"] if basis == "MTD" else day
    return {"business_date": day, "basis": basis, "date_from": f, "date_to": day,
            "lines": pl_lines(by_category(facts(db, c, f, day, branches))),
            "provisional": provisional(db, c, f, day, branches)}
