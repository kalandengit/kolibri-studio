# =============================================================================
# Kolibri Studio - Windows installer (no Docker, no WSL, no admin rights).
#
# Installs portable copies of Python 3.10, Node 20, PostgreSQL 16, Redis and
# MinIO under -InstallRoot, installs all project dependencies, initializes the
# database, seeds demo data and generates a start-studio.bat launcher.
#
# Run from a full checkout of the project, in a regular PowerShell:
#   powershell -ExecutionPolicy Bypass -File deploy\install-windows.ps1
#
# Options:
#   -InstallRoot <dir>   where tools/data live (default: %USERPROFILE%\kolibri-studio-env)
#   -Port <n>            Django port (default 8080)
#   -NoDemoData          migrate only, skip sample channels
#
# Re-running is safe: finished steps are skipped.
# =============================================================================
[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:USERPROFILE\kolibri-studio-env",
    [int]$Port = 8080,
    [switch]$NoDemoData
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Pinned component versions
$NodeVersion  = "20.20.2"
$PyVersion    = "3.10.11"
$PgVersion    = "16.4-1"
$RedisVersion = "5.0.14.1"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "contentcuration\manage.py"))) {
    throw "Run this script from the project checkout (deploy\install-windows.ps1 next to contentcuration\)."
}

function Log($msg) { Write-Host "[studio-install] $msg" -ForegroundColor Cyan }

$Downloads = Join-Path $InstallRoot "downloads"
$DataDir   = Join-Path $InstallRoot "data"
New-Item -ItemType Directory -Force $Downloads | Out-Null
New-Item -ItemType Directory -Force $DataDir   | Out-Null

function Fetch($url, $dest) {
    if (Test-Path $dest) { Log "already downloaded: $(Split-Path -Leaf $dest)"; return }
    Log "downloading $url"
    & curl.exe -fsSL -o $dest $url
    if ($LASTEXITCODE -ne 0) { throw "download failed: $url" }
}

# --- 1. Download portable components -----------------------------------------
Fetch "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip" "$Downloads\node.zip"
Fetch "https://www.nuget.org/api/v2/package/python/$PyVersion"               "$Downloads\python.nupkg.zip"
Fetch "https://get.enterprisedb.com/postgresql/postgresql-$PgVersion-windows-x64-binaries.zip" "$Downloads\postgres.zip"
Fetch "https://github.com/tporadowski/redis/releases/download/v$RedisVersion/Redis-x64-$RedisVersion.zip" "$Downloads\redis.zip"
Fetch "https://dl.min.io/server/minio/release/windows-amd64/minio.exe"       "$Downloads\minio.exe"

# --- 2. Extract ----------------------------------------------------------------
$NodeDir   = Join-Path $InstallRoot "node"
$PyDir     = Join-Path $InstallRoot "python310"
$PgDir     = Join-Path $InstallRoot "pgsql"
$RedisDir  = Join-Path $InstallRoot "redis"

if (-not (Test-Path "$NodeDir\node.exe")) {
    Log "extracting Node $NodeVersion"
    Expand-Archive "$Downloads\node.zip" $InstallRoot -Force
    if (Test-Path $NodeDir) { Remove-Item -Recurse -Force $NodeDir }
    Rename-Item (Join-Path $InstallRoot "node-v$NodeVersion-win-x64") $NodeDir
}
if (-not (Test-Path "$PyDir\python.exe")) {
    Log "extracting Python $PyVersion"
    Expand-Archive "$Downloads\python.nupkg.zip" "$InstallRoot\python_pkg" -Force
    if (Test-Path $PyDir) { Remove-Item -Recurse -Force $PyDir }
    Move-Item "$InstallRoot\python_pkg\tools" $PyDir
    Remove-Item -Recurse -Force "$InstallRoot\python_pkg"
}
if (-not (Test-Path "$PgDir\bin\pg_ctl.exe")) {
    Log "extracting PostgreSQL $PgVersion"
    Expand-Archive "$Downloads\postgres.zip" "$InstallRoot\pg_tmp" -Force
    if (Test-Path $PgDir) { Remove-Item -Recurse -Force $PgDir }
    Move-Item "$InstallRoot\pg_tmp\pgsql" $PgDir
    Remove-Item -Recurse -Force "$InstallRoot\pg_tmp"
}
if (-not (Test-Path "$RedisDir\redis-server.exe")) {
    Log "extracting Redis $RedisVersion"
    Expand-Archive "$Downloads\redis.zip" $RedisDir -Force
}

