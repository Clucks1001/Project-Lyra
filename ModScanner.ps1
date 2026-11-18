<#
.SYNOPSIS
    Project Lyra - automatic Minecraft cheat scanner (running instance).

.DESCRIPTION
    Default mode scans ONLY the RUNNING Minecraft instance:
      - Finds javaw.exe / java.exe processes running Minecraft
      - Reads the process command line to locate that instance's mods folder
      - Also checks the Java classpath for launchers that list mods there
      - Scans only those JARs; other Minecraft installs are ignored

    Use -Mode Disk to scan every Minecraft mods folder on disk instead.

    This tool only READS process information and mod files. It does not upload,
    transmit, inject, or modify anything. Results print here and save locally.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ModScanner.ps1

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ModScanner.ps1 -Mode Disk -ModsPath "D:\Games\.minecraft\mods"
#>
param(
    [ValidateSet('Memory', 'Disk')] [string]$Mode = 'Memory',
    [string]$ModsPath = '',
    [switch]$NoNetwork,
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:AppName = 'Project Lyra'
$script:AppVersion = '3.3.2'
$script:CreatorName = 'Lyra'
$script:CreatorDiscord = 'echo_ducky'

# Strong cheat-client indicators. Any one of these is enough to flag.
$script:HighRiskSignatures = @(
    'aimassist','aimbot','killaura','killaur','autocrystal','autoanchor','autototem',
    'autopot','autoarmor','autohitcrystal','autodoublehand','inventorytotem','shieldbreaker',
    'jumpreset','pingspoof','selfdestruct','triggerbot','velocitymod','axespam','webmacro',
    'fastplace','antivoid','nofall','noreach','reachmod','wallhack','spinbot','speedhack',
    'autoclicker','autofish','autoeat','autowalk','bedaura','crystalaura','wurst','dorta',
    'liquidbounce','radiation','huzuni','pytclient','futureclient','aristotle',
    'hypixelanticheat','anticheatbypass','cheatmanager','guiclick','noclip','ghosthand',
    'multitask','autoblock','bowboost','killaurabot','totempop','fastbow'
)

# Generic words that also appear in legitimate mods. Several together are suspicious.
$script:WeakSignatures = @(
    'hitboxes','xray','tracers','storageesp','nametags','radar','freecam','scaffold',
    'modulemanager','clickgui','crystaloptimizer','velocity'
)

$script:CheatSignatures = @($script:HighRiskSignatures) + @($script:WeakSignatures)

$script:Verified = [System.Collections.Generic.List[object]]::new()
$script:Flagged = [System.Collections.Generic.List[object]]::new()
$script:Unknown = [System.Collections.Generic.List[object]]::new()
$script:Hidden = [System.Collections.Generic.List[object]]::new()
$script:SystemCount = 0

function Write-LyraHeader {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '   PROJECT LYRA  //  MOD CHEAT SCANNER'
    Write-Host ("   v{0}  -  creator: {1} ({2})" -f $script:AppVersion, $script:CreatorName, $script:CreatorDiscord)
    Write-Host '============================================================'
    Write-Host ''
}

function Get-LyraModsFolders {
    param([string]$Override)
    $folders = [System.Collections.Generic.List[string]]::new()
    if ($Override) {
        if (Test-Path -LiteralPath $Override) { $folders.Add($Override) }
        return $folders
    }
    $roots = @(
        (Join-Path $env:APPDATA '.minecraft'),
        (Join-Path $env:USERPROFILE '.minecraft'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\minecraftpe\mods')
    )
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $candidate = Join-Path $root 'mods'
        if (Test-Path -LiteralPath $candidate) { $folders.Add($candidate) }
        $versionsDir = Join-Path $root 'versions'
        if (Test-Path -LiteralPath $versionsDir) {
            Get-ChildItem -LiteralPath $versionsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $vMods = Join-Path $_.FullName 'mods'
                if (Test-Path -LiteralPath $vMods) { $folders.Add($vMods) }
            }
        }
    }

    # Third-party launchers keep each instance's mods in its own folder.
    $launcherInstanceRoots = @(
        (Join-Path $env:APPDATA 'PrismLauncher\instances'),
        (Join-Path $env:APPDATA 'MultiMC\instances'),
        (Join-Path $env:APPDATA 'CurseForge\Minecraft\Instances'),
        (Join-Path $env:APPDATA 'com.modrinth.theseus\profiles'),
        (Join-Path $env:APPDATA 'GDLauncher\instances')
    )
    foreach ($instanceRoot in $launcherInstanceRoots) {
        if (-not $instanceRoot -or -not (Test-Path -LiteralPath $instanceRoot)) { continue }
        Get-ChildItem -LiteralPath $instanceRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($rel in @('mods', 'minecraft\mods', '.minecraft\mods')) {
                $instanceMods = Join-Path $_.FullName $rel
                if ((Test-Path -LiteralPath $instanceMods) -and -not $folders.Contains($instanceMods)) {
                    $folders.Add($instanceMods)
                }
            }
        }
    }
    return $folders
}

