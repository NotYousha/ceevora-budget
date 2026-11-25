"""Management reports R01-R06 on one framework: resolve range -> facts -> rows -> sort/page -> totals."""
from __future__ import annotations

from collections import defaultdict

from .analytics import branch_map, branch_scope, bva, by_category, facts, gl_map, group, provisional, resolve_range
from .calc import ZERO, pct, pl_lines, pl_totals
from .db import Db
from .services import ApiError, now, require

TITLES = {
    "R01": "Sales Actual vs Budget",
    "R02": "Branch-wise Actual vs Budget",
    "R03": "Expense Actual vs Budget",
    "R04": "Profit and Loss Actual vs Budget",
    "R05": "GL Account-wise Budget Variance",
    "R06": "Consolidated Company Budget Performance",
}
M, P, T = "money", "pct", "text"


def _col(key, label, typ=M):
    return {"key": key, "label": label, "type": typ}


def build(db: Db, user: dict, code: str, q: dict) -> dict:
    require(user, "REPORT_VIEW")
    if code not in TITLES:
        raise ApiError(404, "NOT_FOUND", "Unknown report")
    c = user["company_id"]
    branches = branch_scope(user, q.get("branch_id"))
    f, t, label = resolve_range(db, c, q)
    rows_f = facts(db, c, f, t, branches, q.get("category"))
    names, gl = branch_map(db, c), gl_map(db, c)
    per_branch = defaultdict(list)
    for r in rows_f:
        per_branch[r["branch_id"]].append(r)
    totals = None

    if code == "R01":
        cols = [_col("branch_name", "Branch", T), _col("gross_budget", "Gross Sales Budget"), _col("gross_actual", "Gross Sales Actual"),
                _col("budget", "Net Sales Budget"), _col("actual", "Net Sales Actual"), _col("variance", "Variance"),
                _col("achievement_pct", "Achievement %", P)]
        rows = []
        for b in branches:
            pl = pl_totals(by_category(per_branch.get(b, [])))
            rows.append({"branch_name": names[b]["branch_name"], "gross_budget": pl["GROSS_SALES"][0],
                         "gross_actual": pl["GROSS_SALES"][1], **bva(*pl["NET_SALES"], "SALES")})
        pl = pl_totals(by_category(rows_f))
        totals = {"branch_name": "Total", "gross_budget": pl["GROSS_SALES"][0], "gross_actual": pl["GROSS_SALES"][1],
                  **bva(*pl["NET_SALES"], "SALES")}
    elif code == "R02":
        cols = [_col("branch_name", "Branch", T), _col("sales_budget", "Net Sales Budget"), _col("sales_actual", "Net Sales Actual"),
                _col("sales_variance", "Sales Variance"), _col("expense_budget", "Expense Budget"),
                _col("expense_actual", "Expense Actual"), _col("expense_variance", "Expense Variance"),
                _col("profit_budget", "Op. Profit Budget"), _col("profit_actual", "Op. Profit Actual"),
                _col("profit_variance", "Profit Variance"), _col("achievement_pct", "Sales Achievement %", P)]

        def r02(label, rs):
            pl = pl_totals(by_category(rs))
            eb, ea = pl["COGS"][0] + pl["OPEX"][0], pl["COGS"][1] + pl["OPEX"][1]
            s, o = pl["NET_SALES"], pl["OPERATING_PROFIT"]
            return {"branch_name": label, "sales_budget": s[0], "sales_actual": s[1], "sales_variance": s[1] - s[0],
                    "expense_budget": eb, "expense_actual": ea, "expense_variance": eb - ea,
                    "profit_budget": o[0], "profit_actual": o[1], "profit_variance": o[1] - o[0],
                    "achievement_pct": pct(s[1], s[0])}
        rows = [r02(names[b]["branch_name"], per_branch.get(b, [])) for b in branches]
        totals = r02("Total", rows_f)
    elif code in ("R03", "R05"):
        cats = {"COGS", "OPEX"} if code == "R03" else None
        g = group([r for r in rows_f if cats is None or r["category"] in cats], lambda r: r["gl_account_id"])
        rows = []
        for k, (b, a) in g.items():
            info = gl[k]
            row = {"gl_code": info["gl_code"], "gl_name": info["gl_name"], "category": info["budget_category"],
                   "expense_group": info["expense_group"], **bva(b, a, info["budget_category"])}
            row["variance_pct"] = pct(row["variance"], b)
            row["status"] = "UNBUDGETED" if b == 0 and a != 0 else ("FAVOURABLE" if row["favourable"] else "UNFAVOURABLE")
            rows.append(row)
        if code == "R03":
            cols = [_col("gl_code", "GL Code", T), _col("gl_name", "Description", T), _col("expense_group", "Expense Group", T),
                    _col("budget", "Budget"), _col("actual", "Actual"), _col("variance", "Variance"),
                    _col("achievement_pct", "Utilization %", P)]
            b, a = sum((r["budget"] for r in rows), ZERO), sum((r["actual"] for r in rows), ZERO)
            totals = {"gl_code": "Total", **bva(b, a, "OPEX")}
        else:
            cols = [_col("gl_code", "GL Code", T), _col("gl_name", "Description", T), _col("category", "Category", T),
                    _col("budget", "Budget"), _col("actual", "Actual"), _col("variance", "Variance"),
                    _col("variance_pct", "Variance %", P), _col("status", "Status", T)]
        rows.sort(key=lambda r: r["gl_code"])
    elif code == "R04":
        cols = [_col("line", "Line", T), _col("budget", "Budget"), _col("actual", "Actual"), _col("variance", "Variance"),
                _col("achievement_pct", "Achievement %", P), _col("pct_of_net_sales", "% of Net Sales", P)]
        rows = pl_lines(by_category(rows_f))
    else:  # R06
        cols = [_col("line", "Line", T)] + [_col(f"b{b}", names[b]["branch_name"]) for b in branches] + [
            _col("actual", "Consolidated Actual"), _col("budget", "Consolidated Budget"), _col("variance", "Variance"),
            _col("achievement_pct", "Achievement %", P)]
        branch_pl = {b: pl_totals(by_category(per_branch.get(b, []))) for b in branches}
        rows = []
        for line in pl_lines(by_category(rows_f)):
            rows.append({**line, **{f"b{b}": branch_pl[b][line["line"]][1] for b in branches}})

    sort = q.get("sort")
    if sort and any(cdef["key"] == sort for cdef in cols):
        rows.sort(key=lambda r: (r.get(sort) is None, r.get(sort) if r.get(sort) is not None else 0), reverse=bool(q.get("desc")))
    page, size = q.get("page") or 1, q.get("page_size") or 100
    company = db.one("SELECT COMPANY_NAME, BASE_CURRENCY FROM BX_COMPANY WHERE COMPANY_ID = :c", {"c": c})
    return {"code": code, "title": TITLES[code], "company": company["company_name"], "currency": company["base_currency"],
            "branches": ", ".join(names[b]["branch_name"] for b in branches), "period_label": label,
            "date_from": f, "date_to": t, "generated_at": now(), "columns": cols,
            "rows": rows[(page - 1) * size: page * size], "total_rows": len(rows), "page": page, "page_size": size,
            "totals": totals, "provisional": provisional(db, c, f, t, branches)}


