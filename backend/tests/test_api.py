import sqlite3
from decimal import Decimal as D

import pytest

from conftest import idem, login

API = "/api/v1"


def j(r, status=200):
    assert r.status_code == status, r.text
    return r.json()


def amounts(n, v):
    return [str(v)] * n


# ---------------- auth & tenant ----------------

def test_login_and_tenant_isolation(client):
    assert client.post(f"{API}/auth/login", json={"tenant": "DEMO", "username": "admin", "password": "bad"}).status_code == 401
    assert client.post(f"{API}/auth/login", json={"tenant": "OTHER", "username": "admin", "password": "Demo@2027"}).status_code == 401
    assert client.get(f"{API}/auth/me").status_code == 401
    assert client.get(f"{API}/auth/me", headers={"Authorization": "Bearer x.y.z"}).json()["error"]["code"] == "INVALID_TOKEN"
    me = j(client.get(f"{API}/auth/me", headers=login(client, "bm.riyadh")))
    assert me["branch_ids"] == [1] and "BUDGET_CREATE" not in me["permissions"]


# ---------------- reconciliation (demo data) ----------------

def test_january_demo_figures_reconcile_everywhere(client):
    h = login(client, "fmanager")
    r01 = j(client.get(f"{API}/reports/R01", params={"period_type": "MONTHLY", "year": 2027, "period_no": 1}, headers=h))
    got = {r["branch_name"]: (D(r["budget"]), D(r["actual"])) for r in r01["rows"]}
    assert got == {"Riyadh": (200000, 185000), "Jeddah": (150000, 165000), "Al Khobar": (100000, 90000)}
    assert (D(r01["totals"]["budget"]), D(r01["totals"]["actual"])) == (450000, 440000)
    assert r01["totals"]["achievement_pct"] == "97.78"
    dash = j(client.get(f"{API}/dashboard", params={"year": 2027, "period_no": 1}, headers=h))
    assert D(dash["kpis"]["net_sales"]["budget"]) == 450000 and D(dash["kpis"]["net_sales"]["actual"]) == 440000
    r02 = j(client.get(f"{API}/reports/R02", params={"period_type": "MONTHLY", "year": 2027, "period_no": 1}, headers=h))
    assert D(r02["totals"]["profit_actual"]) == D(dash["kpis"]["operating_profit"]["actual"])
    assert D(r02["totals"]["expense_budget"]) == D(dash["kpis"]["expenses"]["budget"])
    r04 = j(client.get(f"{API}/reports/R04", params={"period_type": "MONTHLY", "year": 2027, "period_no": 1}, headers=h))
    op = next(x for x in r04["rows"] if x["line"] == "OPERATING_PROFIT")
    assert op["actual"] == dash["kpis"]["operating_profit"]["actual"]
    r06 = j(client.get(f"{API}/reports/R06", params={"period_type": "MONTHLY", "year": 2027, "period_no": 1}, headers=h))
    net = next(x for x in r06["rows"] if x["line"] == "NET_SALES")
    assert (D(net["b1"]), D(net["b2"]), D(net["b3"]), D(net["actual"])) == (185000, 165000, 90000, 440000)


def test_engine_matches_oracle_variance_view(client, tmp_path):
    h = login(client, "fmanager")
    r05 = j(client.get(f"{API}/reports/R05", params={"period_type": "YEARLY", "year": 2027, "page_size": 1000}, headers=h))
    con = sqlite3.connect(tmp_path / "t.db")
    view = dict(((code, (D(str(b)).quantize(D("0.01")), D(str(a)).quantize(D("0.01"))))
                 for code, b, a in con.execute("SELECT GL_CODE, SUM(BUDGET_AMOUNT), SUM(ACTUAL_AMOUNT) FROM V_BUDGET_VARIANCE "
                                               "WHERE FIN_YEAR = 2027 GROUP BY GL_CODE")))
    assert {r["gl_code"]: (D(r["budget"]), D(r["actual"])) for r in r05["rows"]} == view