function Get-LyraFirstRegexGroup {
    param([System.Text.RegularExpressions.Match]$Match)
    foreach ($group in ($Match.Groups | Select-Object -Skip 1)) {
        if ($group.Success -and $group.Value) { return [string]$group.Value }
    }
    return ''
}

function Get-LyraActiveInstanceModsFolders {
    param([object[]]$Processes)

    $folders = [System.Collections.Generic.List[string]]::new()
    $tokenPattern = '"([^"]+)"|''([^'']+)''|([^\s]+)'

    foreach ($proc in $Processes) {
        $cl = [string]$proc.CommandLine
        $tokens = [System.Collections.Generic.List[string]]::new()
        foreach ($m in [regex]::Matches($cl, $tokenPattern)) {
            $token = Get-LyraFirstRegexGroup -Match $m
            if ($token) { $tokens.Add($token.Trim()) }
        }

        $roots = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $token = $tokens[$i]
            $value = ''

            if ($token -match '^--gameDir=(.*)$') {
                $value = $Matches[1]
            }
            elseif ($token -eq '--gameDir' -and ($i + 1) -lt $tokens.Count) {
                $value = $tokens[$i + 1]
            }
            elseif ($token -match '^-Duser\.dir=(.*)$') {
                $value = $Matches[1]
            }
            elseif ($token -match '^-Djava\.library\.path=(.*)$') {
                $value = $Matches[1]
            }

            if (-not $value) { continue }
            if ($value -match '[\\/]natives$') { $value = Split-Path -Path $value -Parent }
            $roots.Add($value)
        }

        foreach ($root in $roots) {
            $normalized = $root -replace '/', '\'
            $candidates = @(
                (Join-Path $normalized 'mods'),
                (Join-Path $normalized 'minecraft\mods'),
                (Join-Path $normalized '.minecraft\mods')
            )
            foreach ($candidate in $candidates) {
                if ((Test-Path -LiteralPath $candidate) -and -not $folders.Contains($candidate)) {
                    $folders.Add($candidate)
                }
            }
        }
    }
    return $folders
}

function Get-LyraSha1 {
    param([string]$Path)
    try {
        $sha = [System.Security.Cryptography.SHA1]::Create()
        $fs = [System.IO.File]::OpenRead($Path)
        $hash = $sha.ComputeHash($fs)
        $fs.Dispose(); $sha.Dispose()
        return (-join ($hash | ForEach-Object { $_.ToString('x2') }))
    }
    catch { return '' }
}

function Test-LyraModrinth {
    param([string]$Hash)
    if ($NoNetwork -or [string]::IsNullOrWhiteSpace($Hash)) { return $null }
    try {
        $uri = 'https://api.modrinth.com/v2/version_file/{0}?algorithm=sha1' -f $Hash
        $headers = @{ 'User-Agent' = 'ProjectLyra-ModScanner/3.3.2' }
        $v = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 8 -ErrorAction Stop
        if ($v -and $v.project_id) {
            try {
                $p = Invoke-RestMethod -Uri ('https://api.modrinth.com/v2/project/{0}' -f $v.project_id) -Headers $headers -TimeoutSec 8 -ErrorAction Stop
                if ($p.title) { return [string]$p.title }
            }
            catch { }
            return [string]$v.project_id
        }
    }
    catch { }
    return $null
}

function Find-LyraSignatures {
    param([string]$Text)
    $lower = $Text.ToLowerInvariant()
    $hits = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($sig in $script:CheatSignatures) {
        if ($lower.Contains($sig)) { [void]$hits.Add($sig) }
    }
    return @($hits)
}

