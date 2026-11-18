<#
.SYNOPSIS
    Project Lyra ScreenShare - all-in-one Windows screen sharing tool.

.DESCRIPTION
    Mode Share: captures the primary screen (or a specific window by title) via
    GDI+, encodes as JPEG, and streams the frames over TCP to a Lyra View receiver.

    Mode View: runs a TCP listener, accepts a sender, decodes the frames, and
    displays them in a borderless window with an FPS counter and a fullscreen toggle.

.PARAMETER Mode
    Share or View. Defaults to Share.

.PARAMETER ReceiverHost
    Receiver IP address or hostname (Share mode). Accepts "host" or "host:port".
    Defaults to 127.0.0.1.

.PARAMETER Port
    TCP port used for the stream (View mode listener / Share mode target). Defaults to 19732.

.PARAMETER Fps
    Share mode frame rate in frames per second. Defaults to 10.

.PARAMETER WindowTitle
    Share mode: capture a specific top-level window by title. Empty string = capture the primary screen.

.PARAMETER Quality
    JPEG quality between 1 and 100 (Share mode). Defaults to 80.

.PARAMETER WindowWidth
    View mode window width. Defaults to 1280.

.PARAMETER WindowHeight
    View mode window height. Defaults to 720.

.EXAMPLE
    # View mode - on the machine you want to see the screen:
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\ScreenShare.ps1 -Mode View -Port 19732

    # Share mode - on the machine doing the sharing:
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\ScreenShare.ps1 -Mode Share -ReceiverHost 192.168.1.50 -Port 19732 -Fps 10 -WindowTitle 'Chrome'
#>
param(
    [ValidateSet('Share', 'View')] [string]$Mode = 'Share',
    [string]$ReceiverHost = '127.0.0.1',
    [int]$Port = 19732,
    [int]$Fps = 10,
    [string]$WindowTitle = '',
    [int]$Quality = 80,
    [int]$WindowWidth = 1280,
    [int]$WindowHeight = 720,
    [switch]$Hard,
    [string]$CheatStringsFile = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$script:AppName = 'Project Lyra'
$script:AppVersion = '3.3.1'
$script:CreatorName = 'Lyra'
$script:CreatorDiscord = 'echo_ducky'
$script:ExtraCredits = @(
    'Built on GDI+ and pure stubbornness'
    'Powered by PowerShell, .NET, and bad decisions'
)

$script:CheatStrings = @(
    'aimbot', 'wallhack', 'esp', 'triggerbot', 'nospread', 'fly', 'speedhack',
    'xray', 'spinbot', 'reach', 'backtrack', 'glow', 'chams', 'hook', 'injector',
    'dma', 'reader', 'writer', 'legit', 'turbo', 'bone', 'visor'
)
if ($CheatStringsFile) {
    $script:CheatStrings = @()
    if (Test-Path -LiteralPath $CheatStringsFile) {
        $cheatLines = Get-Content -LiteralPath $CheatStringsFile
        foreach ($cheatLine in $cheatLines) {
            if (-not [string]::IsNullOrWhiteSpace($cheatLine)) { $script:CheatStrings += $cheatLine.Trim().ToLowerInvariant() }
        }
    }
}

function Get-ScreenShareCheatMatch {
    param([string]$Haystack)
    $lower = $Haystack.ToLowerInvariant()
    foreach ($cheatString in $script:CheatStrings) {
        if ($lower.Contains($cheatString.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Get-ScreenShareVersion { return $script:AppVersion }

function Set-ScreenShareVersion {
    param([string]$Version)
    if (-not [string]::IsNullOrWhiteSpace($Version)) { $script:AppVersion = $Version }
}

function Get-ScreenShareNextVersion {
    param(
        [ValidateSet('Patch', 'Bigger', 'Massive')] [string]$BumpType = 'Patch'
    )
    $nums = @($script:AppVersion.Split('.') | ForEach-Object { [int]$_ })
    while ($nums.Count -lt 3) { $nums += 0 }
    switch ($BumpType) {
        'Patch' { $nums[2] = $nums[2] + 1 }
        'Bigger' { $nums[1] = $nums[1] + 1; $nums[2] = 0 }
        'Massive' { $nums[0] = $nums[0] + 1; $nums[1] = 0; $nums[2] = 0 }
    }
    return ('{0}.{1}.{2}' -f $nums[0], $nums[1], $nums[2])
}

if ($Mode -eq 'Share') {
    # Accept either "host" (use -Port) or "host:port" (override -Port).
    $parts = @($ReceiverHost -split ':')
    if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
        $receiverIp = $parts[0]
        $receiverPort = [int]$parts[1]
    }
    else {
        $receiverIp = $ReceiverHost
        $receiverPort = [int]$Port
    }

    $win32Source = @'
    using System;
    using System.Runtime.InteropServices;
    using System.Text;

    public static class LyraWindowFinder {
        public delegate bool EnumWindowsCallback(int hwnd, int lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool EnumWindows(EnumWindowsCallback callback, int lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(int hwnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(int hwnd, out RECT rect);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(int hwnd);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        private static EnumWindowsCallback _callback;
        private static string _pendingTitle;
        private static StringBuilder _sb = new StringBuilder(1024);
        private static IntPtr _foundHwnd;
        private static bool _finished;

        public static int FindWindow(string title) {
            _pendingTitle = title;
            _foundHwnd = IntPtr.Zero;
            _finished = false;
            _sb.Length = 0;
            _callback = new EnumWindowsCallback(Callback);
            EnumWindows(_callback, 0);
            return _finished ? (int)_foundHwnd : 0;
        }

        private static bool Callback(int hwnd, int lParam) {
            if (_finished) { return true; }
            _sb.Length = 0;
            GetWindowText(hwnd, _sb, 1024);
            string text = _sb.ToString();
            if (text.ToLowerInvariant() == _pendingTitle.ToLowerInvariant()) {
                _foundHwnd = new IntPtr(hwnd);
                _finished = true;
                return false;
            }
            return true;
        }

        public static bool SetForeground(int hwnd) { return SetForegroundWindow(hwnd); }

        public static bool GetWindowBounds(int hwnd) {
            RECT rect;
            bool ok = GetWindowRect(hwnd, out rect);
            LastLeft = ok ? rect.Left : 0;
            LastTop = ok ? rect.Top : 0;
            LastRight = ok ? rect.Right : 0;
            LastBottom = ok ? rect.Bottom : 0;
            return ok;
        }

        public static int LastLeft;
        public static int LastTop;
        public static int LastRight;
        public static int LastBottom;
    }
'@

    Add-Type -TypeDefinition $win32Source

    $capX = 0
    $capY = 0
    $capW = 0
    $capH = 0

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    if (-not $WindowTitle) {
        $capX = [int]$screen.X
        $capY = [int]$screen.Y
        $capW = [int]$screen.Width
        $capH = [int]$screen.Height
    }
    else {
        $hwnd = [LyraWindowFinder]::FindWindow($WindowTitle)
        if ($hwnd -le 0) {
            Write-Error "Project Lyra: could not find window titled '$WindowTitle'"
            exit 1
        }
        [LyraWindowFinder]::SetForeground($hwnd) | Out-Null
        [LyraWindowFinder]::GetWindowBounds($hwnd) | Out-Null
        $capX = [LyraWindowFinder]::LastLeft
        $capY = [LyraWindowFinder]::LastTop
        $capW = ([LyraWindowFinder]::LastRight - [LyraWindowFinder]::LastLeft)
        $capH = ([LyraWindowFinder]::LastBottom - [LyraWindowFinder]::LastTop)
    }

    $cheatHit = $false
    if ($WindowTitle) { $cheatHit = Get-ScreenShareCheatMatch -Haystack $WindowTitle }
    if ($cheatHit) {
        Write-Host ("Project Lyra: CHEAT CLIENT MATCHED -> '{0}'" -f $WindowTitle)
    }

    Write-Host ("{0} v{1} - sharing to {2}:{3}" -f $script:AppName, $script:AppVersion, $receiverIp, $receiverPort)

    $bitmap = [System.Drawing.Bitmap]::new([int]$capW, [int]$capH)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    $tcpClient.Connect($receiverIp, $receiverPort)
    $stream = $tcpClient.GetStream()
    $writer = [System.IO.BinaryWriter]::new($stream)

    $intervalMs = 1000 / $Fps
    if ($intervalMs -lt 10) { $intervalMs = 10 }

    try {
        while ($true) {
            # Copy the screen region into the bitmap at (0,0).
            $graphics.CopyFromScreen($capX, $capY, 0, 0, [System.Drawing.Size]::new($capW, $capH))

            if ($Hard -or $cheatHit) {
                $toughPen = [System.Drawing.Pen]::new([System.Drawing.Color]::Red, 6)
                $graphics.DrawRectangle($toughPen, 0, 0, ($capW - 1), ($capH - 1))
                $toughPen.Dispose()
                $toughFont = [System.Drawing.Font]::new('Arial', 42, [System.Drawing.FontStyle]::Bold)
                $toughBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Red)
                $graphics.DrawString('LYRA GUARD', $toughFont, $toughBrush, 12, 12)
                $toughBrush.Dispose()
                $toughFont.Dispose()
            }

            $ms = [System.IO.MemoryStream]::new()
            try {
                $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                    Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
                if (-not $jpegCodec) { throw 'JPEG codec unavailable' }
                $encoderParams = [System.Drawing.Imaging.EncoderParameters]::new(1)
                $encoderParams.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
                    [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)
                $bitmap.Save($ms, $jpegCodec, $encoderParams)
            }
            catch {
                $ms.SetLength(0)
                $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            }
            $bytes = $ms.ToArray()
            $ms.Dispose()

            $writer.Write([int]$bytes.Length)
            $writer.Write($bytes)
            $writer.Flush()

            Start-Sleep -Milliseconds ([int]$intervalMs)
        }
    }
    finally {
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($tcpClient) { $tcpClient.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
    }

    exit
}

if ($Mode -eq 'View') {
    Write-Host ("{0} v{1}" -f $script:AppName, $script:AppVersion)
    Write-Host ("Creator: {0} (discord: {1})" -f $script:CreatorName, $script:CreatorDiscord)
    Write-Host ("Credits: {0}" -f ($script:ExtraCredits -join ', '))
    Write-Host ("Listening on port {0}..." -f $Port)

    $script:listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    $script:listener.Start()
    $script:client = $null
    $script:stream = $null
    $script:frameBuffer = [System.IO.MemoryStream]::new()

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "$($script:AppName) ScreenShare v$($script:AppVersion)"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor = [System.Drawing.Color]::FromArgb(15, 22, 30)
    $size = [System.Drawing.Size]::new([int]$WindowWidth, [int]$WindowHeight)
    $form.ClientSize = $size

    $script:topBar = [System.Windows.Forms.Panel]::new()
    $script:topBar.Dock = [System.Windows.Forms.DockStyle]::Top
    $script:topBar.Height = 40
    $script:topBar.BackColor = [System.Drawing.Color]::FromArgb(25, 38, 50)

    $script:BrandLabel = [System.Windows.Forms.Label]::new()
    $script:BrandLabel.Dock = [System.Windows.Forms.DockStyle]::Left
    $script:BrandLabel.Width = 210
    $script:BrandLabel.Text = '  PROJECT LYRA  /  LIVE VIEW'
    $script:BrandLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 220, 255)
    $script:BrandLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $script:BrandLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:topBar.Controls.Add($script:BrandLabel)

    $script:FpsLabel = [System.Windows.Forms.Label]::new()
    $script:FpsLabel.Dock = [System.Windows.Forms.DockStyle]::Left
    $script:FpsLabel.Width = 200
    $script:FpsLabel.Text = 'Waiting for sender...'
    $script:FpsLabel.ForeColor = [System.Drawing.Color]::FromArgb(205, 215, 225)
    $script:FpsLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $script:FpsLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:topBar.Controls.Add($script:FpsLabel)

    $script:CloseButton = [System.Windows.Forms.Button]::new()
    $script:CloseButton.Dock = [System.Windows.Forms.DockStyle]::Right
    $script:CloseButton.Width = 34
    $script:CloseButton.Height = 30
    $script:CloseButton.Text = 'X'
    $script:CloseButton.BackColor = [System.Drawing.Color]::FromArgb(90, 25, 35)
    $script:CloseButton.ForeColor = [System.Drawing.Color]::White
    $script:CloseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $script:CloseButton.FlatAppearance.BorderSize = 0
    $script:CloseButton.Add_Click({ $form.Close() })
    $script:topBar.Controls.Add($script:CloseButton)

    $script:FullButton = [System.Windows.Forms.Button]::new()
    $script:FullButton.Dock = [System.Windows.Forms.DockStyle]::Right
    $script:FullButton.Width = 90
    $script:FullButton.Height = 30
    $script:FullButton.Text = 'Fullscreen'
    $script:FullButton.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 216)
    $script:FullButton.ForeColor = [System.Drawing.Color]::White
    $script:FullButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $script:FullButton.FlatAppearance.BorderSize = 0
    $script:FullButton.Add_Click({
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            $script:FullButton.Text = 'Fullscreen'
        }
        else {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
            $script:FullButton.Text = 'Exit'
        }
    })
    $script:topBar.Controls.Add($script:FullButton)

    $form.Controls.Add($script:topBar)

    $script:Pic = [System.Windows.Forms.PictureBox]::new()
    $script:Pic.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:Pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $script:Pic.BackColor = [System.Drawing.Color]::FromArgb(15, 22, 30)
    $form.Controls.Add($script:Pic)

    $script:FrameCount = 0
    $script:FpsWindowStart = Get-Date

    # A WinForms timer runs on the UI message loop, so the picture actually updates.
    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 25
    $timer.Add_Tick({
        try {
            if (-not $script:client -and $script:listener.Pending()) {
                $script:client = $script:listener.AcceptTcpClient()
                $script:stream = $script:client.GetStream()
                $script:FpsLabel.Text = 'Connected - waiting for frames...'
            }

            if ($script:stream -and $script:stream.DataAvailable) {
                $chunk = [byte[]]::new(65536)
                $read = $script:stream.Read($chunk, 0, $chunk.Length)
                if ($read -gt 0) { $script:frameBuffer.Write($chunk, 0, $read) }
            }

            while ($script:frameBuffer.Length -ge 4) {
                $all = $script:frameBuffer.ToArray()
                $len = [System.BitConverter]::ToInt32($all, 0)
                if ($len -le 0 -or $len -gt 100000000) {
                    $script:frameBuffer.SetLength(0)
                    break
                }
                if ($all.Length -lt ($len + 4)) { break }

                $frameBytes = [byte[]]::new($len)
                [Array]::Copy($all, 4, $frameBytes, 0, $len)

                $restLen = $all.Length - $len - 4
                $script:frameBuffer.SetLength(0)
                if ($restLen -gt 0) {
                    $rest = [byte[]]::new($restLen)
                    [Array]::Copy($all, ($len + 4), $rest, 0, $restLen)
                    $script:frameBuffer.Write($rest, 0, $restLen)
                }

                $ms = [System.IO.MemoryStream]::new($frameBytes)
                $ms.Position = 0
                $img = [System.Drawing.Image]::FromStream($ms)
                $ms.Dispose()
                $old = $script:Pic.Image
                $script:Pic.Image = $img
                $script:Pic.Invalidate()
                if ($old) { $old.Dispose() }
                $script:FrameCount++
            }

            $elapsed = (Get-Date) - $script:FpsWindowStart
            if ($elapsed.TotalSeconds -ge 1) {
                if ($script:FrameCount -gt 0) {
                    $fps = [math]::Round($script:FrameCount / $elapsed.TotalSeconds, 1)
                    $script:FpsLabel.Text = ('FPS: {0}' -f $fps)
                }
                $script:FrameCount = 0
                $script:FpsWindowStart = Get-Date
            }
        }
        catch {
            $script:FpsLabel.Text = 'Stream error'
        }
    })
    $timer.Start()

    $null = $form.ShowDialog()

    $timer.Stop()
    try { if ($script:stream) { $script:stream.Dispose() } } catch { }
    try { if ($script:client) { $script:client.Dispose() } } catch { }
    try { $script:listener.Stop() } catch { }
    exit
}
