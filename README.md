# shotwatch

**Take a screenshot, then just paste it into Claude (or any terminal AI tool) — it Just Works.**

Terminal-based AI tools (Claude Code, aider, Cursor CLI…) and JetBrains' built-in terminal **can't
take a pasted image** — they only take text. shotwatch bridges that gap automatically: when you take
a screenshot, it puts the screenshot's **file path** on your clipboard. You press `Ctrl+V`, the tool
reads the file from disk. Done — no saving paths by hand, no extra steps.

```
Take a screenshot   →   (path is already on your clipboard)   →   Ctrl+V into Claude
```

Each screenshot gets its own path — nothing is overwritten, so you can paste several in a row.

## Everything it handles

- **Plain screenshot** (`Win+PrtScn`) → path on the clipboard.
- **Annotate then Save** (Snipping Tool markup → Save) → path to the marked-up file.
- **Annotate then Copy** (markup → Copy, *no save*) → it saves the copied image for you and gives the path.
- **Copy the same thing again** (Snipping Tool's Copy re-puts the raw image) → re-asserts the path, so it always pastes.
- **Re-save the same file** (more annotations, same name) → re-fires; you're not stuck.
- **Several in a row** → each has its own path.
- **Crashes / sleep / reboot** → it restarts itself within seconds, and on every login (see *Stays alive*).

## Install (no admin needed)

1. Download/clone this folder.
2. Right-click **`install.ps1`** → *Run with PowerShell*
   (or: `powershell -ExecutionPolicy Bypass -File install.ps1`)

That copies the scripts to `%LOCALAPPDATA%\shotwatch`, starts them now, and auto-runs on every login.
Take a screenshot and paste — that's the whole setup.

**Uninstall:** right-click `uninstall.ps1` → *Run with PowerShell*.

## Path for Claude, image for chats — automatically (`follow` mode)

The hard part: a terminal wants the **path**, but a chat (Discord) or image app wants the **picture** —
and an image sitting on the clipboard makes terminals intermittently paste *nothing*. You can't put
both and have each work.

The default **`follow`** mode solves it by reacting to **where you're about to paste**: it keeps the
**path** on the clipboard, but the instant you focus an app from `$ImageApps` (Discord, browser,
Paint, Blender…) it swaps to the **image**, and swaps back to the path when you focus your IDE. So
`Ctrl+V` gives Claude the path and Discord the picture — no manual switching. (It only swaps while
*your* screenshot is still on the clipboard, so it never clobbers something else you copied.)

Other `$ImageMode` values if you prefer fixed behavior:

| `$ImageMode` | Claude / terminal | Discord / image app | Browser search bar |
| --- | --- | --- | --- |
| `follow` *(default)* | path ✅ | image ✅ | image (it's an image app) |
| `never` | path ✅ | path (drag the file for the image) | path |
| `both` | path (occasionally flaky) | image | path |
| `always` | — (can't read it) | image | image |
| `smart` | path when your IDE is focused | image otherwise | depends on focus |

## Stays alive (the "supervisor")

Two small background scripts:

- **`shotwatch.ps1`** — the *watcher*. The actual worker.
- **`shotwatch-run.ps1`** — the *supervisor*. Its only job is to keep the watcher running: if the
  watcher ever stops (clipboard hiccup, waking from sleep, etc.), it relaunches it within a few
  seconds. The supervisor does nothing risky itself, so it stays up.

On login, Windows starts the supervisor, the supervisor starts the watcher. A single crash never
leaves you stranded.

## How it works

A loop checks two things and puts the path on the clipboard via a sticky re-assert (so Windows' own
"image copied" can't knock it off):

1. **Folder watch** — a new or re-saved file in your Screenshots folder.
2. **Clipboard watch** — an image you *copied* with no file yet (annotated snip → Copy). It saves
   that image as `clip_<time>.png`, then hands off the path.

It only acts while your editor (`rider64` by default) is running, so it never touches your clipboard
during unrelated work. No network, no admin, no compiled binary — just readable PowerShell.

The top of `shotwatch.ps1` has a full `HOW IT WORKS` comment explaining each internal guard.

## Configure

Edit the **CONFIG** block at the top of `shotwatch.ps1`, then re-run `install.ps1`:

- **`$GuardProcesses`** — only act while one of these apps is running. EXE name without `.exe`.
  `@()` = always. Examples: `rider64` (Rider), `idea64` (IntelliJ), `pycharm64`, `webstorm64`,
  `clion64`, `goland64`, `Code` (VS Code), `WindowsTerminal`.
- **`$ImageMode`** — `follow` (default), `never`, `both`, `always`, `smart` — see the table above.
- **`$ImageApps`** — in `follow` mode, focusing one of these swaps the clipboard to the image (EXE
  name without `.exe`). Add your chat/image apps here.
- **`$WatchClipboard`** — `true` (default) makes annotate-then-Copy work. `false` = folder only.
- **`$WatchFolder`** — blank = auto-detect the Windows Screenshots folder. Or set a path.
- **`$ClipKeepDays`** — auto-delete shotwatch's own `clip_*.png` after N days (default `1`; `0` = keep
  forever). Only ever touches files it created.
- **`$PollMs`** — folder poll interval in ms (default `200`).
- **`$DebugLog`** — `true` writes `shotwatch.log` next to the script for troubleshooting.

> Tip: `Win+PrtScn` saves a screenshot to the folder. `Win+Shift+S` snips to the clipboard
> (annotate-then-Copy is covered too).

## Optional: bulletproof watchdog (needs admin)

The supervisor covers crashes of the *watcher*. To survive even the *supervisor* being killed, run
**`install-watchdog.ps1` as Administrator** once — it registers a Windows Scheduled Task that
relaunches the supervisor if it's ever gone. Optional; the normal install is already self-healing.

## Branches

- **`main`** — the polled version (what `install.ps1` ships). Battle-tested.
- **`event-clipboard`** — experimental: reacts to clipboard changes via a real
  `AddClipboardFormatListener` event instead of polling (zero lag). Same logic otherwise. Try it with
  `git checkout event-clipboard` then re-run `install.ps1`; `git checkout main` + re-run to revert.

## Requirements

Windows 10/11, Windows PowerShell 5.1 (built in).

## License

MIT — see [LICENSE](LICENSE).
