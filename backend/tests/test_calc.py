import datetime as dt
from decimal import Decimal as D

from app.calc import allocate, day_weights, pct, pl_totals, remaining_target, revision_pct, variance


def test_variance_signs():
    assert variance("SALES", 100, 120) == D("20.00")      # revenue: actual - budget
    assert variance("OPEX", 100, 120) == D("-20.00")      # expense: budget - actual
    assert variance("DISCOUNT", 100, 80) == D("20.00")


def test_zero_denominators_are_na():
    assert pct(5, 0) is None
    assert revision_pct(100, 0) is None
    assert pct(185000, 200000) == D("92.50")
    assert revision_pct(7765, 6765) == D("14.78")


def test_daily_allocation_reconciles_exactly():
    for amount in (D("200000.00"), D("100.00"), D("0.01"), D("12345.67"), D("0")):
        s, e = dt.date(2027, 1, 1), dt.date(2027, 1, 31)
        days = [allocate(amount, s, e, "CALENDAR_DAYS", s + dt.timedelta(i), s + dt.timedelta(i)) for i in range(31)]
        assert sum(days) == amount
        assert max(days) - min(days) <= D("0.01")
        # MTD = sum of daily allocations
        assert allocate(amount, s, e, "CALENDAR_DAYS", s, dt.date(2027, 1, 10)) == sum(days[:10])


def test_leap_year_february():
    s, e = dt.date(2028, 2, 1), dt.date(2028, 2, 29)
    assert len(day_weights(s, e, "CALENDAR_DAYS")) == 29
    assert sum(allocate(D("2900"), s, e, "CALENDAR_DAYS", s + dt.timedelta(i), s + dt.timedelta(i)) for i in range(29)) == D("2900.00")
    assert allocate(D("2900"), s, e, "CALENDAR_DAYS", dt.date(2028, 2, 29), dt.date(2028, 2, 29)) == D("100.00")


def test_working_days_gives_fridays_zero():
    s, e = dt.date(2027, 1, 1), dt.date(2027, 1, 31)  # 1 Jan 2027 is a Friday
    assert allocate(D("1000"), s, e, "WORKING_DAYS", s, s) == D("0.00")
    assert allocate(D("1000"), s, e, "WORKING_DAYS", s, e) == D("1000.00")


def test_range_outside_period_is_zero():
    assert allocate(D("1000"), dt.date(2027, 1, 1), dt.date(2027, 1, 31), "CALENDAR_DAYS",
                    dt.date(2027, 2, 1), dt.date(2027, 2, 5)) == D("0.00")


def test_remaining_target_month_end():
    end = dt.date(2027, 1, 31)
    r = remaining_target(D("200000"), D("150000"), dt.date(2027, 1, 21), end)
    assert r["remaining_target"] == D("50000.00") and r["days_remaining"] == 10 and r["required_avg_daily"] == D("5000.00")
    r = remaining_target(D("200000"), D("150000"), end, end)
    assert r["required_avg_daily"] is None and r["days_remaining"] == 0     # unmet at month end: N/A
    r = remaining_target(D("200000"), D("210000"), dt.date(2027, 1, 20), end)
    assert r["remaining_target"] == D("0.00") and r["required_avg_daily"] == D("0.00")


def test_pl_formulas():
    t = pl_totals({"SALES": (205000, 189625), "DISCOUNT": (4000, 3700), "RETURN": (1000, 925),
                   "COGS": (70000, 66600), "OPEX": (80000, 81000)})
    assert t["NET_SALES"] == (D("200000.00"), D("185000.00"))
    assert t["GROSS_PROFIT"] == (D("130000.00"), D("118400.00"))
    assert t["OPERATING_PROFIT"] == (D("50000.00"), D("37400.00"))


def test_pure_python_pbkdf2_matches_hashlib(monkeypatch):
    import hashlib

    from app import security

    want = hashlib.pbkdf2_hmac("sha256", b"Demo@2027", b"salt1234", 500)
    monkeypatch.delattr(hashlib, "pbkdf2_hmac")
    assert security._pbkdf2(b"Demo@2027", b"salt1234", 500) == want
