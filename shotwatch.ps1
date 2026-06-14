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

# What lands on the clipboard for each screenshot:
#   'both'   = path text + image together. Claude/editors paste the PATH; pure image apps
#              (Paint/Discord/Blender) paste the PICTURE. A surface that accepts both (browser
#              search bar) prefers text. (recommended — Claude paste always works)
#   'never'  = path text only — most reliable for terminal/editor paste.
#   'always' = image only — best for browsers/search bars/image apps, but Claude can't read it.
#   'smart'  = path text when a guard/IDE window is in front, image otherwise. Note: capturing
#              another app to show Claude then fails, since that app is the foreground.
$ImageMode    = 'both'

# Write a diagnostic log next to this script (shotwatch.log). Flip to $true to troubleshoot.
$DebugLog     = $false
# ========================== END CONFIG =========================

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Fg {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
}
"@ | Out-Null

# Name (no .exe) of the process owning the foreground window, or '' if unknown.
function Get-ForegroundProc {
    try {
        $h = [Fg]::GetForegroundWindow()
        $procId = 0
        [void][Fg]::GetWindowThreadProcessId($h, [ref]$procId)
        if ($procId -gt 0) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($p) { return $p.ProcessName }
        }
    } catch { }
    return ''
}

$LogPath = Join-Path (Split-Path -Parent $PSCommandPath) 'shotwatch.log'
function Log($msg) {
    if (-not $DebugLog) { return }
    try { Add-Content -Path $LogPath -Value ((Get-Date -Format 'HH:mm:ss.fff') + '  ' + $msg) -ErrorAction SilentlyContinue } catch { }
}
Log "=== shotwatch started (pid $PID) ==="

if ([string]::IsNullOrWhiteSpace($WatchFolder)) {
    $WatchFolder = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'
}
if (-not (Test-Path $WatchFolder)) { New-Item -ItemType Directory -Path $WatchFolder -Force | Out-Null }

# Seed: remember existing files (path -> last-write time) so we never re-copy old shots.
# Tracking the timestamp (not just the name) means re-saving/overwriting the SAME file with new
# annotations is treated as new — otherwise a same-name overwrite looks "already seen" and is missed.
$seen = @{}
Get-ChildItem -Path $WatchFolder -File -ErrorAction SilentlyContinue |
    Where-Object { $Extensions -contains $_.Extension } |
    ForEach-Object { $seen[$_.FullName] = $_.LastWriteTimeUtc }

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

# Put the path text and/or the image on the clipboard and KEEP it there for ~2s. With $useText
# on, a terminal/editor pastes the PATH; with $useImage on, a pure image app pastes the PICTURE.
# (A surface that accepts BOTH, e.g. a browser search bar, prefers text when both are present.)
# We re-assert because screenshot tools copy the image a beat after saving the file, and the
# clipboard is a single shared lock another app can momentarily hold; either drops our write.
function Set-ClipboardSticky($path, $useImage, $useText) {
    # Build the clipboard object once. copy=$true flushes it to the OS clipboard so it survives
    # this process. Load the image from a memory copy so the file isn't locked.
    $data = New-Object System.Windows.Forms.DataObject
    $img = $null; $ms = $null
    if ($useImage) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $ms = New-Object System.IO.MemoryStream (,$bytes)
            $img = [System.Drawing.Image]::FromStream($ms)
            $data.SetImage($img)
        } catch { $useText = $true }         # image load failed -> at least give the text
    }
    if ($useText) { $data.SetText($path) }

    $ours = 0; $confirmed = $false; $sets = 0; $lastErr = ''
    for ($i = 0; $i -lt 16; $i++) {
        $ok = $false
        try {
            # Verify on whichever format we own; text first since it's the exact value check.
            if ($useText)       { $ok = ([System.Windows.Forms.Clipboard]::GetText() -eq $path) }
            elseif ($useImage)  { $ok = [System.Windows.Forms.Clipboard]::ContainsImage() }
        } catch { $lastErr = $_.Exception.Message }
        if ($ok) {
            $ours++
            if ($ours -ge 4) { $confirmed = $true; break }   # held steady ~0.5s -> races are over
        } else {
            $ours = 0
            $sets++
            try { [System.Windows.Forms.Clipboard]::SetDataObject($data, $true) } catch { $lastErr = $_.Exception.Message }
        }
        Start-Sleep -Milliseconds 130
    }
    if ($img) { $img.Dispose() }
    if ($ms)  { $ms.Dispose() }
    Log ("  set img=$useImage txt=$useText confirmed=$confirmed sets=$sets" + $(if ($lastErr) { " err=$lastErr" } else { '' }))
    return $confirmed
}

$tick = 0
while ($true) {
    try {
        # Pump the Windows message queue so the OLE clipboard stays healthy in this long-lived
        # STA thread (without this, clipboard ops can go stale after the process sits idle).
        [System.Windows.Forms.Application]::DoEvents()

        $files = Get-ChildItem -Path $WatchFolder -File -ErrorAction SilentlyContinue |
                 Where-Object { $Extensions -contains $_.Extension } |
                 Sort-Object CreationTime
        foreach ($f in $files) {
            $prev = $seen[$f.FullName]
            if ($null -eq $prev -or $f.LastWriteTimeUtc -gt $prev) {
                $seen[$f.FullName] = $f.LastWriteTimeUtc
                $guard = Test-GuardOpen
                if ($guard) {
                    Wait-FileReady $f.FullName
                    # Decide which formats to put on the clipboard:
                    #   both  -> path + image (Claude pastes path, image apps paste picture)
                    #   never -> path only        always -> image only
                    #   smart -> path when a guard/IDE window is focused, image otherwise
                    $fg = Get-ForegroundProc
                    $useImage = $true; $useText = $true
                    switch ($ImageMode) {
                        'both'   { }
                        'never'  { $useImage = $false }
                        'always' { $useText  = $false }
                        default  { if ($GuardProcesses -contains $fg) { $useImage = $false } else { $useText = $false } }
                    }
                    Log ("NEW " + $f.Name + " guard=$guard fg=$fg img=$useImage txt=$useText")
                    Set-ClipboardSticky $f.FullName $useImage $useText | Out-Null
                } else {
                    Log ("NEW " + $f.Name + " guard=$guard (skipped)")
                }
            }
        }
    } catch { Log ("LOOP-ERR " + $_.Exception.Message) }

    # Heartbeat every ~60s. A gap much larger than 60s between heartbeats = the process was
    # suspended/throttled while idle (which would explain a missed first-shot-after-idle).
    $tick++
    if ($tick -ge [int](60000 / $PollMs)) { $tick = 0; Log "heartbeat" }
    Start-Sleep -Milliseconds $PollMs
}
