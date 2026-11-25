"""Demo Donuts 2027 seed data: one source of truth for SQLite and the generated Oracle demo script.

January 2027 net sales budget / actual: Riyadh 200,000 / 185,000; Jeddah 150,000 / 165,000;
Al Khobar 100,000 / 90,000; total 450,000 / 440,000 (SAR).

  python -m app.seed sqlite data/demo.db          # (re)create the standalone demo database
  python -m app.seed oracle ../database/oracle/demo/20_demo_data.sql
"""
from __future__ import annotations

import calendar
import datetime as dt
import re
import sqlite3
import sys
from decimal import Decimal as D
from pathlib import Path

from . import db as _db  # noqa: F401  (registers Decimal/date adapters for sqlite3)
from .calc import cumulative, money
from .security import DEFAULT_ROLE_PERMISSIONS, hash_password

ROOT = Path(__file__).resolve().parents[2]
COMPANY = 1
BRANCHES = [(1, "RUH", "Riyadh", "الرياض"), (2, "JED", "Jeddah", "جدة"), (3, "KHB", "Al Khobar", "الخبر")]
SCALE = {1: D("1"), 2: D("0.75"), 3: D("0.5")}
SEASON = [D(x) for x in "1.00 0.95 1.10 1.05 1.00 0.90 0.85 0.90 1.00 1.05 1.05 1.15".split()]
JAN_RATIO = {1: D("0.925"), 2: D("1.10"), 3: D("0.90")}   # actual net / budget net, January
FEB_RATIO = {1: D("0.97"), 2: D("1.02"), 3: D("0.95")}
DEMO_PASSWORD = "Demo@2027"

# id, code, name, arabic, type, budget category, expense group, normal balance, vat, internal transfer, active
GL = [
    (1, "1000", "Cash and Bank", "النقد والبنوك", "ASSET", None, None, "D", "N", "N", "Y"),
    (2, "1300", "Inventory", "المخزون", "ASSET", None, None, "D", "N", "N", "Y"),
    (3, "1900", "Inter-branch Transfers", "تحويلات بين الفروع", "ASSET", None, None, "D", "N", "Y", "Y"),
    (4, "2000", "Accounts Payable", "الذمم الدائنة", "LIABILITY", None, None, "C", "N", "N", "Y"),
    (5, "2300", "VAT Output", "ضريبة القيمة المضافة", "LIABILITY", None, None, "C", "Y", "N", "Y"),
    (10, "4000", "Sales - Donuts", "مبيعات الدونات", "REVENUE", "SALES", None, "C", "N", "N", "Y"),
    (11, "4010", "Sales - Beverages", "مبيعات المشروبات", "REVENUE", "SALES", None, "C", "N", "N", "Y"),
    (12, "4100", "Sales Discounts", "خصومات المبيعات", "REVENUE", "DISCOUNT", None, "D", "N", "N", "Y"),
    (13, "4200", "Sales Returns", "مردودات المبيعات", "REVENUE", "RETURN", None, "D", "N", "N", "Y"),
    (20, "5000", "COGS - Ingredients", "تكلفة المبيعات - مكونات", "EXPENSE", "COGS", "Cost of sales", "D", "N", "N", "Y"),
    (21, "5010", "COGS - Packaging", "تكلفة المبيعات - تغليف", "EXPENSE", "COGS", "Cost of sales", "D", "N", "N", "Y"),
    (30, "6000", "Salaries and Wages", "الرواتب والأجور", "EXPENSE", "OPEX", "Staff", "D", "N", "N", "Y"),
    (31, "6100", "Rent", "الإيجار", "EXPENSE", "OPEX", "Occupancy", "D", "N", "N", "Y"),
    (32, "6200", "Utilities", "المرافق", "EXPENSE", "OPEX", "Utilities", "D", "N", "N", "Y"),
    (33, "6300", "Marketing", "التسويق", "EXPENSE", "OPEX", "Marketing", "D", "N", "N", "Y"),
    (34, "6400", "Repairs and Maintenance", "الإصلاح والصيانة", "EXPENSE", "OPEX", "Maintenance", "D", "N", "N", "Y"),
    (35, "6900", "Legacy Expense (inactive)", "مصروف قديم", "EXPENSE", "OPEX", "Other", "D", "N", "N", "N"),
]
GL_ID = {g[1]: g[0] for g in GL}
BUDGETED = ["4000", "4010", "4100", "4200", "5000", "5010", "6000", "6100", "6200", "6300"]


