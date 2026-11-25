# Test results (executed 25 Nov 2026, Windows 11, Python 3.12, Flutter 3.50.1 / Dart 3.14.0)

Only tests that were actually run are marked passed. Nothing on Oracle was executed.

## Summary

| Suite | Command | Result |
|---|---|---|
| Backend API + engine (SQLite demo tenant) | `pytest -v` | **21 passed, 0 failed** |
| Flutter static analysis | `flutter analyze` | **No issues found** |
| Flutter formatting | `dart format` | clean |
| Flutter unit + widget | `flutter test` | **8 passed, 0 failed** |
| Browser end-to-end (Playwright, Chromium, release web build + live backend) | `python tests_e2e/browser_smoke.py` | **12/12 checks passed**, no uncaught page errors |
| Oracle SQL syntax (sqlglot, Oracle dialect) | all files in `database/oracle` + common views | **1,555 statements parsed, 0 failures**; 33 trigger/grant/comment/role statements not parseable by the tool (not checked) |
| Web release build | `flutter build web --release` | **Built** (`frontend/build/web`) |
| Windows release build | `flutter build windows --release` | **Not built**: "Unable to find suitable Visual Studio toolchain" |
| Flutter integration test | `flutter test integration_test` | **Not run** (needs Windows toolchain or chromedriver) |
| Oracle install / demo / validation / rollback | `install_demo.sql` | **Not run** (no Oracle database available) |

## Backend tests (what each proves)
| Test | Covers |
|---|---|
| test_login_and_tenant_isolation | bad password, unknown tenant, missing / forged token, branch list of a branch manager |
| test_january_demo_figures_reconcile_everywhere | R01 per branch 200,000/185,000, 150,000/165,000, 100,000/90,000; totals 450,000/440,000, 97.78%; dashboard = R02 = R04 = R06 |
| test_engine_matches_oracle_variance_view | every GL total of the Python engine equals `V_BUDGET_VARIANCE` for 2027 |
| test_unbudgeted_actuals_and_exclusions | GL 6400 unbudgeted actual 1,500 (variance % N/A); internal-transfer and credit-settlement vouchers excluded; drill-down lines sum to the GL actual |
| test_pending_and_rejected_revisions_do_not_affect_reporting | pending 22,000 and rejected +500 ignored; approved 7,765 applied |
| test_daily_reports_and_provisional_flag | MTD at month end, remaining target, required daily average N/A on the last day, consolidated = sum of branches, provisional on 15 Feb (draft voucher) only |
| test_zero_budget_year_returns_na | zero budget gives N/A achievement |
| test_full_budget_lifecycle | create, duplicate year blocked, duplicate / inactive / VAT account rejected, empty submit blocked, entry save and P&L, optimistic-lock 409, line removal persisted after re-login, permission 403, submit, edit blocked, reject without reason 422, reject, resubmit, approve (v1, originals frozen), approval-history order, revisions with idempotent replay, one-pending rule, new line from zero (N/A %), batch approval to v2, original unchanged, double approval 409, reject revision, version filter |
| test_segregation_of_duties | same user cannot approve own submission; admin can switch SoD off |
| test_stale_revision_is_rejected | changed line auto-rejects the revision, version unchanged |
| test_audit_tables_are_immutable | UPDATE/DELETE on approval and revision history and ORIGINAL_AMOUNT change all refused by triggers |
| test_branch_permissions | branch manager blocked from other branches, budget creation and entry; admin permission change takes effect; ADMIN lock-out prevented |
| test_report_sorting_paging_and_lookups | server sort + paging, lookups, search, unknown report 404, health |
| test_calc (8) | variance signs, N/A denominators, exact daily rounding for awkward amounts, MTD = sum of days, leap-year February (29 days), WORKING_DAYS, out-of-range, month-end target, P&L formulas |

## Flutter tests
* unit: exact money formatting, amount input validation, live P&L summary, Excel (zip signature) and PDF (`%PDF-`) generation.
* widget: login validation, wrong password message, successful login opens dashboard with KPIs and provisional banner,
  role-based menu; Arabic switches to RTL; approval reject requires remarks and sends them; new budget defaults to company currency.

## Browser E2E checks (release web build served by the backend)
dashboard KPIs; R01 450,000 and 440,000; daily performance 185,000; daily P&L; budget created through the UI;
history dialog shows CREATE; entry grid lines and summary; revision list shows the pending lease revision; Arabic UI;
no uncaught JavaScript errors. Screenshots: `docs/screenshots/`.

## Defects found by testing and fixed
1. New budget form left Currency empty, so Save failed validation (found by browser E2E). Fixed: defaults to company currency; regression widget test added.
2. Side navigation ListTiles painted on a ColoredBox (ink invisible; Flutter assertion). Fixed with a Material ancestor.
3. Arabic locale missing Cupertino localisation delegate (assertion on switch). Fixed with `GlobalMaterialLocalizations.delegates`.
4. Long dropdown labels overflowed at narrow widths. Fixed with `isExpanded`.
5. Monthly trend chart plotted future months as zero actuals. Fixed: actuals plotted only where postings exist.
