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
$script:AppVersion = '3.3.3'
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

$script:Findings = [System.Collections.Generic.List[object]]::new()
$script:SystemCount = 0
$script:ScannedCount = 0

# Well-known legitimate mods/libraries are scanned but their results are not shown.
$script:KnownLegitMods = @(
    'cloth-config','clothconfig','entityculling','collective','krypton','lithium',
    'sodium','modernfix','voicechat','simplevoicechat','worldedit','xaero',
    'journeymap','fabric-api','fabricapi','fabric-language-kotlin','modmenu',
    'immediatelyfast','ferritecore','c2me','appleskin','dynamic-fps','fpsdisplay',
    'exordium','freelook','fzzy_config','fzzyconfig','malilib','moreculling',
    'mousetweaks','noisium','placeholder-api','shulkerboxtooltip','silicon',
    'threadtweak','ukulib','ukus-armor-hud','welcomemessage','chatgamehelper',
    'yet_another_config_lib','yacl','gamma-utils','gammautils','marlows',
    'crystaloptimizer','essential','baritone','iris','indigo','sodium-extra',
    'lithium-fabric','krypton-0','worldedit-mod'
)

function Test-LyraKnownLegit {
    param([string]$Name)
    $lower = [string]$Name
    if (-not $lower) { return $false }
    $lower = $lower.ToLowerInvariant()
    foreach ($entry in $script:KnownLegitMods) {
        if ($lower.Contains($entry)) { return $true }
    }
    return $false
}

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
        $headers = @{ 'User-Agent' = 'ProjectLyra-ModScanner/3.3.3' }
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

function Invoke-LyraFileScan {
    param([string]$Path, [string]$DisplayName)

    $hits = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($sig in Find-LyraSignatures -Text $DisplayName) { [void]$hits.Add($sig) }

    try {
        $info = [System.IO.FileInfo]::new($Path)
        if ($info.Length -le 209715200) {
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $isZip = ($bytes.Length -ge 2 -and $bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B)

            if ($isZip) {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
                foreach ($entry in $zip.Entries) {
                    foreach ($sig in Find-LyraSignatures -Text $entry.FullName) { [void]$hits.Add($sig) }
                    if ($entry.Length -eq 0) { continue }
                    try {
                        $s = $entry.Open()
                        $reader = [System.IO.StreamReader]::new($s, [System.Text.Encoding]::ASCII, $true, 65536)
                        $text = $reader.ReadToEnd()
                        $reader.Dispose()
                        foreach ($sig in Find-LyraSignatures -Text $text) { [void]$hits.Add($sig) }
                    }
                    catch { }
                }
                $zip.Dispose()
            }
            else {
                $text = [System.Text.Encoding]::ASCII.GetString($bytes)
                foreach ($sig in Find-LyraSignatures -Text $text) { [void]$hits.Add($sig) }
            }
        }
    }
    catch { }

    return @($hits)
}