def test_unbudgeted_actuals_and_exclusions(client):
    h = login(client, "fmanager")
    r05 = j(client.get(f"{API}/reports/R05", params={"period_type": "MONTHLY", "year": 2027, "period_no": 1}, headers=h))
    rep = next(r for r in r05["rows"] if r["gl_code"] == "6400")
    assert rep["status"] == "UNBUDGETED" and D(rep["actual"]) == 1500 and rep["variance_pct"] is None
    # Jeddah internal-transfer and credit-settlement vouchers credit 4000 but must not count as sales
    tx = j(client.get(f"{API}/drilldown/transactions", params={"date_from": "2027-01-01", "date_to": "2027-01-31",
                                                                "branch_id": 2, "gl_account_id": 10, "page_size": 500}, headers=h))
    assert {t["jv_type"] for t in tx["items"]} == {"SALES"}
    gl = j(client.get(f"{API}/drilldown/gl", params={"date_from": "2027-01-01", "date_to": "2027-01-31", "branch_id": 2}, headers=h))
    assert D(next(g for g in gl if g["gl_code"] == "4000")["actual"]) == sum(D(t["amount"]) for t in tx["items"])


def test_pending_and_rejected_revisions_do_not_affect_reporting(client):
    h = login(client, "fmanager")
    p = {"period_type": "MONTHLY", "year": 2027, "branch_id": 2, "category": "OPEX"}
    apr = j(client.get(f"{API}/reports/R03", params={**p, "period_no": 4}, headers=h))
    assert D(next(r for r in apr["rows"] if r["gl_code"] == "6100")["budget"]) == 20000   # pending 22,000 ignored
    feb = j(client.get(f"{API}/reports/R03", params={**p, "branch_id": 3, "period_no": 2}, headers=h))
    assert D(next(r for r in feb["rows"] if r["gl_code"] == "6200")["budget"]) == D("2850")  # rejected +500 ignored
    mar = j(client.get(f"{API}/reports/R03", params={**p, "branch_id": 1, "period_no": 3}, headers=h))
    assert D(next(r for r in mar["rows"] if r["gl_code"] == "6300")["budget"]) == D("7765")  # approved revision applied


def test_daily_reports_and_provisional_flag(client):
    h = login(client, "fmanager")
    perf = j(client.get(f"{API}/daily/performance", params={"date": "2027-01-31"}, headers=h))
    ruh = next(r for r in perf["rows"] if r["branch_id"] == 1)
    assert D(ruh["mtd_budget"]) == 200000 and D(ruh["mtd_actual"]) == 185000
    assert D(ruh["remaining_target"]) == 15000 and ruh["required_avg_daily"] is None   # month end, unmet => N/A
    assert D(perf["consolidated"]["mtd_actual"]) == 440000
    assert D(sum(D(r["daily_budget"]) for r in perf["rows"])) == D(perf["consolidated"]["daily_budget"])
    assert not perf["consolidated"]["provisional"]
    pl = j(client.get(f"{API}/daily/pl", params={"date": "2027-02-15", "basis": "DAY"}, headers=h))
    assert pl["provisional"] is True
    assert not j(client.get(f"{API}/daily/pl", params={"date": "2027-01-15"}, headers=h))["provisional"]
    mid = j(client.get(f"{API}/daily/performance", params={"date": "2027-01-21", "branch_id": 1}, headers=h))["rows"][0]
    assert mid["days_remaining"] == 10 and D(mid["required_avg_daily"]) == (D(mid["remaining_target"]) / 10).quantize(D("0.01"), "ROUND_HALF_UP")


def test_zero_budget_year_returns_na(client):
    h = login(client, "fmanager")
    r = j(client.get(f"{API}/reports/R01", params={"period_type": "YEARLY", "year": 2026}, headers=h))
    assert r["totals"]["achievement_pct"] is None and D(r["totals"]["budget"]) == 0


# ---------------- workflow ----------------

def create_2028(client, h):
    return j(client.post(f"{API}/budgets", json={"budget_no": "BUD-2028-001", "budget_name": "Plan 2028", "fin_year": 2028},
                         headers={**h, **idem()}))


