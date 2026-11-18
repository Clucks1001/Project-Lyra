<#
.SYNOPSIS
    Project Lyra - local installer-style launcher.

.DESCRIPTION
    Dependency check and console menu. Launches the combined ScreenShare tool
    (Share or View mode) from the same folder.

.EXAMPLE
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\installer.ps1
#>
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$script:AppVersion = '3.3.1'

Write-Host ''
Write-Host '=================================================='
Write-Host '   PROJECT LYRA  //  LOCAL LAUNCHER'
Write-Host ("   Version {0}   -   creator: Lyra (echo_ducky)" -f $script:AppVersion)
Write-Host '=================================================='

$toolPath = Join-Path $PSScriptRoot 'ScreenShare.ps1'
if (-not (Test-Path -LiteralPath $toolPath)) {
    Write-Host ("ERROR: ScreenShare.ps1 was not found next to this launcher.`nPath: {0}" -f $toolPath)
    exit 1
}

$validModes = @{ '1' = 'Share'; '2' = 'View' }
do {
    Write-Host ''
    Write-Host '--------------------------------------------------'
    Write-Host '  Select an operation'
    Write-Host '--------------------------------------------------'
    Write-Host '  [1]  Share my screen   (send a stream)'
    Write-Host '  [2]  View a screen     (receive a stream)'
    Write-Host '  [3]  Exit'
    Write-Host ''
    $choice = Read-Host 'Enter your choice [1/2/3]'

    if ($choice -eq '3') {
        Write-Host 'Exiting Project Lyra. Goodbye.'
        exit
    }

    if ($validModes.ContainsKey($choice)) {
        $mode = $validModes[$choice]
        break
    }

    Write-Host ("Invalid input '{0}'. Please enter 1, 2, or 3." -f $choice)
} while ($true)

$port = '19732'
$fps = '10'
$receiverHost = '127.0.0.1'

if ($mode -eq 'Share') {
    $entered = Read-Host 'Receiver IP / hostname (press ENTER for 127.0.0.1)'
    if (-not [string]::IsNullOrWhiteSpace($entered)) { $receiverHost = $entered }
    $enteredFps = Read-Host 'Frame rate (press ENTER for 10)'
    if (-not [string]::IsNullOrWhiteSpace($enteredFps)) { $fps = $enteredFps }
}
else {
    $enteredPort = Read-Host 'Listening port (press ENTER for 19732)'
    if (-not [string]::IsNullOrWhiteSpace($enteredPort)) { $port = $enteredPort }
}

$toolArgs = @(
    '-NoProfile'
    '-STA'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    ('"{0}"' -f $toolPath)
    '-Mode'
    $mode
)

if ($mode -eq 'Share') {
    $toolArgs += @('-ReceiverHost', $receiverHost, '-Fps', $fps)
    Write-Host ("Starting Share -> {0} at {1} fps" -f $receiverHost, $fps)
}
else {
    $toolArgs += @('-Port', $port)
    Write-Host ("Starting View on port {0}" -f $port)
}

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'powershell.exe'
$psi.Arguments = ($toolArgs -join ' ')
$psi.UseShellExecute = $true

Write-Host 'Launching a new window...'
$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit() | Out-Null
exit
