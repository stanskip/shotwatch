# Changelog

Human-readable summary of what shotwatch can do and how it got here. Newest first.
(For exact diffs, see the [commit history](https://github.com/stanskip/shotwatch/commits/main).)

## follow mode — path for Claude, image for chats
- **`follow` is now the default `$ImageMode`.** shotwatch keeps the **path** on the clipboard, but
  the moment you focus a chat/image app (Discord, browser, Paint, Blender, Unreal, Slack, Teams…)
  it swaps to the **image**, and swaps back to the path when you focus your IDE. The paste target
  decides — no manual switching. Configurable via `$ImageApps`.

## Reliable terminal paste
- **Text-only base.** An image on the clipboard makes terminals (Rider/Claude) intermittently paste
  *nothing*; the base behavior is path-only so Claude paste is rock-solid. (`follow` adds the image
  back only for image apps, by focus.)
- **Re-copy re-asserts the path.** Hitting the Snipping Tool's Copy button re-puts the raw image;
  shotwatch now re-asserts the path instead of leaving the raw image (which pasted as nothing).
- **No clipboard thrash.** Copied images aren't double-processed by the folder + clipboard watches.
- **Faster swap.** Poll dropped to 200 ms so a quick copy-then-paste doesn't beat it.

## Capture coverage
- **Annotate → Copy** (no save) works: the copied image is saved as `clip_<time>.png` and the path
  handed off. Pixel-hash dedup tells your copy from shotwatch's own clipboard writes.
- **Annotate → Save** and **re-saving the same filename** both fire (tracked by modified-time).
- **Auto-cleanup** of shotwatch's own `clip_*.png` after `$ClipKeepDays` (default 1).

## Stays alive
- **Self-healing supervisor** (`shotwatch-run.ps1`) relaunches the watcher within seconds if it ever
  dies (crash, sleep/resume). Optional admin **watchdog** (`install-watchdog.ps1`) covers even the
  supervisor.
- **Clipboard stays healthy when idle** (message pump) — fixed "first shot after a long idle failed".

## Packaging
- No-admin `install.ps1` / `uninstall.ps1`; autostarts hidden on login.
- Plain-language `README.md`, MIT `LICENSE`, architecture header in the script.
- Branches: **`main`** (polled, shipped) and **`event-clipboard`** (experimental, zero-lag clipboard
  via `AddClipboardFormatListener`).

## The original idea
- Terminal AI tools can't accept a pasted image — but they accept text, and a screenshot is a file
  with a path. shotwatch watches the Screenshots folder and puts that path on your clipboard, so
  `Ctrl+V` into Claude "just works".
