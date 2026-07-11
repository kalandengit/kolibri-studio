# Stops every Kolibri Studio process started by start-studio.bat / the Windows
# installer: Django, Celery, webpack, Redis, MinIO and PostgreSQL.
#   powershell -ExecutionPolicy Bypass -File deploy\stop-windows.ps1 [-InstallRoot <dir>]
[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:USERPROFILE\kolibri-studio-env"
)
$ErrorActionPreference = "SilentlyContinue"

function Log($msg) { Write-Host "[studio-stop] $msg" -ForegroundColor Cyan }

if (-not (Test-Path $InstallRoot)) { throw "Install root not found: $InstallRoot" }

# Kill every process whose executable lives under the install root
# (venv python = Django/Celery, node = webpack, redis-server, minio),
# except PostgreSQL which gets a clean shutdown below.
$procs = Get-Process | Where-Object {
    $_.Path -and $_.Path.StartsWith($InstallRoot, [System.StringComparison]::OrdinalIgnoreCase) `
      -and $_.Path -notmatch 'pgsql'
}
foreach ($p in $procs) {
    Log "stopping $($p.ProcessName) (pid $($p.Id))"
    Stop-Process -Id $p.Id -Force
}

# Clean PostgreSQL shutdown
$pgctl = Join-Path $InstallRoot "pgsql\bin\pg_ctl.exe"
$pgdata = Join-Path $InstallRoot "data\pg"
& $pgctl -D $pgdata status *> $null
if ($LASTEXITCODE -eq 0) {
    Log "stopping PostgreSQL"
    & $pgctl -D $pgdata -m fast stop | Out-Null
}

Log "done."
