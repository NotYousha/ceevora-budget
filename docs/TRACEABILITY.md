# Requirements traceability and phase checklist

Source: *Ceevora Flutter Budget AI Development Prompt v1.0*. Status key: **Tested** (automated test or browser
check executed and passing), **Done** (implemented, not separately tested), **Partial**, **Blocked** (cannot be done
in this workspace). The companion documents named in the prompt (Screens and Report Formats v1.2, Developer
Design v1.3, Chart of Accounts) were **not provided**, so screen layouts and DDL follow the prompt text only.

| § | Requirement | Where | Status |
|---|---|---|---|
| 1 | Working module with persistent storage, traceability, conflicts documented | whole repo; this file; GAPS doc | Tested (demo store) |
| 2 | Flutter/Dart for Windows + Web; no direct Oracle access; REST over HTTPS; modular layers | `frontend/lib/{core,features,shared}`, `backend/` | Done. Web build Tested; Windows build **Blocked** (no Visual Studio) |
| 2 | Packages: Riverpod, Dio, go_router, fl_chart, intl, decimal, pdf/printing, Excel; pinned | `pubspec.yaml` / `pubspec.lock` | Done. **Deviation:** pluto_grid replaced by Flutter's `two_dimensional_scrollables` (pinned columns, maintained by the Flutter team) |
| 2 | Standalone demo and integrated production configurations | `tenants.json` (sqlite / oracle dialects) | Demo Tested; Oracle path **not executed** |
| 3 | Navy nav, white content, teal actions, lookups, date controls, status chips, confirm dialogs, loading/error/empty states | `core/theme`, `core/widgets` | Tested (browser screenshots) |
| 3 | English + Arabic with RTL, localised dates; SAR default, company currency in production | `core/localization`, `Company.currency` | Tested (widget + browser) |
| 3 | Keyboard navigation, horizontal scrolling | Tab order in grids, scroll views | Done (manual keyboard test not performed) |
| 4 | Screen 01 fields and actions; mandatory validation; no duplicate annual budget; no edits after approval | `budget_master_page.dart`, `services.create_budget/update_budget`, `BM_ANNUAL_UK` | Tested |
| 5 | Screens 01A/01B read-only history, version filter, Close, Excel; immutable audit | `history_dialog.dart`, triggers `BAH_/BRH_IMMUTABLE` | Tested (API + browser + trigger test) |
| 6 | Screen 02 grid: GL rows x months, annual total, P&L calc, add/remove, copy prev/all, save/submit/search/cancel, eligible accounts only, no duplicate rows, fixed columns | `budget_entry_page.dart`, `services.save_entry`, `BD_LINE_UK` | API Tested; grid UI built, not browser-tested |
| 7 | Approval: summaries, view details, approve, reject with remarks, DRAFT->SUBMITTED->APPROVED, reject->DRAFT, v1 + originals | `approval_page.dart`, `services.approve/reject` | Tested |
| 7 | Revision: PENDING->APPROVED/REJECTED, only approved change amounts, version increment, originals preserved, locking, optimistic concurrency, idempotency, atomic audit, stale rejection | `revision_page.dart`, `services.*revision*` | Tested |
| 8 | Dashboard filters, KPIs, 5 charts, refresh on filter change, drill to GL and posted JVs with permission checks | `dashboard_page.dart`, `drilldown_dialog.dart`, `analytics.dashboard/drill_*` | Tested (API + browser) |
| 9 | Daily Performance and Daily P&L, branch + consolidated, drill-down, provisional flag | `daily_performance_page.dart`, `daily_pl_page.dart`, `analytics.daily_*` | Tested |
| 10 | R01 to R06, common framework, DAILY/MTD/MONTHLY/YTD/YEARLY/CUSTOM, sort, paging, refresh, preview, print, Excel, PDF, header block, reconciliation | `reports.py`, `reports_page.dart`, `core/utils/export.dart` | Tested (reconciliation); Excel/PDF bytes Tested; files not opened in Excel/Acrobat |
| 11 | Four budget tables, keys, constraints, indexes, defaults, comments, grants, demo, validation, upgrade, rollback | `database/oracle/**` | Syntax-checked (1,555 statements, 0 failures); **not executed on Oracle** |
| 11 | V_BUDGET_APPROVED / ACTUAL / VARIANCE, unbudgeted actuals, no join duplication | `database/common/03_reporting_views.sql` | Tested on SQLite (same SQL text) |
| 11 | Reuse Company/Branch/COA/GL/Period/JV/User tables; isolate demo masters; adapters | `BX_*` adapter views over `DM_*` | Done; production mapping **Blocked** (names not supplied) |
| 12 | Tenant per PDB, resolved server-side; company/branch checks everywhere | `db.py`, `services.check_branch`, `analytics.branch_scope` | Tested (single tenant + branch isolation) |
| 12 | Posted JVs only; exclude VAT, credit settlement, internal transfers; contra-revenue; COA signs; no JVs or GL created | `V_BUDGET_ACTUAL`, `calc.py` | Tested |
| 13 | Decimal engine and every formula incl. daily rounding, MTD, month end, N/A | `calc.py` | Tested (8 unit tests + API tests) |
| 14 | Providers for each area, loading/error/empty, refresh after writes, no duplicate clicks | `shared/providers`, `BusyButton`, `ref.invalidate` | Tested (widget) |
| 14 | REST endpoints, typed models, OpenAPI, pagination, standard errors, token expiry, env base URLs | `main.py`, `docs/openapi.json`, `Env` | Done. **Partial:** request models fully typed; responses typed in Dart models but documented generically in OpenAPI |
| 15 | Four roles, server-side permissions, configurable SoD, admin configuration | `security.py`, `admin_page.dart` | Tested |
| 15 | HTTPS, token handling, bind variables, pooling, CORS, validation, least privilege, audit, secrets out of client/source | nginx template, `db.py`, `04_grants.sql`, `.env.example` | Done; HTTPS/OCI **not deployed**. **Gap:** no login rate limiting / lockout |
| 16 | Demo Donuts 2027 SAR with the exact January figures; separate demo seed | `seed.py`, `demo/20_demo_data.sql` | Tested (450,000 / 440,000 reconcile on every screen) |
| 17 | Project structure | repo tree | Done |
| 18 | Test list incl. leap years, zero budgets, rounding, concurrency, permissions, exports | `backend/tests`, `frontend/test` | Tested except DB installation on Oracle and `integration_test` (written, **not run**: needs Windows toolchain or chromedriver). A browser E2E (Playwright, 9 checks) was run instead |
| 19 | Windows setup, OCI/Nginx/systemd/logs/health/backups/upgrades/rollback, releases | `docs/DEPLOYMENT_*.md`, `deployment/` | Docs Done; web release Built; production **not executed** |
| 20 | Source, SQL, demo, screens, exports, API docs, architecture/mapping, tests/results, manual, guides, ZIP, builds | ZIP package | Done except Windows build |

## Phase checklist (prompt §21)

| Phase | State |
|---|---|
| Requirements traceability | Completed |
| Architecture | Completed |
| Oracle scripts | Completed, syntax-tested; execution on Oracle **pending** (no database available) |
| Backend | Completed, tested (21 tests) |
| Flutter screens | Completed, analyzed (0 issues), tested (8 tests + browser E2E) |
| Reports | Completed, tested |
| Integration | Completed against SQLite demo tenant; Oracle tenant **blocked** |
| Testing | Completed for everything runnable here; see TEST_RESULTS.md |
| Deployment | Web build completed; Windows build **blocked**; production deployment **pending** |
| Packaging | Completed (ZIP) |
