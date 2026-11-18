# Project Lyra

A Windows screen sharing tool with a focused, no-nonsense interface. All-in-one: capture + view.

**Version: 3.3.1**

## How it works

- **Share mode**: captures the primary screen (or a specific window by title via `user32` enumeration) with GDI+, encodes as JPEG, frames it as `int32 byte length + JPEG bytes`, and streams over TCP.
- **View mode**: TCP listener, accepts the sender, buffers frames, and displays them in a borderless window with an FPS counter, fullscreen toggle, and close button.

## Tough mode

- `-Hard` (Share): red `LYRA GUARD` border + watermark burned into every frame.

## Cheat client detection

- Share mode checks the selected client's title **one client at a time** (via `-WindowTitle`).
- Built-in string list + optional `-CheatStringsFile` override.
- On match: prints `CHEAT CLIENT MATCHED` and auto-engages tough mode.

## Versioning

- Current version: **3.3.1**
- Patch fixes / small tweaks → `3.3.2`
- Bigger changes → `3.4.0`
- Massive changes → `4.0.0`

### Changelog

- **3.3.1** — fixed View-mode listener constructor, fixed receiver/port parsing in Share mode, replaced the non-firing WPF timer with a WinForms timer, fixed window-capture drawing coordinates, formalized both launcher menus, added a branded receiver top bar.
- **3.3.0** — cheat string detection, tough mode, branding, remote launcher.

## Credits

- **Lyra** — creator (discord: `echo_ducky`)
- Built on GDI+ and pure stubbornness
- Powered by PowerShell, .NET, and bad decisions

## Run

### Auto-download from GitHub (the one-liner)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/Clucks1001/Project-Lyra/refs/heads/main/remote.ps1')"
```

`remote.ps1` downloads `ScreenShare.ps1` from the same repo, shows a formal menu, asks for the target/port, and launches a **new window** running the tool.

### Local launcher

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\screenshare\installer.ps1
```

### Direct

View mode — run on the machine you want to see:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\screenshare\ScreenShare.ps1 -Mode View -Port 19732
```

Share mode — run on the machine doing the sharing:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\screenshare\ScreenShare.ps1 -Mode Share -ReceiverHost 192.168.1.50 -Port 19732 -Fps 10 -WindowTitle 'Chrome'
```

Options:
- `-ReceiverHost` (Share): receiver IP/hostname. Accepts `host` (uses `-Port`) or `host:port`.
- `-WindowTitle` (Share): capture a window by exact title match. Empty = primary screen.
- `-Quality` (Share): JPEG quality 1-100 (default 80).
- `-Fps` (Share): frame rate (default 10).
- `-Hard` (Share): tough mode — red `LYRA GUARD` border + watermark.
- `-CheatStringsFile` (Share): path to a text file of cheat strings, one per line.
- `-Port` (View/Share): TCP port (default 19732).
- `-WindowWidth` / `-WindowHeight` (View): receiver window size (default 1280x720).

## Status

- [x] Primary screen capture
- [x] Window capture by title
- [x] JPEG encoding
- [x] Receiver UI: borderless, FPS counter, fullscreen toggle, branded top bar
- [x] Formal launcher menus (local + remote)
- [x] Tough mode + Project Lyra branding
- [x] Cheat string scanning + auto-tough
- [x] Versioning scheme + credits
- [ ] UDP transport for lower latency
- [ ] Multi-client support / reconnection
- [ ] Audio / clipboard sharing
- [ ] Deeper process-based cheat detection