def budget_amount(branch: int, code: str, month: int) -> D:
    s, f = SCALE[branch], SEASON[month - 1]
    net = D(200000) * s * f
    base = {"4000": D(164000) * s * f, "4010": D(41000) * s * f, "4100": D(4000) * s * f,
            "4200": D(1000) * s * f, "5000": net * D("0.30"), "5010": net * D("0.05"),
            "6000": {1: D(40000), 2: D(32000), 3: D(24000)}[branch],
            "6100": {1: D(25000), 2: D(20000), 3: D(15000)}[branch],
            "6200": D(6000) * s * f, "6300": D(6150) * s * f}
    return money(base[code])


def ts(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s)


def rows() -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []
    add = lambda t, **r: out.append((t, r))  # noqa: E731

    add("DM_COMPANY", COMPANY_ID=COMPANY, COMPANY_CODE="DEMO", COMPANY_NAME="Demo Donuts Co.",
        COMPANY_NAME_AR="شركة ديمو دونتس", BASE_CURRENCY="SAR")
    for bid, code, name, ar in BRANCHES:
        add("DM_BRANCH", BRANCH_ID=bid, COMPANY_ID=COMPANY, BRANCH_CODE=code, BRANCH_NAME=name,
            BRANCH_NAME_AR=ar, IS_ACTIVE="Y")
    for gid, code, name, ar, typ, cat, grp, nb, vat, itr, act in GL:
        add("DM_GL_ACCOUNT", GL_ACCOUNT_ID=gid, COMPANY_ID=COMPANY, GL_CODE=code, GL_NAME=name, GL_NAME_AR=ar,
            ACCOUNT_TYPE=typ, BUDGET_CATEGORY=cat, EXPENSE_GROUP=grp, NORMAL_BALANCE=nb, IS_POSTING="Y",
            IS_ACTIVE=act, IS_VAT=vat, IS_INTERNAL_TRANSFER=itr)
    for year in (2026, 2027, 2028):
        for m in range(1, 13):
            add("DM_FIN_PERIOD", COMPANY_ID=COMPANY, FIN_YEAR=year, PERIOD_NO=m,
                PERIOD_NAME=dt.date(year, m, 1).strftime("%b-%Y"), START_DATE=dt.date(year, m, 1),
                END_DATE=dt.date(year, m, calendar.monthrange(year, m)[1]))

    users = [(1, "admin", "System Administrator", "ADMIN", "Y"), (2, "accountant", "Sara Accountant", "ACCOUNTANT", "Y"),
             (3, "fmanager", "Faisal Finance Manager", "FINANCE_MANAGER", "Y"),
             (4, "bm.riyadh", "Riyadh Branch Manager", "BRANCH_MANAGER", "N")]
    for uid, un, fn, role, allb in users:
        add("DM_USERS", USER_ID=uid, USERNAME=un, FULL_NAME=fn, ROLE_CODE=role, COMPANY_ID=COMPANY,
            ALL_BRANCHES=allb, IS_ACTIVE="Y",
            PASSWORD_HASH=hash_password(DEMO_PASSWORD, salt=f"ceevora-demo-{uid}".encode()))
    add("DM_USER_BRANCH", USER_ID=4, BRANCH_ID=1)
    for role, perms in DEFAULT_ROLE_PERMISSIONS.items():
        for p in perms:
            add("BUDGET_ROLE_PERMISSION", ROLE_CODE=role, PERMISSION_CODE=p)
    add("BUDGET_SETTINGS", SETTING_KEY="SOD_ENFORCED", SETTING_VALUE="Y")

    # ---- approved 2027 budget, version 2 ----
    add("BUDGET_MASTER", BUDGET_ID=1, COMPANY_ID=COMPANY, BUDGET_NO="BUD-2027-001",
        BUDGET_NAME="Demo Donuts Operating Budget 2027", BUDGET_TYPE="OPERATING", FIN_YEAR=2027,
        START_DATE=dt.date(2027, 1, 1), END_DATE=dt.date(2027, 12, 31), CURRENCY_CODE="SAR",
        ALLOCATION_METHOD="CALENDAR_DAYS", STATUS="APPROVED", VERSION_NO=2,
        REMARKS="Annual operating budget for all branches", ROW_VERSION=6,
        SUBMITTED_BY="accountant", SUBMITTED_AT=ts("2026-11-10 16:00:00"),
        APPROVED_BY="fmanager", APPROVED_AT=ts("2026-11-20 10:00:00"),
        CREATED_BY="accountant", CREATED_AT=ts("2026-11-02 09:00:00"),
        UPDATED_BY="fmanager", UPDATED_AT=ts("2026-11-24 12:05:00"))
    detail_id, detail_of = 0, {}
    revised = {(1, "6300", 3): D("1000.00")}
    for bid, *_ in BRANCHES:
        for code in BUDGETED:
            for m in range(1, 13):
                detail_id += 1
                orig = budget_amount(bid, code, m)
                cur = orig + revised.get((bid, code, m), 0)
                detail_of[(bid, code, m)] = (detail_id, orig)
                add("BUDGET_DETAILS", DETAIL_ID=detail_id, BUDGET_ID=1, BRANCH_ID=bid, GL_ACCOUNT_ID=GL_ID[code],
                    PERIOD_NO=m, ORIGINAL_AMOUNT=orig, CURRENT_AMOUNT=cur,
                    ROW_VERSION=3 if cur != orig else 2, CREATED_BY="accountant",
                    CREATED_AT=ts("2026-11-03 10:00:00"), UPDATED_BY="fmanager",
                    UPDATED_AT=ts("2026-11-24 12:00:00" if cur != orig else "2026-11-20 10:00:00"))
    hist = [("CREATE", None, "DRAFT", 0, "accountant", "2026-11-02 09:00:00", "Budget created", None),
            ("SUBMIT", "DRAFT", "SUBMITTED", 0, "accountant", "2026-11-05 14:00:00", "First submission", None),
            ("REJECT", "SUBMITTED", "DRAFT", 0, "fmanager", "2026-11-06 11:00:00", None,
             "Al Khobar marketing too high; align to 3% of gross sales"),
            ("SUBMIT", "DRAFT", "SUBMITTED", 0, "accountant", "2026-11-10 16:00:00", "Resubmitted after correction", None),
            ("APPROVE", "SUBMITTED", "APPROVED", 1, "fmanager", "2026-11-20 10:00:00", "Approved for 2027", None),
            ("REVISION_APPROVED", "APPROVED", "APPROVED", 2, "fmanager", "2026-11-24 12:00:00", "Revision 1 approved", None),
            ("REVISION_REJECTED", "APPROVED", "APPROVED", 2, "fmanager", "2026-11-24 12:05:00", "Revision 2 rejected",
             "Not supported by the utility tariff schedule")]
    for i, (a, p, n, v, by, at, rem, rej) in enumerate(hist, 1):
        add("BUDGET_APPROVAL_HISTORY", HISTORY_ID=i, BUDGET_ID=1, ACTION=a, PREVIOUS_STATUS=p, NEW_STATUS=n,
            VERSION_NO=v, ACTION_BY=by, ACTION_AT=ts(at), REMARKS=rem, REJECTION_REASON=rej)
    revs = [  # branch, gl, period, revised, status, base, version, rowver, reason, rej, revised_at, approved_at
        (1, "6300", 3, None, "APPROVED", 1, 2, 2, "Ramadan marketing campaign", None, "2026-11-23 09:30:00", "2026-11-24 12:00:00"),
        (3, "6200", 2, D("500"), "REJECTED", 1, None, 2, "Expected electricity tariff increase",
         "Not supported by the utility tariff schedule", "2026-11-23 10:00:00", "2026-11-24 12:05:00"),
        (2, "6100", 4, D("2000"), "PENDING", 2, None, 2, "Lease renewal at higher rent", None, "2026-11-25 08:30:00", None),
    ]
    for i, (b, code, p, delta, st, base, ver, rv, reason, rej, rat, aat) in enumerate(revs, 1):
        did, orig = detail_of[(b, code, p)]
        new = orig + (delta if delta is not None else revised[(b, code, p)])
        diff = new - orig
        add("BUDGET_REVISION_HISTORY", REVISION_ID=i, BUDGET_ID=1, DETAIL_ID=did, BRANCH_ID=b, GL_ACCOUNT_ID=GL_ID[code],
            PERIOD_NO=p, BASE_VERSION_NO=base, VERSION_NO=ver, ORIGINAL_AMOUNT=orig, PREVIOUS_APPROVED_AMOUNT=orig,
            REVISED_AMOUNT=new, DIFFERENCE_AMOUNT=diff, DIFFERENCE_PCT=money(diff / orig * 100),
            DETAIL_ROW_VERSION=rv, STATUS=st, REASON=reason, REJECTION_REASON=rej, REVISED_BY="accountant",
            REVISED_AT=ts(rat), APPROVED_BY="fmanager" if aat else None, APPROVED_AT=ts(aat) if aat else None)

    # ---- posted demo JVs ----
    jv = {"id": 0}

    def voucher(branch, date, jtype, lines, status="POSTED", desc=None):
        jv["id"] += 1
        add("DM_JV_HEADER", JV_ID=jv["id"], COMPANY_ID=COMPANY, BRANCH_ID=branch, JV_NO=f"JV-2027-{jv['id']:05d}",
            JV_DATE=date, JV_TYPE=jtype, STATUS=status, DESCRIPTION=desc or f"{jtype.title()} {date}")
        assert sum(d for _, d, _ in lines) == sum(c for _, _, c in lines), "unbalanced JV"
        for n, (code, dr, cr) in enumerate(lines, 1):
            add("DM_JV_DETAILS", JV_ID=jv["id"], LINE_NO=n, GL_ACCOUNT_ID=GL_ID[code], BRANCH_ID=branch,
                DEBIT=money(dr), CREDIT=money(cr), NARRATION=None)

    def daily_split(total: D, year: int, month: int, days: int) -> list[D]:
        w = [13 if dt.date(year, month, d).weekday() == 3 else 14 if dt.date(year, month, d).weekday() == 4 else 10
             for d in range(1, days + 1)]
        return [cumulative(total, w, d) - cumulative(total, w, d - 1) for d in range(1, days + 1)]

    def sales_month(month: int, days: int, comp: dict[int, dict[str, D]]):
        split = {b: {c: daily_split(a, 2027, month, days) for c, a in comp[b].items()} for b in comp}
        for d in range(1, days + 1):
            for b in comp:
                s = {c: split[b][c][d - 1] for c in comp[b]}
                net = s["4000"] + s["4010"] - s["4100"] - s["4200"]
                vat = money(net * D("0.15"))
                voucher(b, dt.date(2027, month, d), "SALES", [
                    ("1000", net + vat, 0), ("4000", 0, s["4000"]), ("4010", 0, s["4010"]),
                    ("4100", s["4100"], 0), ("4200", s["4200"], 0), ("2300", 0, vat)])

    sales_codes = ["4000", "4010", "4100", "4200"]
    sales_month(1, 31, {b: {c: money(budget_amount(b, c, 1) * JAN_RATIO[b]) for c in sales_codes} for b in SCALE})
    for b in SCALE:
        net_a = 200000 * SCALE[b] * JAN_RATIO[b]
        voucher(b, dt.date(2027, 1, 31), "COGS", [("5000", money(net_a * D("0.31")), 0),
                                                  ("5010", money(net_a * D("0.05")), 0),
                                                  ("1300", 0, money(net_a * D("0.36")))])
        exp = [("6000", budget_amount(b, "6000", 1)), ("6100", budget_amount(b, "6100", 1)),
               ("6200", money(budget_amount(b, "6200", 1) * D("1.08"))),
               ("6300", money(budget_amount(b, "6300", 1) * D("0.90")))]
        if b == 1:
            exp.append(("6400", D("1500.00")))  # unbudgeted actual
        voucher(b, dt.date(2027, 1, 31), "EXPENSE",
                [(c, a, 0) for c, a in exp] + [("2000", 0, sum(a for _, a in exp))])
    # February: first 15 days posted, sized from the calendar-day budget allocation.
    feb = {b: {c: money(budget_amount(b, c, 2) * 15 / 28 * FEB_RATIO[b]) for c in sales_codes} for b in SCALE}
    sales_month(2, 15, feb)
    # Must be excluded from actuals:
    voucher(1, dt.date(2027, 1, 20), "INTERNAL_TRANSFER", [("1900", D(5000), 0), ("1000", 0, D(5000))],
            desc="Cash transfer to head office")
    voucher(2, dt.date(2027, 1, 22), "INTERNAL_TRANSFER", [("1900", D(2000), 0), ("4000", 0, D(2000))],
            desc="Stock sent to Al Khobar booked to sales")
    voucher(2, dt.date(2027, 1, 25), "CREDIT_SETTLEMENT", [("1000", D(1150), 0), ("4000", 0, D(1000)), ("2300", 0, D(150))],
            desc="Corporate credit sale settlement (revenue already recognised)")
    voucher(1, dt.date(2027, 2, 15), "SALES", [("1000", D(1150), 0), ("4000", 0, D(1000)), ("2300", 0, D(150))],
            status="DRAFT", desc="Evening shift sales - not yet posted")
    return out


