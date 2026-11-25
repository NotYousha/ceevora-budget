# Missing production integration requirements and unverified steps

This module must **not** be labelled production-ready until every item below is closed.

## Inputs that were not supplied
1. `Ceevora_Budget_Screens_and_Report_Formats_v1.2.docx`, `Ceevora_Budget_Module_Developer_Design_v1.3.docx` and
   the Chart of Accounts. Screens, report columns and DDL were derived from the prompt text alone; compare the UI
   and column lists with v1.2 and the tables with the v1.3 DDL, and record differences.
2. Existing Ceevora Flutter/backend source, coding standards and API contracts. A separate demo backend
   (Python FastAPI) was built instead; if Ceevora has its own backend, port `services.py`, `calc.py`,
   `analytics.py` and `reports.py` or call this service behind it.
3. Production table names, key types and COA classification for Company, Branch, COA, GL Ledger, Financial
   Year/Period, JV Header/Details and User/Role (see MAPPING_GUIDE.md).
4. The tenant / PDB registry format and the identity provider used for sign-in.

## Built but not executed here
| Item | Why | How to verify |
|---|---|---|
| Oracle install, demo, validation, rollback scripts | No Oracle database or Docker on the build machine | Run `install_demo.sql` on a test PDB; validation queries print expected values |
| Oracle code path of the backend (pools, `RETURNING INTO`, `FOR UPDATE`, CLOB reads) | Same | Add an `oracle` tenant and run `pytest` against it (the tests currently use SQLite) |
| Oracle triggers and role grants | Not parseable by the offline SQL checker | Install and run the immutability checks manually (UPDATE on BUDGET_APPROVAL_HISTORY must raise ORA-20901) |
| Windows desktop release (`flutter build windows`) | Visual Studio C++ workload not installed ("Unable to find suitable Visual Studio toolchain") | Build on a machine with VS 2022 Desktop C++ |
| `integration_test/app_test.dart` | Needs a Windows toolchain or chromedriver | `flutter test integration_test -d windows` with the backend running |
| Excel / PDF files opened in Excel / a PDF reader | Only file signatures were tested | Export each report and open it |
| Arabic text inside exported PDFs | Uses Noto Naskh Arabic downloaded from Google Fonts at runtime; offline falls back to a Latin-only font | Bundle the font as an asset for offline sites |
| OCI / Nginx / systemd / TLS / backups / upgrade runbook | No server | Run in staging |
| Budget Entry grid driven in a browser | Browser E2E covered login, dashboard, reports, daily screens, master create, history and Arabic; the grid itself was verified through API tests and code review only | Manual UAT of add/remove/copy/save in the grid |

## Known functional limits (by design or deferred)
* No login rate limiting or account lockout; add at Nginx (`limit_req`) or in the identity provider.
* Tokens live in memory only: closing the browser tab or desktop app signs the user out (by design; data is saved server-side).
* One operating budget per company and year; budget versions apply to the whole budget (not per branch).
* Revisions edit one line (branch, GL, period) each; approving several in one action creates one new version.
* `WORKING_DAYS` treats Friday as the only non-working day.
* Arabic UI uses Western digits; number grouping is fixed to `1,234.56`.
* Exports are produced in the client from report endpoints (no server-side export endpoint).
* OpenAPI documents request bodies precisely; response bodies are documented as generic JSON.
* The demo user table stores PBKDF2 hashes; production should use the existing Ceevora identity source.

## Public demo (GitHub Pages)
* The shared link runs the backend in the visitor's browser (Pyodide + SQLite). It is a demo transport only:
  no Oracle, no shared data between visitors, data kept in that browser's IndexedDB. The demo users are re-hashed
  with 1,000 PBKDF2 rounds in the browser copy (the published password is public anyway); the server build keeps 210,000.
* It needs cdn.jsdelivr.net (Pyodide) and pypi.org (pure-Python wheels) on first load.
