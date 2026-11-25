"""Build the GitHub Pages demo: Flutter web + the real backend running in the browser (Pyodide).

    python deployment/build_pages.py [--base-href /ceevora-budget/]

Output: frontend/build/web (publish it to the gh-pages branch). Needs flutter on PATH and backend/.venv.
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FRONT, BACK = ROOT / "frontend", ROOT / "backend"

ap = argparse.ArgumentParser()
ap.add_argument("--base-href", default="/ceevora-budget/")
args = ap.parse_args()

flutter = shutil.which("flutter") or shutil.which("flutter.bat")
if not flutter:
    sys.exit("flutter not found on PATH")
subprocess.run([flutter, "build", "web", "--release", "--no-wasm-dry-run", f"--base-href={args.base_href}",
                "--dart-define=IN_BROWSER_BACKEND=true"], cwd=FRONT, check=True)

out = FRONT / "build" / "web" / "backend"
(out / "app").mkdir(parents=True, exist_ok=True)
files = sorted(p.name for p in (BACK / "app").glob("*.py"))
for name in files:
    shutil.copy2(BACK / "app" / name, out / "app" / name)
(out / "manifest.json").write_text(json.dumps({"app": files}))
py = BACK / ".venv" / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
subprocess.run([str(py), "-m", "app.seed", "sqlite", str(out / "demo.db")], cwd=BACK, check=True)
(FRONT / "build" / "web" / ".nojekyll").write_text("")
print(f"Pages build ready: {FRONT / 'build' / 'web'}")