# ---------- writers ----------

def _sqlite_views() -> str:
    sql = (ROOT / "database" / "common" / "03_reporting_views.sql").read_text(encoding="utf-8")
    return re.sub(r"CREATE OR REPLACE VIEW (\w+)", r"DROP VIEW IF EXISTS \1; CREATE VIEW \1", sql)


def init_sqlite(path: Path, with_demo: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    conn = sqlite3.connect(path)
    conn.executescript((ROOT / "database" / "sqlite" / "schema.sql").read_text(encoding="utf-8"))
    conn.executescript(_sqlite_views())
    if with_demo:
        for table, r in rows():
            conn.execute(f"INSERT INTO {table} ({', '.join(r)}) VALUES ({', '.join(':' + k for k in r)})", r)
    conn.commit()
    conn.close()


def _lit(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, dt.datetime):
        return f"TIMESTAMP '{v:%Y-%m-%d %H:%M:%S}'"
    if isinstance(v, dt.date):
        return f"DATE '{v:%Y-%m-%d}'"
    if isinstance(v, (int, D)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def emit_oracle(path: Path) -> None:
    lines = ["-- GENERATED by backend/app/seed.py - Demo Donuts 2027. DEMO ONLY; never run in production.",
             "-- Run after 10_demo_master_tables.sql and install/*.sql. Requires NLS_LANG=.AL32UTF8 for Arabic names.",
             "SET DEFINE OFF"]
    for table, r in rows():
        lines.append(f"INSERT INTO {table} ({', '.join(r)}) VALUES ({', '.join(_lit(v) for v in r.values())});")
    for t, pk in [("BUDGET_MASTER", "BUDGET_ID"), ("BUDGET_DETAILS", "DETAIL_ID"),
                  ("BUDGET_APPROVAL_HISTORY", "HISTORY_ID"), ("BUDGET_REVISION_HISTORY", "REVISION_ID")]:
        lines.append(f"ALTER TABLE {t} MODIFY {pk} GENERATED BY DEFAULT AS IDENTITY (START WITH LIMIT VALUE);")
    lines.append("COMMIT;")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    kind, target = sys.argv[1], Path(sys.argv[2])
    init_sqlite(target) if kind == "sqlite" else emit_oracle(target)
    print(f"wrote {target}")
