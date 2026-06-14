# uninstall.ps1 — stops shotwatch, removes the Startup launcher and installed files.
$startup = [Environment]::GetFolderPath('Startup')
$dest    = Join-Path $env:LOCALAPPDATA 'shotwatch'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*shotwatch.ps1*' -and $_.CommandLine -notlike '*-Command*' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }

Remove-Item (Join-Path $startup 'shotwatch.vbs') -Force -ErrorAction SilentlyContinue
Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "  shotwatch uninstalled." -ForegroundColor Yellow
