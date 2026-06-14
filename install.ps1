# install.ps1 — installs shotwatch to %LOCALAPPDATA%\shotwatch, auto-runs it hidden on login,
# and starts it now. Re-running re-installs cleanly. No admin rights needed.
#
# Run:  right-click -> "Run with PowerShell"   (or)   powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = 'Stop'
$src     = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest    = Join-Path $env:LOCALAPPDATA 'shotwatch'
$startup = [Environment]::GetFolderPath('Startup')
$vbsPath = Join-Path $startup 'shotwatch.vbs'

# Stop any running instance.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*shotwatch.ps1*' -and $_.CommandLine -notlike '*-Command*' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }

# Copy script to a stable per-user location.
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item (Join-Path $src 'shotwatch.ps1') -Destination $dest -Force

# Hidden launcher in Startup (no console flash).
$installedScript = Join-Path $dest 'shotwatch.ps1'
$vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$installedScript""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII

# Start it now.
Start-Process wscript.exe -ArgumentList "`"$vbsPath`""

Write-Host ""
Write-Host "  shotwatch installed." -ForegroundColor Green
Write-Host "    script : $installedScript"
Write-Host "    startup: $vbsPath"
Write-Host ""
Write-Host "  Take a screenshot to the Screenshots folder (Win+PrtScn) and the path is on your clipboard." -ForegroundColor Cyan
Write-Host "  Guard processes (edit shotwatch.ps1 CONFIG to change): see the file." -ForegroundColor DarkGray
Write-Host ""
