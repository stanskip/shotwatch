# install.ps1 — installs shotwatch to %LOCALAPPDATA%\shotwatch, auto-runs it hidden on login via
# a supervisor that relaunches the watcher if it ever dies, and starts it now. No admin needed.
#
# Run:  right-click -> "Run with PowerShell"   (or)   powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = 'Stop'
$src     = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest    = Join-Path $env:LOCALAPPDATA 'shotwatch'
$startup = [Environment]::GetFolderPath('Startup')
$vbsPath = Join-Path $startup 'shotwatch.vbs'

# Stop any running supervisor/watcher.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { ($_.CommandLine -like '*shotwatch.ps1*' -or $_.CommandLine -like '*shotwatch-run.ps1*') -and $_.CommandLine -notlike '*-Command*' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }

# Copy scripts to a stable per-user location.
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item (Join-Path $src 'shotwatch.ps1')     -Destination $dest -Force
Copy-Item (Join-Path $src 'shotwatch-run.ps1') -Destination $dest -Force

# Hidden launcher in Startup -> starts the supervisor (which keeps the watcher alive).
$supervisor = Join-Path $dest 'shotwatch-run.ps1'
$vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$supervisor""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII

# Start it now.
Start-Process wscript.exe -ArgumentList "`"$vbsPath`""

Write-Host ""
Write-Host "  shotwatch installed (self-healing)." -ForegroundColor Green
Write-Host "    watcher   : $(Join-Path $dest 'shotwatch.ps1')"
Write-Host "    supervisor: $supervisor   (relaunches the watcher if it dies)"
Write-Host "    startup   : $vbsPath"
Write-Host ""
Write-Host "  Take a screenshot (Win+PrtScn) and the path is on your clipboard." -ForegroundColor Cyan
Write-Host ""