# --- 3. Python venv + backend deps ----------------------------------------------
$Venv = Join-Path $InstallRoot "venv"
$VPy  = "$Venv\Scripts\python.exe"
if (-not (Test-Path $VPy)) {
    Log "creating Python 3.10 venv"
    & "$PyDir\python.exe" -m venv $Venv
    & $VPy -m pip install -q -U pip wheel setuptools
}
Log "installing backend requirements (first run takes a few minutes)"
& $VPy -m pip install -q -r "$ProjectRoot\requirements.txt" -r "$ProjectRoot\requirements-dev.txt"
if ($LASTEXITCODE -ne 0) { throw "pip install failed" }

# --- 4. Frontend deps ------------------------------------------------------------
$env:PATH = "$NodeDir;$env:PATH"
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = "0"
Push-Location $ProjectRoot
try {
    & "$NodeDir\corepack.cmd" enable | Out-Null
    Log "installing frontend packages with pnpm (first run takes 10-20 min)"
    & "$NodeDir\pnpm.cmd" install
    if ($LASTEXITCODE -ne 0) { throw "pnpm install failed" }
} finally { Pop-Location }

# --- 5. PostgreSQL cluster ---------------------------------------------------------
$PgData = Join-Path $DataDir "pg"
if (-not (Test-Path "$PgData\PG_VERSION")) {
    Log "initializing PostgreSQL cluster"
    & "$PgDir\bin\initdb.exe" -D $PgData -U learningequality -A trust -E UTF8 --no-locale | Out-Null
}
& "$PgDir\bin\pg_ctl.exe" -D $PgData status *> $null
if ($LASTEXITCODE -ne 0) {
    Log "starting PostgreSQL"
    & "$PgDir\bin\pg_ctl.exe" -D $PgData -l "$DataDir\pg.log" -w start | Out-Null
}
& "$PgDir\bin\psql.exe" -U learningequality -d kolibri-studio -c "select 1" *> $null
if ($LASTEXITCODE -ne 0) {
    Log "creating database kolibri-studio"
    & "$PgDir\bin\createdb.exe" -U learningequality kolibri-studio
}

