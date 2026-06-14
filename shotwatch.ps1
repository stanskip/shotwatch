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

# Put BOTH the image and its path text on the clipboard at once, and KEEP them there for ~2s.
# A clipboard can hold multiple formats simultaneously: a text app (terminal/editor) pastes the
# PATH, an image app (Blender/Photoshop/chat) pastes the IMAGE — the target picks the format.
# We re-assert because screenshot tools copy the image a beat after saving the file, and the
# clipboard is a single shared lock another app can momentarily hold; either drops our write.
# Stops early once a different value sticks (you deliberately copied something else).
function Set-ClipboardSticky($path) {
    # Build a combined image+text object once. Load the image from a memory copy so the file
    # isn't locked. copy=$true flushes it to the OS clipboard so it survives this process.
    $data = New-Object System.Windows.Forms.DataObject
    $img = $null; $ms = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $ms = New-Object System.IO.MemoryStream (,$bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        $data.SetImage($img)
    } catch { }
    $data.SetText($path)

    $ours = 0
    for ($i = 0; $i -lt 16; $i++) {
        $cur = $null
        try { $cur = [System.Windows.Forms.Clipboard]::GetText() } catch { }
        if ($cur -eq $path) {
            $ours++
            if ($ours -ge 4) { break }            # held steady ~0.5s -> the races are over
        } else {
            $ours = 0
            try { [System.Windows.Forms.Clipboard]::SetDataObject($data, $true) } catch { }
        }
        Start-Sleep -Milliseconds 130
    }
    if ($img) { $img.Dispose() }
    if ($ms)  { $ms.Dispose() }
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
                    Set-ClipboardSticky $f.FullName
                }
            }
        }
    } catch { }
    Start-Sleep -Milliseconds $PollMs
}
