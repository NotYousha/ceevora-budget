# Standalone demo: Python backend (SQLite tenant DEMO) serving the compiled Flutter web app.
# Usage:  .\run_demo.ps1            (first run creates backend\.venv and seeds the demo database)
#         .\run_demo.ps1 -Reseed    (reset demo data to the original Demo Donuts 2027 state)
param([switch]$Reseed, [int]$Port = 8000)
$ErrorActionPreference = 'Stop'
$backend = Join-Path $PSScriptRoot '..\backend' | Resolve-Path
Set-Location $backend

if (-not (Test-Path '.venv\Scripts\python.exe')) {
    Write-Host 'Creating Python virtual environment...'
    python -m venv .venv
    .\.venv\Scripts\python -m pip install --quiet -r requirements.txt
}
if ($Reseed -or -not (Test-Path 'data\demo.db')) {
    Write-Host 'Seeding Demo Donuts 2027...'
    .\.venv\Scripts\python -m app.seed sqlite data\demo.db
}
if (-not $env:JWT_SECRET) {
    # Per-run random secret: fine for a local demo; production must set JWT_SECRET from a secret store.
    $env:JWT_SECRET = [Convert]::ToBase64String((1..48 | ForEach-Object { Get-Random -Maximum 256 }))
}
Write-Host "Open http://127.0.0.1:$Port  (company DEMO, users accountant / fmanager / admin / bm.riyadh, password Demo@2027)"
.\.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port $Port
