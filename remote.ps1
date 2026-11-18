<#
.SYNOPSIS
    Project Lyra - GitHub remote launcher.

.DESCRIPTION
    Downloads ScreenShare.ps1 from GitHub raw and launches it in the chosen mode.

    Fetch this script with (the ?cb= part defeats GitHub's raw-file cache):
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/Clucks1001/Project-Lyra/refs/heads/main/remote.ps1?cb=lyra331')"
#>
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$owner = 'Clucks1001'
$repo = 'Project-Lyra'
$branch = 'main'
$launcherVersion = '3.3.1'
$toolUrl = "https://raw.githubusercontent.com/$owner/$repo/refs/heads/$branch/ScreenShare.ps1"

Write-Host ''
Write-Host '=================================================='
Write-Host '   PROJECT LYRA  //  REMOTE LAUNCHER'
Write-Host ("   Version {0}   -   creator: Lyra (echo_ducky)" -f $launcherVersion)
Write-Host '=================================================='

$destDir = Join-Path ([System.IO.Path]::GetTempPath()) 'LyraScreenShare'
if (-not (Test-Path -LiteralPath $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
$dest = Join-Path $destDir 'ScreenShare.ps1'

Write-Host ''
Write-Host 'Fetching the latest ScreenShare.ps1 from GitHub...'

# raw.githubusercontent.com can serve a cached copy, and Invoke-WebRequest
# reuses a cached response too. A unique query string forces a fresh fetch,
# and the content check rejects any stale file that still slips through.
$downloadOk = $false
for ($attempt = 1; $attempt -le 4 -and -not $downloadOk; $attempt++) {
    $freshUrl = '{0}?cb={1}' -f $toolUrl, [guid]::NewGuid().ToString('N')
    try {
        Invoke-WebRequest -Uri $freshUrl -OutFile $dest -ErrorAction Stop
        $body = Get-Content -Raw -LiteralPath $dest
        $stale = ($body -like '*New-Object System.Net.Sockets.TcpListener*') -or
                 ($body -notlike "*'$launcherVersion'*")
        if ($stale) { throw 'downloaded file is an old cached copy' }
        $downloadOk = $true
    }
    catch {
        if ($attempt -lt 4) {
            Write-Host ("Attempt {0} returned a stale copy - retrying..." -f $attempt)
        }
        else {
            Write-Host ''
            Write-Host ("ERROR: could not download a current copy of the tool.`nURL: {0}`nDetails: {1}" -f $toolUrl, $_.Exception.Message)
            exit 1
        }
    }
}
Write-Host ("Download complete (v{0})." -f $launcherVersion)

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

$toolArgs = @(
    '-NoProfile'
    '-STA'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    ('"{0}"' -f $dest)
    '-Mode'
    $mode
)

if ($mode -eq 'Share') {
    Write-Host ''
    $target = Read-Host 'Receiver IP / hostname (press ENTER for 127.0.0.1)'
    if ([string]::IsNullOrWhiteSpace($target)) { $target = '127.0.0.1' }
    $toolArgs += @('-ReceiverHost', $target, '-Fps', '10')
    Write-Host ("Starting Share -> {0}" -f $target)
}
else {
    $listenPort = Read-Host 'Listening port (press ENTER for 19732)'
    if ([string]::IsNullOrWhiteSpace($listenPort)) { $listenPort = '19732' }
    $toolArgs += @('-Port', $listenPort)
    Write-Host ("Starting View on port {0}" -f $listenPort)
}

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'powershell.exe'
$psi.Arguments = ($toolArgs -join ' ')
$psi.UseShellExecute = $true

Write-Host 'Launching a new window...'
$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit() | Out-Null
exit