# --- 6. Redis + MinIO -----------------------------------------------------------------
if (-not (Get-NetTCPConnection -LocalPort 6379 -State Listen -ErrorAction SilentlyContinue)) {
    Log "starting Redis"
    Start-Process -WindowStyle Hidden "$RedisDir\redis-server.exe" -ArgumentList "--port 6379 --maxmemory 256mb"
}
if (-not (Get-NetTCPConnection -LocalPort 9000 -State Listen -ErrorAction SilentlyContinue)) {
    Log "starting MinIO"
    $env:MINIO_ROOT_USER = "development"; $env:MINIO_ROOT_PASSWORD = "development"
    Start-Process -WindowStyle Hidden "$Downloads\minio.exe" -ArgumentList "server `"$DataDir\minio`" --address :9000 --console-address :9001"
    Start-Sleep 4
}
Log "ensuring MinIO bucket 'content' exists"
& $VPy -c @"
import boto3, json
s3 = boto3.client('s3', endpoint_url='http://localhost:9000', aws_access_key_id='development', aws_secret_access_key='development')
try: s3.create_bucket(Bucket='content')
except Exception: pass
s3.put_bucket_policy(Bucket='content', Policy=json.dumps({'Version':'2012-10-17','Statement':[{'Effect':'Allow','Principal':{'AWS':['*']},'Action':['s3:GetObject'],'Resource':['arn:aws:s3:::content/*']}]}))
"@

# --- 7. Migrations + seed data -----------------------------------------------------------
Push-Location "$ProjectRoot\contentcuration"
try {
    if ($NoDemoData) {
        Log "running migrations (no demo data)"
        & $VPy manage.py setup --clean-data-state --settings=contentcuration.dev_settings
    } else {
        Log "running migrations and seeding demo data"
        & $VPy manage.py setup --settings=contentcuration.dev_settings
    }
    if ($LASTEXITCODE -ne 0) { throw "manage.py setup failed" }
} finally { Pop-Location }

# --- 8. Launcher -------------------------------------------------------------------------
$Bat = Join-Path $InstallRoot "start-studio.bat"
@"
@echo off
REM Starts the full Kolibri Studio dev stack (generated by install-windows.ps1)
set ENV=$InstallRoot
set PROJ=$ProjectRoot
set PATH=%ENV%\node;%PATH%
set COREPACK_ENABLE_DOWNLOAD_PROMPT=0

"%ENV%\pgsql\bin\pg_ctl.exe" -D "%ENV%\data\pg" status >nul 2>&1
if errorlevel 1 "%ENV%\pgsql\bin\pg_ctl.exe" -D "%ENV%\data\pg" -l "%ENV%\data\pg.log" start
start "redis"  /min "%ENV%\redis\redis-server.exe" --port 6379 --maxmemory 256mb
set MINIO_ROOT_USER=development
set MINIO_ROOT_PASSWORD=development
start "minio"  /min "%ENV%\downloads\minio.exe" server "%ENV%\data\minio" --address :9000 --console-address :9001
start "celery" /min cmd /c "cd /d %PROJ%\contentcuration && set DJANGO_SETTINGS_MODULE=contentcuration.dev_settings&& %ENV%\venv\Scripts\celery.exe -A contentcuration worker --pool=solo -l info --without-mingle --without-gossip"
start "webpack" /min cmd /c "cd /d %PROJ% && %ENV%\node\pnpm.cmd run build:dev"
echo Kolibri Studio starting on http://127.0.0.1:$Port  (login: a@a.com / a)
start "" /min cmd /c "timeout /t 15 >nul & start http://127.0.0.1:$Port/"
cd /d %PROJ%\contentcuration
"%ENV%\venv\Scripts\python.exe" manage.py runserver --settings=contentcuration.dev_settings --noreload 127.0.0.1:$Port
"@ | Set-Content -Encoding ascii $Bat

# --- 9. Desktop shortcut -------------------------------------------------------------------
$IconSrc = Join-Path $ProjectRoot "contentcuration\contentcuration\static\img\logo.ico"
$IconDst = Join-Path $InstallRoot "kolibri-studio.ico"
if (Test-Path $IconSrc) { Copy-Item $IconSrc $IconDst -Force }
$Shortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Kolibri Studio.lnk"
$Shell = New-Object -ComObject WScript.Shell
$Lnk = $Shell.CreateShortcut($Shortcut)
$Lnk.TargetPath = $Bat
$Lnk.WorkingDirectory = $InstallRoot
if (Test-Path $IconDst) { $Lnk.IconLocation = "$IconDst,0" }
$Lnk.Description = "Start Kolibri Studio (http://127.0.0.1:$Port)"
$Lnk.Save()
Log "Desktop shortcut created: $Shortcut"

Log "=================================================================="
Log "Install complete."
Log "Start everything:  $Bat"
Log "URL:               http://127.0.0.1:$Port  (first webpack compile ~1 min)"
if (-not $NoDemoData) { Log "Logins:            a@a.com/a (admin), user@a.com/a, user@b.com/b, user@c.com/c" }
Log "=================================================================="
