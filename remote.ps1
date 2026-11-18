<#
.SYNOPSIS
    Project Lyra - GitHub remote launcher (automatic mod cheat scanner).

.DESCRIPTION
    Fetched with a one-liner, this downloads ModScanner.ps1 from GitHub and
    launches it immediately. No menu, no input required - the scan starts
    automatically.

    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/Clucks1001/Project-Lyra/refs/heads/main/remote.ps1?cb=lyra332')"
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$owner = 'Clucks1001'
$repo = 'Project-Lyra'
$branch = 'main'
$launcherVersion = '3.3.2'
$toolUrl = "https://raw.githubusercontent.com/$owner/$repo/refs/heads/$branch/ModScanner.ps1"

Write-Host ''
Write-Host '============================================================'
Write-Host '   PROJECT LYRA  //  AUTO SCANNER LAUNCHER'
Write-Host ("   v{0}  -  creator: Lyra ({1})" -f $launcherVersion, 'echo_ducky')
Write-Host '============================================================'
Write-Host ''
Write-Host 'This will scan your local Minecraft mods folder for cheat signatures.'
Write-Host 'It only reads mod files. Nothing is uploaded or changed.'

$destDir = Join-Path ([System.IO.Path]::GetTempPath()) 'ProjectLyraScanner'
if (-not (Test-Path -LiteralPath $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
$dest = Join-Path $destDir 'ModScanner.ps1'

Write-Host ''
Write-Host 'Fetching the latest scanner from GitHub...'
$downloadOk = $false
for ($attempt = 1; $attempt -le 4 -and -not $downloadOk; $attempt++) {
    $freshUrl = '{0}?cb={1}' -f $toolUrl, [guid]::NewGuid().ToString('N')
    try {
        Invoke-WebRequest -Uri $freshUrl -OutFile $dest -ErrorAction Stop
        $body = Get-Content -Raw -LiteralPath $dest
        if ($body -notlike '*MOD CHEAT SCANNER*') { throw 'downloaded file is stale or wrong' }
        $downloadOk = $true
    }
    catch {
        if ($attempt -lt 4) {
            Write-Host ("Attempt {0} failed - retrying..." -f $attempt)
        }
        else {
            Write-Host ''
            Write-Host ("ERROR: could not download the scanner.`nURL: {0}`nDetails: {1}" -f $toolUrl, $_.Exception.Message)
            exit 1
        }
    }
}
Write-Host 'Scanner ready. Starting scan in a new window...'

$toolArgs = @(
    '-NoProfile'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    ('"{0}"' -f $dest)
)

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'powershell.exe'
$psi.Arguments = ($toolArgs -join ' ')
$psi.UseShellExecute = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit() | Out-Null
exit
