# =============================================================================
# Builds a self-contained Windows offline installer for Kolibri Studio.
# Run on a machine where install-windows.ps1 has already completed (it reuses
# the downloaded runtimes and the local pnpm store).
#
#   powershell -ExecutionPolicy Bypass -File deploy\build-offline-bundle.ps1
#
# Output: kolibri-studio-offline-installer.zip (~1.2 GB) containing:
#   INSTALL.bat            one-click installer, no internet required
#   source\                full project source
#   payload\downloads\     Node, Python, PostgreSQL, Redis, MinIO
#   payload\wheels\        all Python packages as wheels
#   payload\pnpm-store\    all frontend packages
#   payload\pnpm.exe       standalone pnpm
# =============================================================================
[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:USERPROFILE\kolibri-studio-env",
    [string]$OutputDir = "$env:USERPROFILE\Downloads",
    [string]$PnpmVersion = "10.33.0"
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Stage = Join-Path $env:TEMP "studio-offline-bundle"
$VPy = Join-Path $InstallRoot "venv\Scripts\python.exe"
$StoreSrc = "$env:LOCALAPPDATA\pnpm\store\v10"

function Log($msg) { Write-Host "[bundle] $msg" -ForegroundColor Cyan }

foreach ($req in @("$InstallRoot\downloads\node.zip", $VPy, $StoreSrc)) {
    if (-not (Test-Path $req)) { throw "Missing $req - run install-windows.ps1 first." }
}

if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force "$Stage\payload\downloads", "$Stage\payload\wheels" | Out-Null

Log "copying runtime downloads..."
Copy-Item "$InstallRoot\downloads\node.zip", "$InstallRoot\downloads\python.nupkg.zip", `
          "$InstallRoot\downloads\postgres.zip", "$InstallRoot\downloads\redis.zip", `
          "$InstallRoot\downloads\minio.exe" "$Stage\payload\downloads\"

Log "collecting Python wheels (pip download)..."
& $VPy -m pip download -q -r "$ProjectRoot\requirements.txt" -r "$ProjectRoot\requirements-dev.txt" `
    -d "$Stage\payload\wheels"
if ($LASTEXITCODE -ne 0) { throw "pip download failed" }

Log "copying pnpm store ($StoreSrc)..."
& robocopy $StoreSrc "$Stage\payload\pnpm-store" /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy of pnpm store failed" }

Log "downloading standalone pnpm $PnpmVersion..."
& curl.exe -fsSL -o "$Stage\payload\pnpm.exe" "https://github.com/pnpm/pnpm/releases/download/v$PnpmVersion/pnpm-win-x64.exe"
if ($LASTEXITCODE -ne 0) { throw "pnpm download failed" }

Log "copying project source..."
& robocopy $ProjectRoot "$Stage\source" /E /NFL /NDL /NJH /NJS /NP `
    /XD node_modules .git __pycache__ /XF *.pyc | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy of source failed" }

Log "writing INSTALL.bat..."
@'
@echo off
REM Kolibri Studio - offline installer. No internet connection required.
echo Installing Kolibri Studio (this takes several minutes)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0source\deploy\install-windows.ps1" -OfflineDir "%~dp0payload" -Port 8080
if errorlevel 1 (
  echo.
  echo INSTALL FAILED - see messages above.
) else (
  echo.
  echo Done! Use the "Kolibri Studio" desktop shortcut to start.
)
pause
'@ | Set-Content -Encoding ascii "$Stage\INSTALL.bat"

$Zip = Join-Path $OutputDir "kolibri-studio-offline-installer.zip"
Log "compressing to $Zip (takes a few minutes)..."
if (Test-Path $Zip) { Remove-Item -Force $Zip }
& tar.exe -acf $Zip -C $Stage INSTALL.bat source payload
if ($LASTEXITCODE -ne 0) { throw "zip creation failed" }

Remove-Item -Recurse -Force $Stage
Log "=================================================================="
Log "Offline installer ready: $Zip"
Log ("size: {0:N0} MB" -f ((Get-Item $Zip).Length / 1MB))
Log "Usage on the target PC: extract the zip anywhere, run INSTALL.bat"
Log "=================================================================="
