# shotwatch

**Take a screenshot, then just paste it into Claude (or any terminal AI tool) — it Just Works.**

Terminal-based AI tools (Claude Code, aider, Cursor CLI…) and JetBrains' built-in terminal **can't
take a pasted image**. They only take text. shotwatch bridges that gap automatically: when you take
a screenshot, it puts the screenshot's **file path** on your clipboard. You press `Ctrl+V`, the tool
reads the file. Done — no saving paths by hand, no extra steps.

```
Take a screenshot   →   (path is already on your clipboard)   →   Ctrl+V into Claude
```

It also keeps the **image** on the clipboard, so the *same* screenshot still pastes as a picture
into image apps (Paint, Discord, Blender…). The app you paste into decides which it grabs:

| Where you paste | What you get |
| --- | --- |
| Claude / terminal / text box | the **path** |
| Paint / Discord / image slot | the **image** |
| Browser search bar (takes both) | the **path** *(see `$ImageMode` to change this)* |

## Everything it handles

- **Plain screenshot** → path on clipboard.
- **Annotate then Save** (Snipping Tool markup → Save) → path to the marked-up file.
- **Annotate then Copy** (markup → Copy, *no save*) → it saves the copied image for you and gives the path.
- **Re-saving the same file** (more annotations, same name) → re-fires; you're not stuck.
- **Several in a row** → each screenshot has its own path, nothing gets overwritten.
- **If it crashes** → it restarts itself within seconds (see "Stays alive" below).

## Install (no admin needed)

1. Download/clone this folder.
2. Right-click **`install.ps1`** → *Run with PowerShell*
   (or: `powershell -ExecutionPolicy Bypass -File install.ps1`)

That copies the scripts to `%LOCALAPPDATA%\shotwatch`, starts them now, and auto-runs on every login.
Take a screenshot and paste — that's the whole setup.

**Uninstall:** right-click `uninstall.ps1` → *Run with PowerShell*.

## Stays alive (the "supervisor")

There are two small background scripts:

- **`shotwatch.ps1`** — the *watcher*. The actual worker that watches for screenshots.
- **`shotwatch-run.ps1`** — the *supervisor*. Its only job is to keep the watcher running: if the
  watcher ever stops (a rare clipboard hiccup, waking from sleep, etc.), the supervisor relaunches
  it within a few seconds. The supervisor itself does nothing risky, so it just stays up.

So a single crash never leaves you stranded — it heals on its own. On login, Windows starts the
supervisor, the supervisor starts the watcher.

## How it works (plain version)

Every half-second the watcher quietly checks two things:

1. **Your Screenshots folder** — did a new (or re-saved) screenshot appear? If so, it puts that
   file's path (and the image) on the clipboard.
2. **The clipboard** — did you just *Copy* an image that isn't a saved file yet (e.g. an annotated
   snip)? If so, it saves that image to the folder as `clip_<time>.png` and hands you the path.

It only does this while your editor (Rider by default) is running, so it never messes with your
clipboard when you're doing unrelated work. And it re-asserts what it put on the clipboard for a
couple seconds, so Windows' own "image copied" can't knock it off.

No network. No admin. No compiled binary — just readable PowerShell you can open and check.

## Configure

Edit the **CONFIG** block at the top of `shotwatch.ps1`, then re-run `install.ps1`:

- **`$GuardProcesses`** — only act while one of these apps is running. EXE name without `.exe`.
  Empty `@()` = always. Examples: `rider64` (Rider), `idea64` (IntelliJ), `pycharm64`,
  `webstorm64`, `clion64`, `goland64`, `Code` (VS Code), `WindowsTerminal`.
- **`$ImageMode`** — `both` (default: path + image), `never` (path only — most reliable for
  terminals), `always` (image only — best for browser search bars, but Claude can't read it),
  `smart` (path when your editor is focused, image otherwise).
- **`$WatchClipboard`** — `true` (default) makes annotate-then-Copy work. `false` = folder only.
- **`$WatchFolder`** — blank = auto-detect Windows Screenshots folder. Or set a path.
- **`$DebugLog`** — `true` writes `shotwatch.log` next to the script for troubleshooting.

> Tip: `Win+PrtScn` saves a screenshot to the folder. `Win+Shift+S` snips to the clipboard
> (and Copy-after-annotate is covered too).

## Optional: bulletproof watchdog (needs admin)

The supervisor covers crashes of the watcher. If you want it to survive *even the supervisor*
dying or being killed, run **`install-watchdog.ps1` as Administrator** once. It registers a Windows
Scheduled Task that re-checks every few minutes and relaunches if nothing is running. Totally
optional — the normal install is already self-healing for everyday use.

## Requirements

Windows 10/11, Windows PowerShell 5.1 (built in).
