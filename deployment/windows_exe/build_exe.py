"""Build CeevoraBudget.exe: one-file Windows demo (no Python or installation needed on the target PC).

    python deployment/windows_exe/build_exe.py <python-with-pyinstaller>

Needs: frontend/build/web built with `flutter build web --release` (base href "/"), backend/.venv for seeding,
and a Python that has pyinstaller, fastapi, uvicorn and PyJWT installed. Output: deployment/windows_exe/dist/CeevoraBudget.exe
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BACK, WEB = ROOT / "backend", ROOT / "frontend" / "build" / "web"
py_build = sys.argv[1] if len(sys.argv) > 1 else sys.executable

if 'href="/"' not in (WEB / "index.html").read_text(encoding="utf-8") or (WEB / "backend").exists():
    sys.exit("frontend/build/web is the GitHub Pages build; run `flutter build web --release` first")

stage = HERE / "build" / "bundle"
shutil.rmtree(stage, ignore_errors=True)
stage.mkdir(parents=True)
venv_py = BACK / ".venv" / "Scripts" / "python.exe"
subprocess.run([str(venv_py), "-m", "app.seed", "sqlite", str(stage / "demo.db")], cwd=BACK, check=True)
(stage / "tenants.json").write_text(json.dumps({"DEMO": {"dialect": "sqlite", "path": "demo.db", "path_env": "DEMO_DB_PATH"}}))

sep = ";"
subprocess.run([py_build, "-m", "PyInstaller", "--noconfirm", "--onefile", "--name", "CeevoraBudget",
                "--paths", str(BACK), "--collect-submodules", "uvicorn", "--hidden-import", "app.main",
                "--exclude-module", "oracledb",
                "--add-data", f"{stage / 'demo.db'}{sep}.", "--add-data", f"{stage / 'tenants.json'}{sep}.",
                "--add-data", f"{WEB}{sep}web",
                "--distpath", str(HERE / "dist"), "--workpath", str(HERE / "build" / "work"), "--specpath", str(HERE / "build"),
                str(HERE / "launcher.py")], check=True)
print("Built", HERE / "dist" / "CeevoraBudget.exe")
