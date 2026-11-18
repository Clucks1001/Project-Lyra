# Project Lyra

Our own screen sharing tool for Windows. All-in-one: capture + view.

**Version: 3.3.0** (over 3.1.4 - see versioning notes below)

## How it works

- **Share mode**: captures the primary screen (or a specific window by title via `user32` enumeration) via GDI+, encodes as JPEG, frames it as `int32 byte length + JPEG bytes`, and streams over TCP.
- **View mode**: TCP listener, accepts the sender, decodes frames, displays in a borderless WinForms window with an FPS counter and a fullscreen toggle.

## Tough mode

- `-Hard` (Share): red `LYRA GUARD` border + watermark on every frame.

## Cheat client detection

- Share mode looks for cheat strings **one client at a time** (via `-WindowTitle`).
- Built-in cheat string list + optional `-CheatStringsFile` override.
- On match: flags `CHEAT CLIENT MATCHED` and auto-engages tough mode.

## Versioning

- Current version: **3.3.0** (over 3.1.4).
- Every retry / update bumps the version:
  - Small patches -> `3.3.1`
  - Bigger ish changes -> `3.4.0`
  - Massive ones -> `4.0.0`

## Credits

- **Lyra** - creator (discord: `echo_ducky`)
- Built on GDI+ and pure stubbornness
- Powered by PowerShell, .NET, and bad decisions

## Run

### Installer (local):

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\screenshare\installer.ps1
```

### Remote launcher (GitHub one-liner - requires pushing to GitHub):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/<owner>/<repo>/refs/heads/main/screenshare/remote.ps1')"
```

`remote.ps1` downloads `ScreenShare.ps1` from that raw URL and launches it via menu.

### Direct:

View mode - on the machine you want to see the screen:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\screenshare\ScreenShare.ps1 -Mode View -Port 19732
```

Share mode - on the machine doing the sharing:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\screenshare\ScreenShare.ps1 -Mode Share -ReceiverHost 192.168.1.50 -Port 19732 -Fps 10 -WindowTitle 'Chrome'
```

Options:
- `-WindowTitle` (Share): capture a window by exact title match (e.g. `Chrome`). Empty = primary screen.
- `-Quality` (Share): JPEG quality 1-100 (default 80).
- `-Fps` (Share): frame rate (default 10).
- `-Hard` (Share): tough mode - red `LYRA GUARD` border + watermark.
- `-CheatStringsFile` (Share): optional path to a text file of cheat strings (one per line). Falls back to the built-in list when empty.
- `-WindowWidth` / `-WindowHeight` (View): receiver window size (default 1280x720).

## Status / TODO

- [x] Primary screen capture
- [x] Window capture by title
- [x] JPEG encoding
- [x] Receiver UI: borderless, FPS counter, fullscreen toggle
- [x] Installer-style launcher
- [x] Tough mode + feminine branding (Project Lyra)
- [x] Cheat string scanning + auto-tough
- [x] Versioning scheme + hardcoded credits
- [ ] UDP instead of TCP for lower latency
- [ ] Multi-client support / reconnection
- [ ] Audio / clipboard sharing
- [ ] Real cheat client / hack detection (beyond the LYRA GUARD overlay)
- [ ] Better window matching (partial title match, process name)

## Why not just run theirs?

You were right to be suspicious. The installer they gave you was a launcher that `Invoke-Expression`d remote scripts straight into PowerShell - and the GitHub repo now returns 404. Building your own version means the capture/streaming code is fully under your control.
