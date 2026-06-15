# shotwatch.ps1 — auto-put each new screenshot's file PATH on the clipboard, so you can paste it
# into a terminal AI tool (Claude Code, aider, Cursor CLI...) that can't accept a pasted image.
# Take a screenshot, then Ctrl+V the path into the tool. Runs hidden; shotwatch-run.ps1 supervises
# it and relaunches if it ever dies. See README.md for install/uninstall.
#
# ───────────────────────── HOW IT WORKS ─────────────────────────
# A poll loop (every $PollMs) does two checks, then puts the path (and/or image — see $ImageMode)
# on the clipboard via Set-ClipboardSticky:
#   1. FOLDER WATCH  — a new or re-saved file in the Screenshots folder (covers Win+PrtScn and
#                      "annotate -> Save"). Detects re-saves by tracking last-write time, not name.
#   2. CLIPBOARD WATCH — an image freshly COPIED with no file (covers "annotate -> Copy"). Saves it
#                      as clip_<time>.png, then hands off the path. Driven by a real clipboard EVENT
#                      listener (ClipWatcher / WM_CLIPBOARDUPDATE), so it reacts with no poll lag.
#
# Why the guards exist (each maps to a real bug found the hard way):
#   $seen        path -> last-write time. New/changed files fire; unchanged ones don't.
#   $ownClips    clip_*.png WE saved — the folder watch must skip them (else double-processing).
#   $hashToPath  pixel-hash -> our clip path. A re-copy (Snipping Tool's Copy re-puts the RAW image)
#                must RE-ASSERT the existing path, not be ignored — else the raw image sits on the
#                clipboard and a terminal pastes nothing.
#   $placedHash  pixel-hash of an image WE placed (image modes only) — so our own put isn't mistaken
#                for a user copy and reprocessed in a loop.
# Pixel-hash (Get-BitmapHash), not PNG bytes, because re-encoding isn't deterministic.
# Set-ClipboardSticky re-asserts for ~2s: screenshot tools copy the image a beat late and the
# clipboard is a single shared lock another app can momentarily hold; either would drop our write.

# ============================ CONFIG ============================
# Only copy while one of these processes is running, so it never hijacks your clipboard
# the rest of the time. Use the EXE name without ".exe". Empty array = always copy.
#   Rider=rider64  IntelliJ=idea64  PyCharm=pycharm64  WebStorm=webstorm64  CLion=clion64
#   GoLand=goland64  PhpStorm=phpstorm64  RubyMine=rubymine64  DataGrip=datagrip64
#   VS Code=Code  Windows Terminal=WindowsTerminal
$GuardProcesses = @('rider64')

# Folder to watch. Empty = auto-detect the Windows Screenshots folder (handles OneDrive redirect).
$WatchFolder = ''

# Image extensions to react to, and how often to poll (ms). Lower = the path replaces a copied
# image faster, so a quick copy-then-paste doesn't beat it to the clipboard.
$Extensions   = @('.png', '.jpg', '.jpeg')
$PollMs       = 200

# What lands on the clipboard for each screenshot:
#   'both'   = path text + image together. Claude/editors paste the PATH; pure image apps
#              (Paint/Discord/Blender) paste the PICTURE. A surface that accepts both (browser
#              search bar) prefers text. (recommended — Claude paste always works)
#   'never'  = path text only — most reliable for terminal/editor paste.
#   'always' = image only — best for browsers/search bars/image apps, but Claude can't read it.
#   'smart'  = path text when a guard/IDE window is in front, image otherwise. Note: capturing
#              another app to show Claude then fails, since that app is the foreground.
# Default 'never': an image on the clipboard makes terminals (Rider/Claude) intermittently paste
# NOTHING instead of the path. Text-only is rock-solid for pasting into Claude — which is the point.
# The screenshot is still saved as a file you can drag into image apps. Flip to 'both'/'always' if
# you'd rather paste the picture (and accept flaky terminal paste).
$ImageMode    = 'never'

# Also watch the CLIPBOARD for images (so "annotate in Snipping Tool, then hit Copy" works even
# though no file is saved). When a freshly copied image appears that isn't already a recent file,
# shotwatch saves it to the watch folder itself and hands you the path. $false = folder only.
$WatchClipboard = $true