function Invoke-LyraJarScan {
    param([string]$Path, [string]$DisplayName)
    $nameHits = Find-LyraSignatures -Text $DisplayName
    $contentHits = [System.Collections.Generic.HashSet[string]]::new()
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        foreach ($entry in $zip.Entries) {
            foreach ($sig in Find-LyraSignatures -Text $entry.FullName) { [void]$contentHits.Add($sig) }
            if ($entry.Length -le 0 -or $entry.Length -gt 4000000) { continue }
            if ($entry.FullName -notmatch '\.(class|json|toml|info|txt|mf|yml|yaml|cfg)$') { continue }
            try {
                $s = $entry.Open()
                $reader = [System.IO.StreamReader]::new($s, [System.Text.Encoding]::ASCII, $true, 65536)
                $text = $reader.ReadToEnd()
                $reader.Dispose()
                foreach ($sig in Find-LyraSignatures -Text $text) { [void]$contentHits.Add($sig) }
            }
            catch { }
        }
        $zip.Dispose()
    }
    catch { }
    $all = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($h in $nameHits) { [void]$all.Add($h) }
    foreach ($h in $contentHits) { [void]$all.Add($h) }
    return @($all)
}

function Add-LyraVerdict {
    param([string]$Path, [string]$DisplayName)
    $hash = Get-LyraSha1 -Path $Path
    $sigs = @(Invoke-LyraJarScan -Path $Path -DisplayName $DisplayName)
    $modrinthName = Test-LyraModrinth -Hash $hash
    $highHits = @($sigs | Where-Object { $script:HighRiskSignatures -contains $_ })
    $weakHits = @($sigs | Where-Object { $script:WeakSignatures -contains $_ })

    # Well-known legitimate families often contain generic words like "radar" or "nametags".
    $knownLegit = @('xaero', 'journeymap', 'worldedit', 'voicechat', 'entityculling',
                    'collective', 'sodium', 'lithium', 'krypton', 'modernfix',
                    'marlows', 'crystaloptimizer', 'essential', 'fabric-api')
    $isKnownLegit = $false
    foreach ($name in $knownLegit) {
        if ($DisplayName -match [regex]::Escape($name)) { $isKnownLegit = $true; break }
    }

    if ($modrinthName) {
        $script:Verified.Add([pscustomobject]@{ File = $DisplayName; Source = $modrinthName; Signatures = ($sigs -join ', ') })
        Write-Host ('        -> VERIFIED on Modrinth: {0}' -f $modrinthName) -ForegroundColor Green
    }
    elseif ($highHits.Count -gt 0 -or ($weakHits.Count -ge 3 -and -not $isKnownLegit)) {
        $script:Flagged.Add([pscustomobject]@{ File = $DisplayName; Signatures = ($sigs -join ', '); Hash = $hash })
        Write-Host ('        -> FLAGGED: {0}' -f ($sigs -join ', ')) -ForegroundColor Red
    }
    else {
        $note = if ($weakHits.Count -gt 0) { 'weak signals only' } else { 'no strong signals' }
        $script:Unknown.Add([pscustomobject]@{ File = $DisplayName; Hash = $hash; Signatures = ($sigs -join ', ') })
        Write-Host ("        -> UNKNOWN (not on Modrinth, {0})" -f $note) -ForegroundColor Yellow
    }
}

# ---------- MEMORY MODE ----------

$script:memSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class LyraMemReader {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr VirtualQueryEx(IntPtr process, IntPtr address, out MEMORY_BASIC_INFORMATION info, uint length);
    [DllImport("psapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetMappedFileName(IntPtr process, IntPtr address, StringBuilder name, uint size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint QueryDosDevice(string device, StringBuilder target, uint size);

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public IntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }

    public static List<string> GetMappedFiles(int pid) {
        List<string> found = new List<string>();
        IntPtr hProc = OpenProcess(0x1000 | 0x0400, false, pid);
        if (hProc == IntPtr.Zero) return found;

        Dictionary<string, string> drives = new Dictionary<string, string>();
        for (char c = 'A'; c <= 'Z'; c++) {
            string dev = c + ":";
            StringBuilder target = new StringBuilder(512);
            if (QueryDosDevice(dev, target, (uint)target.Capacity) > 0) {
                drives[target.ToString().ToLowerInvariant()] = dev + "\\";
            }
        }

        try {
            IntPtr addr = IntPtr.Zero;
            int size = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
            StringBuilder sb = new StringBuilder(1024);
            while (true) {
                MEMORY_BASIC_INFORMATION mbi;
                IntPtr ret = VirtualQueryEx(hProc, addr, out mbi, (uint)size);
                if (ret == IntPtr.Zero) break;
                if (mbi.State == 0x1000 && mbi.Type == 0x20000) {
                    uint len = GetMappedFileName(hProc, mbi.BaseAddress, sb, (uint)sb.Capacity);
                    if (len > 0) {
                        string raw = sb.ToString();
                        string converted = raw;
                        foreach (KeyValuePair<string, string> kv in drives) {
                            if (raw.ToLowerInvariant().StartsWith(kv.Key)) {
                                converted = kv.Value + raw.Substring(kv.Key.Length);
                                break;
                            }
                        }
                        if (!found.Contains(converted)) found.Add(converted);
                    }
                    sb.Length = 0;
                }
                long next = mbi.BaseAddress.ToInt64() + mbi.RegionSize.ToInt64();
                if (next <= addr.ToInt64()) break;
                addr = new IntPtr(next);
            }
        }
        finally { CloseHandle(hProc); }
        return found;
    }
}
'@

function Get-LyraMinecraftProcesses {
    $all = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('javaw.exe', 'java.exe') -and $_.CommandLine }
    return @($all | Where-Object {
        $_.CommandLine -match 'minecraft|\.minecraft|net\.minecraft|net\.fabricmc|net\.forge|cp\s+.*mods'
    })
}

