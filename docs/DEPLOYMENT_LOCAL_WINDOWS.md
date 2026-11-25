# Local setup on Windows 10/11

## A. Run the demo (no Flutter or Oracle needed)
1. Install Python 3.12 (python.org, tick "Add to PATH").
2. Unzip the package, open PowerShell in `deployment`, run `.\run_demo.ps1` (use `-Reseed` to reset data).
   If scripts are blocked: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
3. Browse to <http://127.0.0.1:8000> and sign in (company `DEMO`, password `Demo@2027`).

## B. Develop the Flutter app
1. Flutter SDK 3.50.x stable: `git clone https://github.com/flutter/flutter.git -b stable`, add `flutter\bin` to PATH.
2. For the Windows desktop target: Visual Studio 2022 with the **Desktop development with C++** workload.
3. `cd frontend`, `flutter doctor -v`, `flutter pub get`.
4. Start the backend (A.2), then:
   * Web: `flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1`
   * Windows: `flutter run -d windows` (defaults to `http://localhost:8000/api/v1`)
5. Release builds: `flutter build web --release` (output `build\web`) and `flutter build windows --release`
   (output `build\windows\x64\runner\Release\`; ship the **whole** folder including DLLs and `data\`).
   For a desktop build pointing at a server, add `--dart-define=API_BASE_URL=https://budget.example.com/api/v1`.

## C. Oracle test schema (instead of the SQLite demo)
1. Create a test user in a test PDB (DBA): `CREATE USER BUDGET_DEMO IDENTIFIED BY ...; GRANT CREATE SESSION,
   CREATE TABLE, CREATE VIEW, CREATE TRIGGER, CREATE ROLE TO BUDGET_DEMO; ALTER USER BUDGET_DEMO QUOTA 200M ON USERS;`
2. `set NLS_LANG=.AL32UTF8`, `cd database\oracle`, `sqlplus BUDGET_DEMO@//host:1521/TESTPDB @install_demo.sql`.
   Check the validation output against the expected values printed with each query.
3. Add a tenant to `backend\tenants.json`, e.g.
   `"ORA": {"dialect": "oracle", "user_env": "ORA_DB_USER", "password_env": "ORA_DB_PASSWORD", "dsn_env": "ORA_DB_DSN"}`,
   set those environment variables, start uvicorn and sign in with company code `ORA`.
   python-oracledb thin mode needs no Oracle Client install.

## Tests
* Backend: `cd backend`, `.venv\Scripts\python -m pip install -r requirements-dev.txt`, `.venv\Scripts\python -m pytest -q`
* Flutter: `flutter analyze`, `flutter test`
* Integration (needs running backend + Windows toolchain): `flutter test integration_test -d windows`
