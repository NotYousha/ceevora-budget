# Architecture

```
Flutter (Windows / Web)  --HTTPS JSON-->  Nginx  -->  FastAPI (uvicorn)  --python-oracledb pool-->  Oracle PDB per customer
   Riverpod providers                              auth, permissions, tenant         BUDGET_* tables
   Dio + token interceptor                         workflow, calc engine, reports    BX_* adapter views -> ERP tables
   go_router (permission-aware)                                                      V_BUDGET_* reporting views
```

Flutter never connects to Oracle. Credentials live only in the backend environment.

## Backend (`backend/app`)

| Module | Responsibility |
|---|---|
| `main.py` | Routes, request models (Pydantic, validation at the trust boundary), auth, tenant resolution, idempotency, standard errors, optional static hosting of the web build |
| `security.py` | PBKDF2-SHA256 password hashes, HS256 JWT (60 min), role and permission catalogue |
| `db.py` | Tenant registry (`tenants.json`), Oracle connection pools, SQLite demo connections, one transaction per request, bind-variable helpers |
| `services.py` | Budget master, branch entry, submit / approve / reject, revisions, histories. Every state change writes its audit row in the same transaction |
| `calc.py` | Decimal financial engine: variances, percentages (N/A on zero), daily allocation, remaining target, P&L |
| `analytics.py` | Budget vs actual facts shared by dashboard, drill-down and daily reports |
| `reports.py` | R01 to R06 on one framework (range resolution, rows, totals, sort, paging) |
| `seed.py` | Demo Donuts 2027 data, written to SQLite or emitted as the Oracle demo script |

### Tenancy
Login sends a company code. The backend looks it up in its own registry, which names the environment
variables that hold that customer's PDB credentials. The signed token carries the tenant code, so every later
request is routed by the server, never by client-supplied connection details. Company and branch access are
checked in every endpoint (`check_branch`, `branch_scope`).

### Workflow and integrity
* `DRAFT -> SUBMITTED -> APPROVED`; reject returns `SUBMITTED -> DRAFT` with mandatory remarks.
* Initial approval freezes `ORIGINAL_AMOUNT` and sets version 1 (a trigger blocks later changes).
* Revisions: `PENDING -> APPROVED | REJECTED`. Only approval changes `CURRENT_AMOUNT` and increments the
  version (once per approved batch). One pending revision per line.
* Concurrency: `ROW_VERSION` optimistic tokens on master and lines; `SELECT ... FOR UPDATE` row locks on Oracle
  (`BEGIN IMMEDIATE` on SQLite); stale revisions (line changed since request) are rejected automatically.
* Idempotency: write endpoints accept `Idempotency-Key`; the response is stored in the same transaction and replayed.
* Audit: `BUDGET_APPROVAL_HISTORY` is insert-only (trigger + grants). Revision rows can only leave `PENDING` once.
* Segregation of duties (configurable): approver must differ from submitter / requester.

### Calculations (authoritative on the server)
Net sales = gross - discounts - returns; GP = net - COGS; OP = GP - opex. Revenue/profit variance = actual -
budget; cost variance = budget - actual. Achievement = actual / budget x 100, N/A when budget is 0.
Daily budget for day d = round(cum(d)) - round(cum(d-1)), so any range (day, MTD, YTD, custom) sums exactly and
a full period always equals the monthly amount. `WORKING_DAYS` gives Fridays zero weight.

### Actuals
`V_BUDGET_ACTUAL`: posted vouchers only, signed by the account's normal balance, excluding VAT accounts,
internal-transfer accounts and `INTERNAL_TRANSFER` / `CREDIT_SETTLEMENT` vouchers. Discounts and returns are
contra-revenue categories. Classification uses COA attributes (`BUDGET_CATEGORY`, `NORMAL_BALANCE`, flags), not
hard-coded GL codes. `V_BUDGET_VARIANCE` uses `UNION ALL` + `GROUP BY` so unbudgeted actuals appear and nothing is
double counted. Reports flag results **provisional** when unposted (`DRAFT`) vouchers exist in the range.

## Flutter (`frontend/lib`)
* `core/`: config (API base URL per environment via `--dart-define`), theme (navy / white / teal), routing
  (`go_router`, redirects by permission), network (Dio, token header, 401 -> sign-out), security (in-memory
  session), localization (English / Arabic, RTL via `GlobalMaterialLocalizations.delegates`), utils (exact
  Decimal formatting, Excel / PDF export), widgets (busy buttons that block double clicks, dialogs, grids).
* `features/`: authentication, budget_master (01), budget_history (01A/01B), budget_entry (02),
  budget_approval (03), budget_revision (04), dashboard (05 + drill-down), reports (06, 07, R01 to R06), admin.
* `shared/`: typed models, repository (every endpoint), Riverpod providers invalidated after writes.

Flutter 3.50 moved Material to `package:material_ui`; the app imports it directly.