function Get-LyraClasspathJars {
    param([string]$CommandLine)
    $jars = [System.Collections.Generic.List[string]]::new()
    $m = [regex]::Match($CommandLine, '(?:-cp|-classpath)\s+"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($CommandLine, '(?:-cp|-classpath)\s+([^\s]+)') }
    if ($m.Success) {
        foreach ($part in ($m.Groups[1].Value -split ';')) {
            if ($part -match '\.jar$' -and (Test-Path -LiteralPath $part)) { $jars.Add($part) }
        }
    }
    return $jars
}

Write-LyraHeader

$loadedJars = [System.Collections.Generic.List[string]]::new()
$mcProcesses = @()
$activeModFolders = @()
$script:modFolders = @()
$modeLabel = if ($Mode -eq 'Memory') { 'Memory (running instance)' } else { 'Disk' }

if ($Mode -eq 'Memory') {
    Add-Type -TypeDefinition $script:memSource -ErrorAction SilentlyContinue

    $mcProcesses = @(Get-LyraMinecraftProcesses)
    if ($mcProcesses.Count -eq 0) {
        Write-Host 'No running Minecraft instance found.' -ForegroundColor Yellow
        Write-Host 'Open Minecraft first, then run this again.' -ForegroundColor Yellow
        Write-Host 'To scan a folder manually, use -Mode Disk.' -ForegroundColor Yellow
        exit 1
    }

    Write-Host ("Found {0} running Minecraft process(es)." -f $mcProcesses.Count)
    $activeModFolders = @(Get-LyraActiveInstanceModsFolders -Processes $mcProcesses)
    if ($activeModFolders.Count -gt 0) {
        Write-Host ("Active instance mods folder(s): {0}" -f ($activeModFolders -join ', '))
    }
    else {
        Write-Host 'Active instance mods folder: not found (classic launcher may still work).' -ForegroundColor Yellow
    }

    foreach ($proc in $mcProcesses) {
        Write-Host ("  PID {0}: {1}" -f $proc.ProcessId, (Split-Path $proc.ExecutablePath -Leaf))
        foreach ($jar in @(Get-LyraClasspathJars -CommandLine $proc.CommandLine)) {
            if (-not $loadedJars.Contains($jar)) { $loadedJars.Add($jar) }
        }
        try {
            foreach ($mapped in @([LyraMemReader]::GetMappedFiles([int]$proc.ProcessId))) {
                if ($mapped -match '\.jar$' -and (Test-Path -LiteralPath $mapped) -and -not $loadedJars.Contains($mapped)) {
                    $loadedJars.Add($mapped)
                }
            }
        }
        catch { }
    }

    # PrismLauncher / Fabric load mods from the instance folder, not the classpath.
    foreach ($folder in $activeModFolders) {
        Get-ChildItem -LiteralPath $folder -Filter '*.jar' -File -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $loadedJars.Contains($_.FullName)) { $loadedJars.Add($_.FullName) }
        }
    }
    $script:modFolders = $activeModFolders

    if ($loadedJars.Count -eq 0) {
        Write-Host 'No JARs found for the running instance.' -ForegroundColor Yellow
        exit 1
    }
    Write-Host ("JAR(s) from this instance: {0}" -f $loadedJars.Count)
    Write-Host ''
}
else {
    $script:modFolders = @(Get-LyraModsFolders -Override $ModsPath)
}

