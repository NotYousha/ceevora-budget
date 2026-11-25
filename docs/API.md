# API (v1)

Full typed contract: `docs/openapi.json` (OpenAPI 3.1) or live at `/docs`. Base path `/api/v1`.

**Auth:** `POST /auth/login {tenant, username, password}` returns `{token, expires_at, user, company}`. Send
`Authorization: Bearer <token>`. Expiry: 401 `TOKEN_EXPIRED`; the client signs out and returns to the login screen.

**Errors:** always `{"error": {"code": "...", "message": "..."}}`. Codes include `VALIDATION_ERROR` (422),
`FORBIDDEN` / `BRANCH_FORBIDDEN` (403), `NOT_FOUND` (404), `STALE_DATA`, `DUPLICATE_BUDGET`, `INVALID_STATE`,
`NOT_EDITABLE`, `PENDING_EXISTS`, `ALREADY_DECIDED`, `SEGREGATION_OF_DUTIES`, `CONFLICT` (409), `SERVER_ERROR` (500).

**Money:** decimals are sent and returned as **strings** ("185000.00") to avoid floating point. Percentages are
strings or `null` (= N/A).

**Concurrency:** writes carry the `row_version` the client last read; a mismatch returns 409 `STALE_DATA`.
**Idempotency:** POST writes accept `Idempotency-Key` (8 to 100 chars); a repeat returns the stored response with
header `Idempotent-Replay: true`.

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | /auth/me | any | user, permissions, branch_ids |
| GET | /lookups/branches, /years, /periods?year=, /gl-accounts?q=&category= | any | gl-accounts = active posting budget accounts |
| GET | /budgets?q=&year=&status=&page=&page_size= | BUDGET_VIEW | paginated |
| POST | /budgets | BUDGET_CREATE | one operating budget per company and year |
| GET / PUT | /budgets/{id} | VIEW / CREATE | PUT only while DRAFT |
| GET / PUT | /budgets/{id}/entry?branch_id= | VIEW / CREATE | PUT replaces the branch grid (DRAFT only) |
| GET | /budgets/{id}/summary | BUDGET_VIEW | branch + company P&L of current amounts |
| POST | /budgets/{id}/submit, /approve, /reject | SUBMIT / APPROVE | reject needs `reason` |
| GET | /budgets/{id}/approval-history?version= | BUDGET_VIEW | Screen 01A |
| GET | /budgets/{id}/revision-history?version=&status= | BUDGET_VIEW | Screen 01B |
| GET | /budgets/{id}/revision-line?branch_id=&gl_account_id=&period_no= | BUDGET_VIEW | original / current / pending |
| POST | /budgets/{id}/revisions | REVISION_REQUEST | creates PENDING |
| POST | /revisions/approve, /revisions/reject | REVISION_APPROVE | batch; stale lines auto-rejected |
| GET | /dashboard?year=&period_no=&date_from=&date_to=&branch_id=&category=&gl_account_id= | DASHBOARD_VIEW | KPIs + chart series |
| GET | /drilldown/gl, /drilldown/transactions | DRILLDOWN_VIEW | branch-checked, paginated |
| GET | /daily/performance?date=&branch_id= | REPORT_VIEW | Screen 06 |
| GET | /daily/pl?date=&branch_id=&basis=DAY\|MTD | REPORT_VIEW | Screen 07 |
| GET | /reports/{R01..R06}?period_type=DAILY\|MTD\|MONTHLY\|YTD\|YEARLY\|CUSTOM&... | REPORT_VIEW | sort, desc, page, page_size |
| GET / PUT | /admin/permissions, PUT /admin/settings | ADMIN_CONFIG | role matrix, SoD switch |
| GET | /health | none | per-tenant DB check (restrict at the proxy) |

Exports (Excel / PDF / print) are generated in the Flutter client from these report endpoints.