function Add-LyraFinding {
    param([string]$Path, [string]$DisplayName)
    if ($ReportPath -and $Path) {
        try {
            if ([System.IO.Path]::GetFullPath($Path) -eq [System.IO.Path]::GetFullPath($ReportPath)) { return }
        }
        catch { }
    }
    $sigs = @(Invoke-LyraFileScan -Path $Path -DisplayName $DisplayName)
    if ($sigs.Count -eq 0) { return }
    if (Test-LyraKnownLegit -Name $DisplayName) { return }
    $script:Findings.Add([pscustomobject]@{
        File       = $DisplayName
        Signatures = ($sigs -join ', ')
    })
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

$loadedFiles = [System.Collections.Generic.List[string]]::new()
$mcProcesses = @()
$activeModFolders = @()
$script:modFolders = @()
$modeLabel = if ($Mode -eq 'Memory') { 'Memory (running instance)' } else { 'Disk' }

if ($Mode -eq 'Memory') {
    Add-Type -TypeDefinition $script:memSource -ErrorAction SilentlyContinue

    $mcProcesses = @(Get-LyraMinecraftProcesses)
    if ($mcProcesses.Count -eq 0) {
        Write-Host 'No running Minecraft instance found.' -ForegroundColor Yellow
        exit 1
    }

    $activeModFolders = @(Get-LyraActiveInstanceModsFolders -Processes $mcProcesses)

    foreach ($proc in $mcProcesses) {
        foreach ($jar in @(Get-LyraClasspathJars -CommandLine $proc.CommandLine)) {
            if (-not $loadedFiles.Contains($jar)) { $loadedFiles.Add($jar) }
        }
        try {
            foreach ($mapped in @([LyraMemReader]::GetMappedFiles([int]$proc.ProcessId))) {
                if ($mapped -match '\.jar$' -and (Test-Path -LiteralPath $mapped) -and -not $loadedFiles.Contains($mapped)) {
                    $loadedFiles.Add($mapped)
                }
            }
        }
        catch { }
    }

    # PrismLauncher / Fabric load mods from the instance folder, not the classpath.
    foreach ($folder in $activeModFolders) {
        Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $loadedFiles.Contains($_.FullName)) { $loadedFiles.Add($_.FullName) }
        }
    }
    $script:modFolders = $activeModFolders

    if ($loadedFiles.Count -eq 0) {
        Write-Host 'No files found for the running instance.' -ForegroundColor Yellow
        exit 1
    }
}
else {
    $script:modFolders = @(Get-LyraModsFolders -Override $ModsPath)
}

if ($Mode -eq 'Memory') {
    $isModFile = {
        param($p)
        if ($p -match '[\\/](mods|mod)[\\/]') { return $true }
        foreach ($folder in $script:modFolders) {
            if ($p.StartsWith($folder, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    $modFiles = @($loadedFiles | Where-Object { & $isModFile $_ })
    $systemFiles = @($loadedFiles | Where-Object { -not (& $isModFile $_) })
    $script:SystemCount = $systemFiles.Count
    $script:ScannedCount = $modFiles.Count

    $current = 0
    foreach ($filePath in $modFiles) {
        $current++
        Write-Host ("Searching mods [{0}/{1}]" -f $current, $modFiles.Count)
        Add-LyraFinding -Path $filePath -DisplayName (Split-Path $filePath -Leaf)
    }
}
else {
    $diskFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($folder in $script:modFolders) {
        Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $diskFiles.Add($_)
        }
    }
    $script:ScannedCount = $diskFiles.Count

    $current = 0
    foreach ($file in $diskFiles) {
        $current++
        Write-Host ("Searching mods [{0}/{1}]" -f $current, $diskFiles.Count)
        Add-LyraFinding -Path $file.FullName -DisplayName $file.Name
    }
}

Write-Host ''
if ($script:Findings.Count -eq 0) {
    Write-Host 'No cheat strings found.' -ForegroundColor Green
}
else {
    Write-Host '--- CHEAT STRINGS FOUND ---' -ForegroundColor Red
    $script:Findings | Sort-Object File | Format-Table File, Signatures -AutoSize -Wrap | Out-Host
}

if (-not $ReportPath) {
    $ReportPath = Join-Path ([System.IO.Path]::GetTempPath()) 'ProjectLyra-ScanReport.txt'
}
try {
    $lines = @('PROJECT LYRA - CHEAT STRING SCAN', ('Date: {0}' -f (Get-Date)), ('Mode: {0}' -f $modeLabel), '')
    if ($script:Findings.Count -eq 0) {
        $lines += 'No cheat strings found.'
    }
    else {
        $lines += '--- CHEAT STRINGS FOUND ---'
        foreach ($f in $script:Findings) { $lines += ('{0} | {1}' -f $f.File, $f.Signatures) }
    }
    [System.IO.File]::WriteAllLines($ReportPath, $lines)
}
catch { }

[void][System.Console]::ReadLine()
