<#
.SYNOPSIS
    ScreenShare - installer-style launcher.

.DESCRIPTION
    Dependency check and console menu. Launches the combined ScreenShare tool
    (Share or View mode).

.EXAMPLE
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\installer.ps1
#>
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName WindowsBase

Write-Host 'Project Lyra - all-in-one screen sharing tool'
Write-Host '----------------------------------------'

$toolPath = Join-Path $PSScriptRoot 'ScreenShare.ps1'

do {
    Write-Host ''
    Write-Host '1) Share my screen (send a stream)'
    Write-Host '2) View a screen (receive a stream)'
    Write-Host '3) Exit'
    $choice = Read-Host 'Choose an option'
} while ($true)

$mode = $null
$receiverHost = '127.0.0.1'
$port = 19732
$fps = 10
$windowTitle = ''

switch ($choice) {
    '1' {
        $mode = 'Share'
        $receiverHost = Read-Host 'Receiver IP / hostname (viewing machine)'
        if ([string]::IsNullOrWhiteSpace($receiverHost)) { $receiverHost = '127.0.0.1' }
        $fps = 10
        Write-Host "Launching share -> $receiverHost port $port at $fps fps"
    }
    '2' {
        $mode = 'View'
        $port = 19732
        Write-Host "Launching view on port $port"
    }
    '3' { exit }
    default { Write-Host 'Invalid option.'; exit }
}

$toolArgs = @(
    '-NoProfile'
    '-STA'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    "`"$toolPath`""
    '-Mode'
    $mode
)

if ($mode -eq 'Share') {
    $toolArgs += @('-ReceiverHost', $receiverHost, '-Fps', $fps)
}
else {
    $toolArgs += @('-Port', $port)
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = ($toolArgs -join ' ')
$psi.UseShellExecute = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit() | Out-Null
exit
