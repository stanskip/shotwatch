# install-watchdog.ps1 — OPTIONAL, needs Administrator.
# The normal install is already self-healing (the supervisor relaunches the watcher). This adds a
# belt-and-suspenders Windows Scheduled Task that relaunches the SUPERVISOR itself every few minutes
# if it's ever gone — surviving even a supervisor kill or a resume-from-sleep that drops it.
#
# Run:  right-click -> "Run as administrator"  (or, from an elevated PowerShell:)
#       powershell -ExecutionPolicy Bypass -File install-watchdog.ps1

# Must be elevated.
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $admin) {
    Write-Host "  Please run this as Administrator (right-click -> Run as administrator)." -ForegroundColor Yellow
    exit 1
}

$supervisor = Join-Path $env:LOCALAPPDATA 'shotwatch\shotwatch-run.ps1'
if (-not (Test-Path $supervisor)) {
    Write-Host "  shotwatch isn't installed yet. Run install.ps1 first." -ForegroundColor Yellow
    exit 1
}

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $supervisor)
$trigger = New-ScheduledTaskTrigger -AtLogOn
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes 5) `
            -RepetitionDuration (New-TimeSpan -Days 9999)).Repetition
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName 'shotwatch-watchdog' -Action $action -Trigger $trigger `
    -Settings $settings -Description 'Relaunches the shotwatch supervisor if it ever stops.' -Force | Out-Null

Write-Host "  Watchdog installed (task 'shotwatch-watchdog'). Remove with:" -ForegroundColor Green
Write-Host "    Unregister-ScheduledTask -TaskName shotwatch-watchdog -Confirm:`$false" -ForegroundColor DarkGray
