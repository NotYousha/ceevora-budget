"""Double-click Windows launcher for the standalone demo (built into CeevoraBudget.exe by build_exe.py).

Copies the seeded demo database to %LOCALAPPDATA%\\CeevoraBudget on first run, starts the
backend on a free local port and opens the browser. Closing the console window stops it.
"""
import os
import secrets
import shutil
import socket
import sys
import threading
import webbrowser
from pathlib import Path

BUNDLE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent / "bundle"))
DATA = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "CeevoraBudget"


def free_port(preferred=8000):
    for port in (preferred, 0):
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", port))
                return s.getsockname()[1]
            except OSError:
                continue


def main():
    DATA.mkdir(parents=True, exist_ok=True)
    db = DATA / "demo.db"
    if "--reset" in sys.argv or not db.exists():
        shutil.copy2(BUNDLE / "demo.db", db)
    os.environ.update(CEEVORA_TENANTS_FILE=str(BUNDLE / "tenants.json"), DEMO_DB_PATH=str(db),
                      WEB_DIR=str(BUNDLE / "web"), JWT_SECRET=secrets.token_hex(32))
    import uvicorn
    from app.main import app

    port = free_port()
    url = f"http://127.0.0.1:{port}/"
    print("Ceevora Budget demo\n")
    print(f"  Open {url} (your browser should open by itself)")
    print("  Company code DEMO, password Demo@2027, users accountant / fmanager / admin / bm.riyadh")
    print(f"  Your data is saved in {db}")
    print("  To restore the original demo data, run: CeevoraBudget.exe --reset\n")
    print("  Keep this window open while you use the app. Close it to stop.\n")
    threading.Timer(1.5, webbrowser.open, [url]).start()
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")


if __name__ == "__main__":
    main()
