"""Browser E2E smoke (pip install playwright; backend running with a freshly seeded DEMO tenant).
Usage: python tests_e2e/browser_smoke.py <screenshot_dir>

Browser E2E smoke against the running backend + Flutter web build (Flutter semantics tree)."""
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
CHROME = os.environ.get("E2E_CHROME")  # optional path to a Chromium/Chrome binary
BASE = "http://127.0.0.1:8000"
results = []


def check(name, ok):
    results.append((name, ok))
    print(("PASS " if ok else "FAIL ") + name, flush=True)


def shot(page, name):
    time.sleep(1.5)
    page.screenshot(path=str(OUT / f"{name}.png"))


def enable_semantics(page):
    page.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=60000)
    page.locator("flt-semantics-placeholder").evaluate("e => e.click()")
    time.sleep(1)


def login(page, user):
    page.goto(BASE)
    enable_semantics(page)
    page.get_by_role("textbox", name="Username").fill(user)
    page.get_by_role("textbox", name="Password").fill("Demo@2027")
    page.get_by_role("button", name="Sign in").click()
    page.get_by_text(user if user != "fmanager" else "Faisal", exact=False).first.wait_for(timeout=30000)


def nav(page, label):
    page.get_by_text(label, exact=True).first.click()
    time.sleep(2.5)


def has(page, text):
    try:
        page.get_by_text(text, exact=False).first.wait_for(timeout=15000)
        return True
    except Exception:
        return False


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=CHROME, headless=True)
    page = browser.new_page(viewport={"width": 1600, "height": 1000})
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))

    # --- finance manager: dashboard, reports, daily, approval ---
    login(page, "fmanager")
    time.sleep(3)
    check("dashboard shows KPIs", has(page, "Operating Profit"))
    shot(page, "05_dashboard")
    nav(page, "Management Reports")
    check("R01 Jan budget total 450,000", has(page, "450,000.00"))
    check("R01 Jan actual total 440,000", has(page, "440,000.00"))
    shot(page, "R01_sales_report")
    nav(page, "Daily Performance")
    check("daily performance MTD actual 185,000 Riyadh", has(page, "185,000.00"))
    shot(page, "06_daily_performance")
    nav(page, "Daily P&L")
    check("daily P&L renders", has(page, "Operating Profit"))
    shot(page, "07_daily_pl")
    nav(page, "Revision")
    shot(page, "04_revision_empty")
    nav(page, "Budget Master")
    shot(page, "01_master_empty")

    # --- accountant: create a 2028 budget through the UI ---
    page.get_by_role("button", name="Sign out").click()
    time.sleep(2)
    login(page, "accountant")
    nav(page, "Budget Master")
    page.get_by_role("textbox", name="Budget No. *").fill("BUD-2028-UI")
    page.get_by_role("textbox", name="Budget Name *").fill("UI created plan 2028")
    page.get_by_text("Financial Year *").first.click()
    time.sleep(1)
    page.get_by_role("menuitem", name="2028").click()
    time.sleep(1)
    page.get_by_role("button", name="Save").click()
    check("budget created via UI", has(page, "Saved"))
    shot(page, "01_master_created")
    page.get_by_role("button", name="View History").click()
    check("history dialog shows CREATE", has(page, "CREATE"))
    shot(page, "01A_history")
    page.get_by_role("button", name="Close").last.click()
    time.sleep(1)

    # --- budget entry grid for the approved 2027 budget (read-only) ---
    try:
        nav(page, "Budget Entry")
        page.get_by_role("button", name="Search").click()
        time.sleep(2)
        page.locator("flt-semantics[role=row]", has_text="BUD-2027-001").click()
        time.sleep(2)
        branch = page.get_by_role("button", name="Branch")
        box = branch.bounding_box()
        branch.click()
        time.sleep(1.5)
        # The open menu overlays the field with its first item (Riyadh) under the same point.
        page.mouse.click(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
        time.sleep(2)
        check("entry grid shows Sales - Donuts line", has(page, "Sales - Donuts"))
        check("entry grid summary Net Sales", has(page, "Net Sales"))
        shot(page, "02_budget_entry")
    except Exception as e:  # recorded, not fatal
        check(f"entry grid navigation ({type(e).__name__})", False)

    # --- revision screen with pending revision list ---
    try:
        nav(page, "Revision")
        page.get_by_role("button", name="Search").click()
        time.sleep(2)
        page.locator("flt-semantics[role=row]", has_text="BUD-2027-001").click()
        check("revision list shows pending lease revision", has(page, "Lease renewal at higher rent"))
        shot(page, "04_revision")
    except Exception as e:
        check(f"revision navigation ({type(e).__name__})", False)

    # --- Arabic RTL ---
    page.get_by_role("button", name="العربية").click()
    time.sleep(2)
    check("Arabic UI", has(page, "بيانات الموازنة"))
    shot(page, "rtl_arabic_master")

    check("no uncaught page errors", not errors)
    for e in errors[:5]:
        print("  pageerror:", e)
    browser.close()

failed = [n for n, ok in results if not ok]
print(f"{len(results) - len(failed)}/{len(results)} checks passed")
sys.exit(1 if failed else 0)
