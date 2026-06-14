# shotwatch

Paste **screenshots** into terminal AI tools that only accept file paths — without typing anything.

Terminal-based AI tools (Claude Code, aider, Cursor CLI, …) and JetBrains' integrated terminal
can't take a pasted *image*. shotwatch fixes that: it watches your Windows **Screenshots** folder,
and the instant a new screenshot lands it copies **that file's path** to your clipboard as text.
You just `Ctrl+V` the path into the tool.

```
Win+PrtScn   ->   (path is now on your clipboard)   ->   Ctrl+V into your AI tool
```

Each screenshot gets its own path — nothing is overwritten, so you can paste several in a row.

It keeps the **image on the clipboard too**, so the same screenshot still pastes as a picture
into image apps (Blender, Photoshop, Discord…). Text targets get the path; pure-image targets get
the image — the receiving app picks the format, no mode switching.

> Note: a surface that accepts *both* text and images (e.g. a browser search bar) will prefer the
> **path**. If you want such places to paste the image instead, set `$ImageMode = 'always'` (image
> only) — but then Claude/terminals can't read it. See the `$ImageMode` options in the script.

## Why it doesn't annoy you

It only copies the path **while a "guard" app is running** (Rider by default), so it never touches
your clipboard the rest of the time. Configurable — see below.

## Install (no admin needed)

1. Download/clone this folder.
2. Right-click `install.ps1` → **Run with PowerShell**.
   (or: `powershell -ExecutionPolicy Bypass -File install.ps1`)

That copies the script to `%LOCALAPPDATA%\shotwatch`, starts it now, and auto-runs it hidden on
every login. Done.

## Configure

Edit the **CONFIG** block at the top of `shotwatch.ps1`, then re-run `install.ps1`:

- `$GuardProcesses` — only copy while one of these apps is running. Use the EXE name without `.exe`.
  Empty array `@()` = always copy. Common ones:
  `rider64` (Rider), `idea64` (IntelliJ), `pycharm64`, `webstorm64`, `clion64`, `goland64`,
  `phpstorm64`, `Code` (VS Code), `WindowsTerminal`.
- `$WatchFolder` — empty = auto-detect the Windows Screenshots folder (handles OneDrive). Or set a path.
- `$Extensions`, `$PollMs` — what to watch for and how often.

> Tip: `Win+PrtScn` saves to the Screenshots folder. `Win+Shift+S` (Snip) copies to the clipboard
> but does **not** save a file — set Snip to auto-save, or just use `Win+PrtScn`.

## Uninstall

Right-click `uninstall.ps1` → **Run with PowerShell**.

## How it works / is it safe?

~60 lines of plain PowerShell (read it). It polls the Screenshots folder a couple times a second
and, when guarded, writes a file path to the clipboard. No network, no admin, no compiled binary.

## Requirements

Windows 10/11, Windows PowerShell 5.1 (built in).
