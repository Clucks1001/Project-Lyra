<#
.SYNOPSIS
    Lyra ScreenShare - GitHub remote launcher.

.DESCRIPTION
    Downloads ScreenShare.ps1 from GitHub raw and launches it in the chosen mode.

    This is the script intended to be fetched with:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/Clucks1001/Project-Lyra/refs/heads/main/remote.ps1')"

.EXAMPLE
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/Clucks1001/Project-Lyra/refs/heads/main/remote.ps1')"
#>
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName WindowsBase

$owner = 'Clucks1001'
$repo = 'Project-Lyra'
$branch = 'main'
$toolUrl = "https://raw.githubusercontent.com/$owner/$repo/refs/heads/$branch/ScreenShare.ps1"

Write-Host 'Project Lyra - remote launcher'

$destDir = Join-Path ([System.IO.Path]::GetTempPath()) 'LyraScreenShare'
if (-not (Test-Path -LiteralPath $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
$dest = Join-Path $destDir 'ScreenShare.ps1'
Invoke-WebRequest -Uri $toolUrl -OutFile $dest

do {
    Write-Host ''
    Write-Host '1) Share my screen (send a stream)'
    Write-Host '2) View a screen (receive a stream)'
    Write-Host '3) Exit'
    $choice = Read-Host 'Choose an option'
} while ($true)

if ($choice -eq '3') { exit }

$mode = switch ($choice) { '1' { 'Share' } '2' { 'View' } default { $null } }
if (-not $mode) { exit }

$toolArgs = @(
    '-NoProfile'
    '-STA'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    $dest
    '-Mode'
    $mode
)

if ($mode -eq 'Share') {
    $toolArgs += @('-ReceiverHost', '127.0.0.1', '-Fps', '10')
}
else {
    $toolArgs += @('-Port', '19732')
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = ($toolArgs -join ' ')
$psi.UseShellExecute = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit() | Out-Null
exit
