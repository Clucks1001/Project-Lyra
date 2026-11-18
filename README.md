# Project Lyra

**Version: 3.3.2** — creator: Lyra (discord: `echo_ducky`)

Project Lyra is an **automatic Minecraft cheat scanner**. Someone runs one command from GitHub, and it scans **only the Minecraft instance that is currently open** — no menu, no input, no screensharing from the tool. (You can still screenshare in your Discord call manually.)

## What it does

1. Finds the running `javaw.exe` / `java.exe` Minecraft process.
2. Reads that process's command line to locate the **open instance's** mods folder
   (PrismLauncher, MultiMC, CurseForge, Modrinth, GDLauncher, and classic `.minecraft`).
3. Scans only that instance's mod JARs (plus any JARs on the Java classpath). Other Minecraft installs are ignored.
4. For each JAR:
   - Hashes it (SHA-1) and checks **Modrinth** to see if it's a legitimate published mod.
   - Reads entry names, metadata, and class contents looking for cheat signatures.
5. Sorts every mod into:
   - **VERIFIED** — found on Modrinth, legitimate
   - **FLAGGED** — strong cheat signatures found (or several suspicious signals) and not a known mod
   - **UNKNOWN** — not on Modrinth, no strong signals (manual review)
6. Prints a report and saves it to `%TEMP%\ProjectLyra-ScanReport.txt`.

The scanner only **reads** process info and local mod files. It does not upload, transmit, inject, or modify anything.

## The one-liner (auto scan)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/Clucks1001/Project-Lyra/refs/heads/main/remote.ps1?cb=lyra332')"
```

`remote.ps1` downloads `ModScanner.ps1` from the repo (with cache-busting) and launches it immediately. The scan of the open instance starts automatically.

## Files on GitHub (root of `Clucks1001/Project-Lyra`)

| File | Purpose |
|---|---|
| `remote.ps1` | One-liner entry point — downloads and auto-runs the scanner |
| `ModScanner.ps1` | The scanner itself |
| `ScreenShare.ps1` | Old screensharing tool — kept, no longer used by the one-liner |
| `installer.ps1` | Old local screenshare launcher — kept |
| `README.md` | This file |

## Direct / manual scan

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ModScanner.ps1
```

Options:
- `-Mode Disk` — scan every discovered Minecraft mods folder instead of only the open instance
- `-ModsPath "C:\path\to\.minecraft\mods"` — scan a specific folder
- `-NoNetwork` — skip Modrinth lookups (offline; more UNKNOWN results)
- `-ReportPath "C:\path\report.txt"` — choose where the report is saved

## Versioning

- Current: **3.3.2**
- Patches → `3.3.3`, bigger changes → `3.4.0`, massive → `4.0.0`

## Status

- [x] Detect the running Minecraft instance (PrismLauncher / MultiMC / CurseForge / Modrinth / GDLauncher / classic)
- [x] Scan only the open instance's mods (not every install)
- [x] Modrinth verification by SHA-1
- [x] Cheat signature scanning inside JARs
- [x] Strong vs. weak signal scoring to reduce false positives
- [x] VERIFIED / FLAGGED / UNKNOWN verdicts
- [x] Local report file
- [ ] GUI results dashboard
- [ ] CurseForge verification
- [ ] Signature list auto-updates