def test_full_budget_lifecycle(client):
    acc, fm = login(client, "accountant"), login(client, "fmanager")
    b = create_2028(client, acc)
    assert b["status"] == "DRAFT" and b["currency_code"] == "SAR" and b["start_date"].startswith("2028-01-01")
    dup = client.post(f"{API}/budgets", json={"budget_no": "BUD-2028-XYZ", "budget_name": "x", "fin_year": 2028}, headers=acc)
    assert dup.status_code == 409 and dup.json()["error"]["code"] == "DUPLICATE_BUDGET"
    bid, rv = b["budget_id"], b["row_version"]
    # validation
    bad = client.put(f"{API}/budgets/{bid}/entry", headers=acc, json={"branch_id": 1, "row_version": rv, "lines": [
        {"gl_account_id": 10, "amounts": amounts(12, 1)}, {"gl_account_id": 10, "amounts": amounts(12, 1)}]})
    assert bad.json()["error"]["code"] == "DUPLICATE_LINE"
    bad = client.put(f"{API}/budgets/{bid}/entry", headers=acc, json={"branch_id": 1, "row_version": rv, "lines": [
        {"gl_account_id": 35, "amounts": amounts(12, 1)}]})
    assert bad.json()["error"]["code"] == "INVALID_ACCOUNT"      # inactive account
    bad = client.put(f"{API}/budgets/{bid}/entry", headers=acc, json={"branch_id": 1, "row_version": rv, "lines": [
        {"gl_account_id": 5, "amounts": amounts(12, 1)}]})
    assert bad.json()["error"]["code"] == "INVALID_ACCOUNT"      # VAT account
    assert client.post(f"{API}/budgets/{bid}/submit", json={"row_version": rv}, headers=acc).json()["error"]["code"] == "EMPTY_BUDGET"
    e = j(client.put(f"{API}/budgets/{bid}/entry", headers=acc, json={"branch_id": 1, "row_version": rv, "lines": [
        {"gl_account_id": 10, "amounts": amounts(12, "1000.10")}, {"gl_account_id": 30, "amounts": amounts(12, 400)}]}))
    assert D(e["summary"]["annual"]["OPERATING_PROFIT"]) == D("7201.20")
    stale = client.put(f"{API}/budgets/{bid}/entry", headers=acc, json={"branch_id": 1, "row_version": rv, "lines": []})
    assert stale.status_code == 409 and stale.json()["error"]["code"] == "STALE_DATA"
    rv = e["budget"]["row_version"]
    # remove one account, reopen and verify persisted
    j(client.put(f"{API}/budgets/{bid}/entry", headers=acc, json={"branch_id": 1, "row_version": rv, "lines": [
        {"gl_account_id": 10, "amounts": amounts(12, "1000.10")}]}))
    again = j(client.get(f"{API}/budgets/{bid}/entry", params={"branch_id": 1}, headers=login(client, "accountant")))
    assert [ln["gl_code"] for ln in again["lines"]] == ["4000"] and D(again["lines"][0]["annual_total"]) == D("12001.20")
    rv = again["budget"]["row_version"]
    # accountant cannot approve
    assert client.post(f"{API}/budgets/{bid}/approve", json={"row_version": rv}, headers=acc).status_code == 403
    s = j(client.post(f"{API}/budgets/{bid}/submit", json={"row_version": rv, "remarks": "ready"}, headers={**acc, **idem()}))
    assert s["status"] == "SUBMITTED"
    assert client.put(f"{API}/budgets/{bid}/entry", headers=acc, json={"branch_id": 1, "row_version": s["row_version"],
                                                                       "lines": []}).json()["error"]["code"] == "NOT_EDITABLE"
    assert client.post(f"{API}/budgets/{bid}/reject", json={"row_version": s["row_version"], "reason": ""},
                       headers=fm).status_code == 422
    r = j(client.post(f"{API}/budgets/{bid}/reject", json={"row_version": s["row_version"], "reason": "Add expenses"}, headers=fm))
    assert r["status"] == "DRAFT"
    s = j(client.post(f"{API}/budgets/{bid}/submit", json={"row_version": r["row_version"]}, headers=acc))
    a = j(client.post(f"{API}/budgets/{bid}/approve", json={"row_version": s["row_version"]}, headers=fm))
    assert a["status"] == "APPROVED" and a["version_no"] == 1
    hist = j(client.get(f"{API}/budgets/{bid}/approval-history", headers=fm))
    assert [x["action"] for x in hist] == ["CREATE", "SUBMIT", "REJECT", "SUBMIT", "APPROVE"]
    assert hist[2]["rejection_reason"] == "Add expenses" and hist[4]["action_by"] == "fmanager"
    # after approval: no direct edits
    up = client.put(f"{API}/budgets/{bid}", json={"row_version": a["row_version"], "budget_name": "x"}, headers=acc)
    assert up.json()["error"]["code"] == "NOT_EDITABLE"

    # ---- revisions ----
    body = {"branch_id": 1, "gl_account_id": 10, "period_no": 2, "revised_amount": "1500.10", "reason": "Promo"}
    key = idem()
    r1 = j(client.post(f"{API}/budgets/{bid}/revisions", json=body, headers={**acc, **key}))
    replay = client.post(f"{API}/budgets/{bid}/revisions", json=body, headers={**acc, **key})
    assert replay.json() == r1 and replay.headers.get("Idempotent-Replay") == "true"
    assert client.post(f"{API}/budgets/{bid}/revisions", json=body, headers=acc).json()["error"]["code"] == "PENDING_EXISTS"
    new_line = j(client.post(f"{API}/budgets/{bid}/revisions", headers=acc, json={
        "branch_id": 2, "gl_account_id": 33, "period_no": 1, "revised_amount": "300", "reason": "New marketing line"}))
    rh = j(client.get(f"{API}/budgets/{bid}/revision-history", headers=fm))
    first = next(x for x in rh if x["revision_id"] == r1["revision_id"])
    assert first["status"] == "PENDING" and D(first["difference_amount"]) == 500 and D(first["difference_pct"]) == D("50.00")  # 500 / 1000.10 = 49.995 -> half-up
    assert next(x for x in rh if x["revision_id"] == new_line["revision_id"])["difference_pct"] is None  # from zero: N/A
    out = j(client.post(f"{API}/revisions/approve", json={"revision_ids": [r1["revision_id"], new_line["revision_id"]]}, headers=fm))
    assert out["version_no"] == 2 and sorted(out["approved"]) == sorted([r1["revision_id"], new_line["revision_id"]])
    line = j(client.get(f"{API}/budgets/{bid}/revision-line",
                        params={"branch_id": 1, "gl_account_id": 10, "period_no": 2}, headers=fm))
    assert D(line["original_amount"]) == D("1000.10") and D(line["current_amount"]) == D("1500.10")
    again = client.post(f"{API}/revisions/approve", json={"revision_ids": [r1["revision_id"]]}, headers=fm)
    assert again.json()["error"]["code"] == "ALREADY_DECIDED"
    r3 = j(client.post(f"{API}/budgets/{bid}/revisions", headers=acc, json={**body, "revised_amount": "900"}))
    assert client.post(f"{API}/revisions/reject", json={"revision_ids": [r3["revision_id"]], "reason": " "},
                       headers=fm).status_code == 422
    j(client.post(f"{API}/revisions/reject", json={"revision_ids": [r3["revision_id"]], "reason": "No"}, headers=fm))
    line = j(client.get(f"{API}/budgets/{bid}/revision-line",
                        params={"branch_id": 1, "gl_account_id": 10, "period_no": 2}, headers=fm))
    assert D(line["current_amount"]) == D("1500.10")
    assert j(client.get(f"{API}/budgets/{bid}", headers=fm))["version_no"] == 2
    v2 = j(client.get(f"{API}/budgets/{bid}/revision-history", params={"version": 2}, headers=fm))
    assert {x["revision_id"] for x in v2} >= {r1["revision_id"], new_line["revision_id"]}