# Auto-delete shotwatch's own clip_*.png after this many days (they pile up from Copy captures).
# 0 = keep forever. Only ever touches files named clip_* that shotwatch created.
$ClipKeepDays = 1

# Write a diagnostic log next to this script (shotwatch.log). Flip to $true to troubleshoot.
$DebugLog     = $false
# ========================== END CONFIG =========================

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
$md5 = [System.Security.Cryptography.MD5]::Create()
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Fg {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
}
"@ | Out-Null

# Real clipboard EVENT listener (vs. polling the sequence number): a message-only window that
# Windows notifies on every clipboard change via WM_CLIPBOARDUPDATE. We just count changes; the
# loop reacts the moment a change is dispatched (DoEvents), so there's no poll latency.
Add-Type -ReferencedAssemblies 'System.Windows.Forms' @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class ClipWatcher : NativeWindow, IDisposable {
    const int WM_CLIPBOARDUPDATE = 0x031D;
    [DllImport("user32.dll")] static extern bool AddClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    public int Changes = 0;
    public ClipWatcher() {
        CreateParams cp = new CreateParams();
        cp.Parent = (IntPtr)(-3); // HWND_MESSAGE — a message-only window
        this.CreateHandle(cp);
        AddClipboardFormatListener(this.Handle);
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_CLIPBOARDUPDATE) { Changes++; }
        base.WndProc(ref m);
    }
    public void Dispose() {
        try { RemoveClipboardFormatListener(this.Handle); } catch {}
        this.DestroyHandle();
    }
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

# Tidy up: delete auto-saved clip_*.png older than $ClipKeepDays (they accumulate from Copy captures).
# 0 = keep forever. Only touches files shotwatch itself created (clip_ prefix), never your own shots.
if ($ClipKeepDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$ClipKeepDays)
    Get-ChildItem -Path $WatchFolder -Filter 'clip_*.png' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object { try { Remove-Item $_.FullName -Force } catch {} }
}

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

# Decide which clipboard formats to use for this capture, based on $ImageMode + foreground window.
function Get-Formats {
    $fg = Get-ForegroundProc
    $useImage = $true; $useText = $true
    switch ($ImageMode) {
        'both'   { }
        'never'  { $useImage = $false }
        'always' { $useText  = $false }
        default  { if ($GuardProcesses -contains $fg) { $useImage = $false } else { $useText = $false } }
    }
    return @{ fg = $fg; img = $useImage; txt = $useText }
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

# Hash a bitmap by its raw PIXELS (deterministic — unlike re-encoding to PNG), so we can reliably
# tell "an image WE just placed on the clipboard" from "a new image the user copied".
function Get-BitmapHash($bmp) {
    try {
        $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
        $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $len = [Math]::Abs($data.Stride) * $bmp.Height
        $buf = New-Object byte[] $len
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $len)
        $bmp.UnlockBits($data)
        return ("{0}x{1}:" -f $bmp.Width, $bmp.Height) + [System.BitConverter]::ToString($md5.ComputeHash($buf))
    } catch { return '' }
}
# Pixel-hash of whatever image is on the clipboard right now (or '' if none).
function Get-ClipImageHash {
    try {
        if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) { return '' }
        $i = [System.Windows.Forms.Clipboard]::GetImage()
        if (-not $i) { return '' }
        $h = Get-BitmapHash $i
        $i.Dispose()
        return $h
    } catch { return '' }
}

$placedHash = ''    # pixel-hash of the image WE put on the clipboard (only in image modes), to ignore our echo
$ownClips = New-Object System.Collections.Generic.HashSet[string]   # clip_*.png we created ourselves
$hashToPath = @{}   # pixel-hash -> clip file we already saved for it (so a re-copy re-asserts the path)

$clip = New-Object ClipWatcher        # clipboard EVENT listener (no polling)
$lastChanges = $clip.Changes

