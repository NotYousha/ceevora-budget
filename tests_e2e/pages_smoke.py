"""Phone + desktop smoke test of the GitHub Pages demo (backend running in the browser).

    python tests_e2e/pages_smoke.py https://notyousha.github.io/ceevora-budget/ <screenshot_dir>
"""
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

URL, OUT = sys.argv[1], Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
CHROME = os.environ.get("E2E_CHROME")
results = []


def check(name, ok):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name, flush=True)


def has(page, text, timeout=20000):
    try:
        page.get_by_text(text, exact=False).first.wait_for(timeout=timeout)
        return True
    except Exception:
        return False


def start(page):
    page.goto(URL)
    page.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=90000)
    page.locator("flt-semantics-placeholder").evaluate("e => e.click()")
    t = time.time()
    ok = has(page, "Users: accountant", timeout=180000)
    check(f"in-browser backend ready ({time.time() - t:.0f}s)", ok)


def login(page, user):
    page.get_by_role("textbox", name="Username").fill(user)
    page.get_by_role("textbox", name="Password").fill("Demo@2027")
    page.get_by_role("button", name="Sign in").click()


def open_menu(page, item):
    page.get_by_role("button", name="Open navigation menu").click()
    time.sleep(1)
    page.get_by_text(item, exact=True).first.click()
    time.sleep(2.5)


with sync_playwright() as p:
    b = p.chromium.launch(executable_path=CHROME, headless=True)
    errors = []

    phone = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, is_mobile=True, has_touch=True)
    page = phone.new_page()
    page.on("pageerror", lambda e: errors.append(str(e)))
    start(page)
    page.screenshot(path=str(OUT / "phone_login.png"))
    login(page, "fmanager")
    check("phone: dashboard after login", has(page, "Operating Profit", 60000))
    time.sleep(2)
    page.screenshot(path=str(OUT / "phone_dashboard.png"))
    open_menu(page, "Management Reports")
    check("phone: R01 total 440,000", has(page, "440,000.00"))
    page.screenshot(path=str(OUT / "phone_report.png"))
    open_menu(page, "Budget Entry")
    page.get_by_role("button", name="Search").click()
    time.sleep(2)
    page.locator("flt-semantics[role=row]", has_text="BUD-2027-001").click()
    time.sleep(2)
    branch = page.get_by_role("button", name="Branch")
    box = branch.bounding_box()
    branch.click()
    time.sleep(1.5)
    page.mouse.click(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    check("phone: entry grid", has(page, "Sales - Donuts"))
    time.sleep(1)
    page.screenshot(path=str(OUT / "phone_entry.png"))

    # write path + persistence across reload (IndexedDB)
    page.get_by_role("button", name="Sign out").click() if page.get_by_role("button", name="Sign out").count() else None
    page2 = b.new_context(viewport={"width": 1440, "height": 900}).new_page()
    page2.on("pageerror", lambda e: errors.append(str(e)))
    start(page2)
    login(page2, "accountant")
    has(page2, "Operating Profit", 60000)
    page2.get_by_text("Budget Master", exact=True).first.click()
    time.sleep(2)
    page2.get_by_role("textbox", name="Budget No. *").fill("BUD-2028-WEB")
    page2.get_by_role("textbox", name="Budget Name *").fill("Created on GitHub Pages")
    page2.get_by_text("Financial Year *").first.click()
    time.sleep(1)
    page2.get_by_role("menuitem", name="2028").click()
    time.sleep(1)
    page2.get_by_role("button", name="Save").click()
    check("desktop: budget saved", has(page2, "Saved"))
    page2.reload()
    page2.wait_for_selector("flt-semantics-placeholder", state="attached", timeout=90000)
    page2.locator("flt-semantics-placeholder").evaluate("e => e.click()")
    has(page2, "Users: accountant", 180000)
    login(page2, "accountant")
    has(page2, "Operating Profit", 60000)
    page2.get_by_text("Budget Master", exact=True).first.click()
    time.sleep(2)
    page2.get_by_role("button", name="Search").click()
    check("desktop: saved budget survives reload", has(page2, "BUD-2028-WEB"))
    page2.screenshot(path=str(OUT / "desktop_persisted.png"))

    check("no uncaught page errors", not errors)
    for e in errors[:5]:
        print("  pageerror:", e[:300])
    b.close()

print(f"{sum(results)}/{len(results)} checks passed")
sys.exit(0 if all(results) else 1)