if ($Mode -eq 'Memory') {
    $isModJar = {
        param($p)
        if ($p -match '[\\/](mods|mod)[\\/]') { return $true }
        foreach ($folder in $script:modFolders) {
            if ($p.StartsWith($folder, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    $modJars = @($loadedJars | Where-Object { & $isModJar $_ })
    $systemJars = @($loadedJars | Where-Object { -not (& $isModJar $_) })
    $script:SystemCount = $systemJars.Count

    Write-Host ("Mod JARs to analyze: {0}" -f $modJars.Count)
    Write-Host ("System/library JARs (skipped): {0}" -f $systemJars.Count)
    Write-Host ''

    $current = 0
    foreach ($jarPath in $modJars) {
        $current++
        $display = Split-Path $jarPath -Leaf
        Write-Host ("[{0}/{1}] {2}  (active instance)" -f $current, $modJars.Count, $display)
        Add-LyraVerdict -Path $jarPath -DisplayName $display

        if (-not (Test-Path -LiteralPath $jarPath)) {
            $script:Hidden.Add([pscustomobject]@{ File = $display; Reason = 'Loaded by the instance but deleted from disk' })
            Write-Host '        -> HIDDEN/SELF-DESTRUCT: file is gone from disk' -ForegroundColor Magenta
        }
    }
}
else {
    $diskJars = [System.Collections.Generic.List[object]]::new()
    foreach ($folder in $script:modFolders) {
        Get-ChildItem -LiteralPath $folder -Filter '*.jar' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $diskJars.Add($_)
        }
    }
    Write-Host ("Scanning mods folder(s): {0}" -f ($script:modFolders -join ', '))
    $current = 0
    foreach ($jar in $diskJars) {
        $current++
        Write-Host ("[{0}/{1}] {2}" -f $current, $diskJars.Count, $jar.Name)
        Add-LyraVerdict -Path $jar.FullName -DisplayName $jar.Name
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host '  SCAN REPORT'
Write-Host '============================================================'
Write-Host ("SYSTEM JARs skipped: {0}" -f $script:SystemCount)
Write-Host ("VERIFIED: {0}   FLAGGED: {1}   UNKNOWN: {2}   HIDDEN: {3}" -f $script:Verified.Count, $script:Flagged.Count, $script:Unknown.Count, $script:Hidden.Count)
Write-Host ''

if ($script:Hidden.Count -gt 0) {
    Write-Host '--- HIDDEN / SELF-DESTRUCT ---' -ForegroundColor Magenta
    $script:Hidden | Format-Table File, Reason -AutoSize | Out-Host
}
if ($script:Flagged.Count -gt 0) {
    Write-Host '--- FLAGGED (possible cheat mods) ---' -ForegroundColor Red
    $script:Flagged | Format-Table File, Signatures, Hash -AutoSize -Wrap | Out-Host
}
if ($script:Unknown.Count -gt 0) {
    Write-Host '--- UNKNOWN (manual review) ---' -ForegroundColor Yellow
    $script:Unknown | Format-Table File, Signatures, Hash -AutoSize -Wrap | Out-Host
}
if ($script:Verified.Count -gt 0) {
    Write-Host '--- VERIFIED (legitimate mods) ---' -ForegroundColor Green
    $script:Verified | Format-Table File, Source -AutoSize | Out-Host
}

if (-not $ReportPath) {
    $ReportPath = Join-Path ([System.IO.Path]::GetTempPath()) 'ProjectLyra-ScanReport.txt'
}
try {
    $lines = @('PROJECT LYRA - MOD SCAN REPORT', ('Date: {0}' -f (Get-Date)), ('Mode: {0}' -f $modeLabel), '')
    $lines += ('SYSTEM JARs skipped: {0}' -f $script:SystemCount)
    $lines += ('VERIFIED: {0}  FLAGGED: {1}  UNKNOWN: {2}  HIDDEN: {3}' -f $script:Verified.Count, $script:Flagged.Count, $script:Unknown.Count, $script:Hidden.Count)
    $lines += ''
    $lines += '--- HIDDEN / SELF-DESTRUCT ---'
    foreach ($h in $script:Hidden) { $lines += ('{0} | {1}' -f $h.File, $h.Reason) }
    $lines += ''
    $lines += '--- FLAGGED ---'
    foreach ($f in $script:Flagged) { $lines += ('{0} | {1} | {2}' -f $f.File, $f.Signatures, $f.Hash) }
    $lines += ''
    $lines += '--- UNKNOWN ---'
    foreach ($u in $script:Unknown) { $lines += ('{0} | {1} | {2}' -f $u.File, $u.Signatures, $u.Hash) }
    $lines += ''
    $lines += '--- VERIFIED ---'
    foreach ($v in $script:Verified) { $lines += ('{0} | {1}' -f $v.File, $v.Source) }
    [System.IO.File]::WriteAllLines($ReportPath, $lines)
    Write-Host ("Report saved to: {0}" -f $ReportPath)
}
catch {
    Write-Host ('Could not save report: {0}' -f $_.Exception.Message)
}

Write-Host ''
Read-Host 'Scan complete. Press ENTER to close'