def test_segregation_of_duties(client):
    adm = login(client, "admin")   # admin holds every permission
    b = create_2028(client, adm)
    e = j(client.put(f"{API}/budgets/{b['budget_id']}/entry", headers=adm, json={
        "branch_id": 1, "row_version": b["row_version"], "lines": [{"gl_account_id": 10, "amounts": amounts(12, 1)}]}))
    s = j(client.post(f"{API}/budgets/{b['budget_id']}/submit", json={"row_version": e["budget"]["row_version"]}, headers=adm))
    r = client.post(f"{API}/budgets/{b['budget_id']}/approve", json={"row_version": s["row_version"]}, headers=adm)
    assert r.status_code == 409 and r.json()["error"]["code"] == "SEGREGATION_OF_DUTIES"
    j(client.put(f"{API}/admin/settings", json={"sod_enforced": False}, headers=adm))
    assert j(client.post(f"{API}/budgets/{b['budget_id']}/approve", json={"row_version": s["row_version"]}, headers=adm))["status"] == "APPROVED"


def test_stale_revision_is_rejected(client, tmp_path):
    acc, fm = login(client, "accountant"), login(client, "fmanager")
    rid = j(client.post(f"{API}/budgets/1/revisions", headers=acc, json={
        "branch_id": 1, "gl_account_id": 30, "period_no": 6, "revised_amount": "41000", "reason": "Raise"}))["revision_id"]
    con = sqlite3.connect(tmp_path / "t.db")
    con.execute("UPDATE BUDGET_DETAILS SET ROW_VERSION = ROW_VERSION + 1 WHERE BUDGET_ID = 1 AND BRANCH_ID = 1 "
                "AND GL_ACCOUNT_ID = 30 AND PERIOD_NO = 6")
    con.commit()
    out = j(client.post(f"{API}/revisions/approve", json={"revision_ids": [rid]}, headers=fm))
    assert out["stale_rejected"] == [rid] and out["approved"] == [] and out["version_no"] == 2


