# shotwatch-run.ps1 — supervisor. Keeps shotwatch.ps1 alive: if the watcher ever exits
# (crash, etc.), this relaunches it within a few seconds. Does no clipboard/file work itself,
# so it doesn't share the watcher's crash risk. Singleton via a named mutex.
$createdNew = $false
$mtx = New-Object System.Threading.Mutex($true, 'shotwatch_supervisor_v1', [ref]$createdNew)
if (-not $createdNew) { exit 0 }   # another supervisor already running

$script = Join-Path (Split-Path -Parent $PSCommandPath) 'shotwatch.ps1'
while ($true) {
    try {
        $p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile','-Sta','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$script
        )
        $p.WaitForExit()
    } catch { }
    Start-Sleep -Seconds 3   # small backoff so a crash-loop doesn't spin hot
}