# Event-driven loop: a short pump tick keeps WM_CLIPBOARDUPDATE flowing to the listener (so the
# clipboard reaction is ~instant), while the folder is scanned on a slower cadence (files aren't
# latency-critical — you paste them later). $PollMs is now the folder cadence.
$LoopMs   = 40
$folderMs = $PollMs
$folderAccum = $folderMs    # force an initial folder scan
$hbAccum = 0
while ($true) {
    try {
        # Pump messages: dispatches WM_CLIPBOARDUPDATE to the listener AND keeps OLE clipboard healthy.
        [System.Windows.Forms.Application]::DoEvents()

        # --- Folder watch (new or re-saved screenshot file) — on $folderMs cadence ---
        $folderAccum += $LoopMs
        if ($folderAccum -ge $folderMs) {
            $folderAccum = 0
            $files = Get-ChildItem -Path $WatchFolder -File -ErrorAction SilentlyContinue |
                     Where-Object { $Extensions -contains $_.Extension } |
                     Sort-Object CreationTime
            foreach ($f in $files) {
                if ($ownClips.Contains($f.FullName)) { continue }   # our own clip_*.png — already handled
                $prev = $seen[$f.FullName]
                if ($null -eq $prev -or $f.LastWriteTimeUtc -gt $prev) {
                    $seen[$f.FullName] = $f.LastWriteTimeUtc
                    if (Test-GuardOpen) {
                        Wait-FileReady $f.FullName
                        $fmt = Get-Formats
                        Log ("NEW " + $f.Name + " fg=$($fmt.fg) img=$($fmt.img) txt=$($fmt.txt)")
                        Set-ClipboardSticky $f.FullName $fmt.img $fmt.txt | Out-Null
                        $placedHash = if ($fmt.img) { Get-ClipImageHash } else { '' }
                    } else {
                        Log ("NEW " + $f.Name + " (skipped, guard closed)")
                    }
                }
            }
        }

        # --- Clipboard watch (annotate-then-Copy) — fires the instant the listener sees a change ---
        if ($WatchClipboard -and $clip.Changes -ne $lastChanges) {
            if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                $cimg = [System.Windows.Forms.Clipboard]::GetImage()
                if ($cimg) {
                    $chash = Get-BitmapHash $cimg
                    # Ignore the echo of an image WE placed (image modes only). Otherwise an image on
                    # the clipboard is the user's copy — make sure the PATH ends up there, even if it's
                    # a re-copy of an image we've already captured (a re-copy puts the raw image back).
                    if ($chash -ne '' -and $chash -ne $placedHash -and (Test-GuardOpen)) {
                        $path = $null
                        if ($hashToPath.ContainsKey($chash) -and (Test-Path $hashToPath[$chash])) {
                            $path = $hashToPath[$chash]
                            Log ("RECLIP $([System.IO.Path]::GetFileName($path))")
                        } else {
                            $cms = New-Object System.IO.MemoryStream
                            $cimg.Save($cms, [System.Drawing.Imaging.ImageFormat]::Png)
                            $cbytes = $cms.ToArray(); $cms.Dispose()
                            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
                            $path = Join-Path $WatchFolder ("clip_$stamp.png")
                            [System.IO.File]::WriteAllBytes($path, $cbytes)
                            [void]$ownClips.Add($path)
                            $seen[$path] = (Get-Item $path).LastWriteTimeUtc
                            $hashToPath[$chash] = $path
                            Log ("CLIP saved $([System.IO.Path]::GetFileName($path))")
                        }
                        if ($path) {
                            $fmt = Get-Formats
                            Set-ClipboardSticky $path $fmt.img $fmt.txt | Out-Null
                            $placedHash = if ($fmt.img) { Get-ClipImageHash } else { '' }
                        }
                    }
                    $cimg.Dispose()
                }
            }
            $lastChanges = $clip.Changes   # absorb our own clipboard writes from processing above
        }
    } catch { Log ("LOOP-ERR " + $_.Exception.Message) }

    # Heartbeat every ~60s (gap >> 60s between them = the process was suspended while idle).
    $hbAccum += $LoopMs
    if ($hbAccum -ge 60000) { $hbAccum = 0; Log "heartbeat" }
    Start-Sleep -Milliseconds $LoopMs
}