def test_audit_tables_are_immutable(client, tmp_path):
    con = sqlite3.connect(tmp_path / "t.db")
    with pytest.raises(sqlite3.DatabaseError):
        con.execute("UPDATE BUDGET_APPROVAL_HISTORY SET REMARKS = 'x' WHERE HISTORY_ID = 1")
    with pytest.raises(sqlite3.DatabaseError):
        con.execute("DELETE FROM BUDGET_REVISION_HISTORY WHERE REVISION_ID = 1")
    with pytest.raises(sqlite3.DatabaseError):
        con.execute("UPDATE BUDGET_DETAILS SET ORIGINAL_AMOUNT = 1 WHERE DETAIL_ID = 1")


def test_branch_permissions(client):
    bm = login(client, "bm.riyadh")
    assert client.get(f"{API}/dashboard", params={"year": 2027, "branch_id": 2}, headers=bm).status_code == 403
    assert client.get(f"{API}/drilldown/transactions", params={"date_from": "2027-01-01", "date_to": "2027-01-31",
                                                               "branch_id": 3, "gl_account_id": 10}, headers=bm).status_code == 403
    perf = j(client.get(f"{API}/daily/performance", params={"date": "2027-01-31"}, headers=bm))
    assert [r["branch_id"] for r in perf["rows"]] == [1] and D(perf["consolidated"]["mtd_actual"]) == 185000
    assert client.post(f"{API}/budgets", json={"budget_no": "X1", "budget_name": "x", "fin_year": 2028}, headers=bm).status_code == 403
    assert client.get(f"{API}/budgets/1/entry", params={"branch_id": 1}, headers=bm).status_code == 403
    adm = login(client, "admin")
    m = j(client.get(f"{API}/admin/permissions", headers=adm))["matrix"]
    m["BRANCH_MANAGER"] = ["DASHBOARD_VIEW"]
    j(client.put(f"{API}/admin/permissions", json={"matrix": m}, headers=adm))
    assert client.get(f"{API}/reports/R01", params={"period_type": "MTD", "date": "2027-01-31"}, headers=bm).status_code == 403
    assert client.put(f"{API}/admin/permissions", json={"matrix": {"ADMIN": []}}, headers=adm).status_code == 422
    assert client.get(f"{API}/admin/permissions", headers=bm).status_code == 403


def test_report_sorting_paging_and_lookups(client):
    h = login(client, "fmanager")
    r = j(client.get(f"{API}/reports/R05", params={"period_type": "YTD", "date": "2027-02-15", "sort": "actual",
                                                   "desc": True, "page_size": 3}, headers=h))
    assert len(r["rows"]) == 3 and r["total_rows"] > 3
    vals = [D(x["actual"]) for x in r["rows"]]
    assert vals == sorted(vals, reverse=True)
    assert j(client.get(f"{API}/lookups/years", headers=h)) == [2026, 2027, 2028]
    gl = j(client.get(f"{API}/lookups/gl-accounts", params={"q": "sales"}, headers=h))
    assert {g["gl_code"] for g in gl} == {"4000", "4010", "4100", "4200"}
    found = j(client.get(f"{API}/budgets", params={"q": "2027"}, headers=h))
    assert found["total"] == 1 and found["items"][0]["status"] == "APPROVED"
    assert client.get(f"{API}/reports/R99", headers=h).status_code == 404
    assert client.get("/health").json()["status"] == "ok"
