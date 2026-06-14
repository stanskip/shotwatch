# shotwatch.ps1 — auto-copy each new screenshot's file PATH to the clipboard, so you can
# paste it into a terminal-based AI tool (Claude Code, aider, Cursor CLI...) that can't take
# pasted images. Watches the Windows Screenshots folder; on a new image it copies that file's
# full path as TEXT. Each screenshot = its own path (nothing is overwritten).
#
# Runs hidden in the background. See README.md for install/uninstall.

# ============================ CONFIG ============================
# Only copy while one of these processes is running, so it never hijacks your clipboard
# the rest of the time. Use the EXE name without ".exe". Empty array = always copy.
#   Rider=rider64  IntelliJ=idea64  PyCharm=pycharm64  WebStorm=webstorm64  CLion=clion64
#   GoLand=goland64  PhpStorm=phpstorm64  RubyMine=rubymine64  DataGrip=datagrip64
#   VS Code=Code  Windows Terminal=WindowsTerminal
$GuardProcesses = @('rider64')

# Folder to watch. Empty = auto-detect the Windows Screenshots folder (handles OneDrive redirect).
$WatchFolder = ''

# Image extensions to react to, and how often to poll (ms).
$Extensions   = @('.png', '.jpg', '.jpeg')
$PollMs       = 500
# ========================== END CONFIG =========================

Add-Type -AssemblyName System.Windows.Forms | Out-Null

if ([string]::IsNullOrWhiteSpace($WatchFolder)) {
    $WatchFolder = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'
}
if (-not (Test-Path $WatchFolder)) { New-Item -ItemType Directory -Path $WatchFolder -Force | Out-Null }

# Seed: remember existing files so we never re-copy old shots.
$seen = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -Path $WatchFolder -File -ErrorAction SilentlyContinue |
    Where-Object { $Extensions -contains $_.Extension } |
    ForEach-Object { [void]$seen.Add($_.FullName) }

function Test-GuardOpen {
    if ($GuardProcesses.Count -eq 0) { return $true }
    foreach ($p in $GuardProcesses) {
        if (Get-Process -Name $p -ErrorAction SilentlyContinue) { return $true }
    }
    return $false
}

# Wait until the file stops growing (screenshot finished writing).
function Wait-FileReady($path) {
    $last = -1
    for ($i = 0; $i -lt 20; $i++) {
        try { $len = (Get-Item $path -ErrorAction Stop).Length } catch { Start-Sleep -Milliseconds 100; continue }
        if ($len -gt 0 -and $len -eq $last) { return }
        $last = $len
        Start-Sleep -Milliseconds 120
    }
}

while ($true) {
    try {
        $files = Get-ChildItem -Path $WatchFolder -File -ErrorAction SilentlyContinue |
                 Where-Object { $Extensions -contains $_.Extension } |
                 Sort-Object CreationTime
        foreach ($f in $files) {
            if (-not $seen.Contains($f.FullName)) {
                [void]$seen.Add($f.FullName)
                if (Test-GuardOpen) {
                    Wait-FileReady $f.FullName
                    Set-Clipboard -Value $f.FullName
                }
            }
        }
    } catch { }
    Start-Sleep -Milliseconds $PollMs
}
