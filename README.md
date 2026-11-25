# Ceevora ERP: Budget Management Module

Flutter/Dart client (Windows desktop and Web) + Python FastAPI backend + Oracle 19c / 26ai database scripts.
Built from *Ceevora Flutter Budget AI Development Prompt v1.0* (25 Nov 2026).

> **Status: working demo, not production-ready.** Everything below runs end to end in the standalone demo
> (SQLite tenant). The Oracle scripts are syntax-checked but have **not** been executed against an Oracle
> database, and the production table mappings were not supplied. See `docs/GAPS_AND_UNVERIFIED.md`.

## Live demo (works on phones)

**https://notyousha.github.io/ceevora-budget/**

Company code `DEMO`, password `Demo@2027`, users `accountant`, `fmanager`, `admin`, `bm.riyadh`.
The first visit takes 20 to 40 seconds: this static demo runs the real Python backend *inside your browser*
(Pyodide, a WebAssembly build of Python) with the demo data in SQLite, and saves your changes in your browser only
(IndexedDB). "Reset demo data" on the sign-in page restores the original data. Production uses the FastAPI server
and Oracle as described below; the in-browser mode exists only so the demo can be shared without a server.
Rebuild it with `python deployment/build_pages.py` and publish `frontend/build/web` to the `gh-pages` branch.

## Windows download (no installation)

Download `CeevoraBudget.exe` from the [latest release](https://github.com/NotYousha/ceevora-budget/releases/latest)
and double-click it. A console window starts the demo server and your browser opens the app; keep the window open
while you use it. Data is saved in `%LOCALAPPDATA%\CeevoraBudget`; `CeevoraBudget.exe --reset` restores the demo data.
The file is not code-signed, so Windows SmartScreen asks first: choose **More info**, then **Run anyway**.
Rebuild it with `python deployment/windows_exe/build_exe.py <python-with-pyinstaller>`.

## Quick start on your own machine (Windows, about 5 minutes)

Prerequisite: Python 3.12 on PATH. The ZIP package includes the compiled web build (`frontend/build/web`);
from a git clone, build it first with `flutter build web --release` in `frontend`.

```powershell
cd deployment
.\run_demo.ps1          # creates the venv, seeds Demo Donuts 2027, starts http://127.0.0.1:8000
```

Open <http://127.0.0.1:8000>, company code `DEMO`, password `Demo@2027` for every user:

| User | Role | Can |
|---|---|---|
| `accountant` | Accountant | create budgets, enter lines, submit, request revisions |
| `fmanager` | Finance Manager | approve / reject budgets and revisions |
| `admin` | Administrator | everything + permission matrix and segregation-of-duties switch |
| `bm.riyadh` | Branch Manager | dashboard and reports for Riyadh only |

API documentation (OpenAPI/Swagger): <http://127.0.0.1:8000/docs>, static copy in `docs/openapi.json`.

## Layout

```
frontend/            Flutter app (lib/core, lib/features/*, lib/shared, test, integration_test, web, windows)
backend/             FastAPI service (app/*.py), tests/, tenants.json, requirements*.txt
database/oracle/     install/, demo/, validation/, upgrade/, rollback/, install_production.sql, install_demo.sql
database/common/     reporting views shared by Oracle and the SQLite demo
database/sqlite/     standalone demo schema (mirrors Oracle)
deployment/          run_demo.ps1, nginx and systemd templates
docs/                architecture, mapping, API, user manual, deployment, traceability, test results, gaps
```

## Tests

```powershell
cd backend;  .venv\Scripts\python -m pytest -q            # 22 API + engine tests
cd frontend; flutter analyze; flutter test                # 9 unit + widget tests (incl. phone size)
```

Results recorded on 25 Nov 2026 are in `docs/TEST_RESULTS.md`.
