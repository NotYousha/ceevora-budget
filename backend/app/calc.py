"""Authoritative financial calculation engine (Decimal only, no floats)."""
from __future__ import annotations

import datetime as dt
from decimal import ROUND_HALF_UP, Decimal

CENT = Decimal("0.01")
ZERO = Decimal("0.00")
REVENUE_CATEGORIES = {"SALES"}
CONTRA_REVENUE = {"DISCOUNT", "RETURN"}
COST_CATEGORIES = {"DISCOUNT", "RETURN", "COGS", "OPEX"}


def money(x) -> Decimal:
    if x is None:
        return ZERO
    if isinstance(x, float):
        x = repr(x)
    return Decimal(x).quantize(CENT, ROUND_HALF_UP)


def pct(numerator, denominator) -> Decimal | None:
    """numerator / denominator x 100, or None (N/A) when the denominator is zero."""
    den = Decimal(denominator or 0)
    if den == 0:
        return None
    return (Decimal(numerator or 0) / den * 100).quantize(CENT, ROUND_HALF_UP)


def variance(category: str, budget, actual) -> Decimal:
    """Revenue/profit: actual - budget. Expense (incl. contra-revenue): budget - actual. Positive = favourable."""
    budget, actual = money(budget), money(actual)
    return budget - actual if category in COST_CATEGORIES else actual - budget


def revision_pct(revised, previous_approved) -> Decimal | None:
    return pct(money(revised) - money(previous_approved), previous_approved)


# ---------- daily allocation ----------

def day_weights(start: dt.date, end: dt.date, method: str) -> list[int]:
    """One weight per day in [start, end]. WORKING_DAYS gives Friday zero weight (KSA weekly holiday)."""
    days = (end - start).days + 1
    w = [1] * days
    if method == "WORKING_DAYS":
        w = [0 if (start + dt.timedelta(i)).weekday() == 4 else 1 for i in range(days)]
        if not any(w):
            w = [1] * days
    return w


def cumulative(amount, weights: list[int], upto: int) -> Decimal:
    """Rounded cumulative allocation of `amount` through day index `upto` (1-based; 0 => 0)."""
    if upto <= 0:
        return ZERO
    upto = min(upto, len(weights))
    total = sum(weights)
    return money(Decimal(money(amount)) * sum(weights[:upto]) / total)


def allocate(amount, period_start: dt.date, period_end: dt.date, method: str,
             from_date: dt.date, to_date: dt.date) -> Decimal:
    """Budget share of one period amount falling inside [from_date, to_date].

    Daily allocation for day d = cum(d) - cum(d-1); summing days telescopes to cum(to) - cum(from-1),
    so MTD/ranges are exact and a whole period always reconciles to the monthly amount.
    """
    lo, hi = max(from_date, period_start), min(to_date, period_end)
    if lo > hi:
        return ZERO
    w = day_weights(period_start, period_end, method)
    return cumulative(amount, w, (hi - period_start).days + 1) - cumulative(amount, w, (lo - period_start).days)


def remaining_target(monthly_budget, mtd_actual, business_date: dt.date, period_end: dt.date) -> dict:
    remaining = money(monthly_budget) - money(mtd_actual)
    days_left = (period_end - business_date).days
    if remaining <= 0:
        required = ZERO
    elif days_left <= 0:
        required = None  # month end reached with target unmet: N/A
    else:
        required = money(remaining / days_left)
    return {"remaining_target": max(remaining, ZERO), "days_remaining": max(days_left, 0),
            "required_avg_daily": required}


# ---------- P&L ----------

PL_LINES = [
    # key, source, variance category
    ("GROSS_SALES", "SALES", "SALES"),
    ("DISCOUNTS", "DISCOUNT", "DISCOUNT"),
    ("RETURNS", "RETURN", "RETURN"),
    ("NET_SALES", None, "SALES"),
    ("COGS", "COGS", "COGS"),
    ("GROSS_PROFIT", None, "SALES"),
    ("OPEX", "OPEX", "OPEX"),
    ("OPERATING_PROFIT", None, "SALES"),
]


def pl_totals(by_category: dict[str, tuple]) -> dict[str, tuple[Decimal, Decimal]]:
    """by_category: {category: (budget, actual)} -> {line: (budget, actual)}.

    Net sales = gross - discounts - returns; GP = net - COGS; OP = GP - opex.
    """
    g = {k: (money(v[0]), money(v[1])) for k, v in by_category.items()}
    z = (ZERO, ZERO)
    s, d, r, c, o = (g.get(k, z) for k in ("SALES", "DISCOUNT", "RETURN", "COGS", "OPEX"))
    net = tuple(s[i] - d[i] - r[i] for i in (0, 1))
    gp = tuple(net[i] - c[i] for i in (0, 1))
    op = tuple(gp[i] - o[i] for i in (0, 1))
    return {"GROSS_SALES": s, "DISCOUNTS": d, "RETURNS": r, "NET_SALES": net, "COGS": c,
            "GROSS_PROFIT": gp, "OPEX": o, "OPERATING_PROFIT": op}


def pl_lines(by_category: dict[str, tuple]) -> list[dict]:
    t = pl_totals(by_category)
    net_actual = t["NET_SALES"][1]
    out = []
    for key, _, cat in PL_LINES:
        b, a = t[key]
        v = variance(cat, b, a)
        out.append({"line": key, "budget": b, "actual": a, "variance": v,
                    "achievement_pct": pct(a, b), "pct_of_net_sales": pct(a, net_actual),
                    "favourable": v >= 0})
    return out
