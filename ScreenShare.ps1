<#
.SYNOPSIS
    ScreenShare - all-in-one Windows screen sharing tool.

.DESCRIPTION
    Mode Share: captures the primary screen (or a specific window by title) via
      GDI+, encodes as JPEG, and streams the frames over TCP to a ScreenShare View receiver.

    Mode View: runs a TCP listener, accepts a sender, decodes the frames, and
      displays them in a borderless window with an FPS counter and a fullscreen toggle.

.PARAMETER Mode
    Share or View. Defaults to Share.

.PARAMETER ReceiverHost
    Receiver IP address or hostname (Share mode). Defaults to 127.0.0.1.

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

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName WindowsBase

$script:AppName = 'Project Lyra'
$script:AppVersion = '3.3.0'
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
            if (-not [string]::IsNullOrWhiteSpace($cheatLine)) { $script:CheatStrings += $cheatLine.Trim() }
        }
    }
}

function Get-ScreenShareCheatMatch {
    param([string]$Haystack)
    $lower = $Haystack.ToLowerInvariant()
    foreach ($cheatString in $script:CheatStrings) {
        if ($lower.Contains($cheatString)) { return $true }
    }
    return $false
}

function Get-ScreenShareVersion {
    return $script:AppVersion
}

function Set-ScreenShareVersion {
    param([string]$Version)
    if (-not [string]::IsNullOrWhiteSpace($Version)) { $script:AppVersion = $Version }
}

function Get-ScreenShareNextVersion {
    param(
        [ValidateSet('Patch', 'Bigger', 'Massive')] [string]$BumpType = 'Patch'
    )
    $parts = @($script:AppVersion.Split('.'))
    $nums = @()
    foreach ($p in $parts) { $nums += [int]$p }
    while ($nums.Count -lt 3) { $nums += 0 }
    switch ($BumpType) {
        'Patch' { $nums[2] = $nums[2] + 1 }
        'Bigger' { $nums[1] = $nums[1] + 1; $nums[2] = 0 }
        'Massive' { $nums[0] = $nums[0] + 1; $nums[1] = 0; $nums[2] = 0 }
    }
    return ('{0}.{1}.{2}' -f $nums[0], $nums[1], $nums[2])
}

if ($Mode -eq 'Share') {
    $parts = @($ReceiverHost -split ':')
    if ($parts.Count -lt 2) { $ReceiverHost = '127.0.0.1'; $Port = 19732 }
    $receiverIp = $parts[0]
    $receiverPort = [int]$parts[1]

    $win32Source = @'
    using System;
    using System.Runtime.InteropServices;
    using System.Text;

    public static class TeslaWindowFinder {
        public delegate bool EnumWindowsCallback(int hwnd, int lParam);

        [System.Runtime.InteropServices.DllImport("user32.dll", System.Runtime.InteropServices.CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        public static extern bool EnumWindows(EnumWindowsCallback callback, int lParam);

        [System.Runtime.InteropServices.DllImport("user32.dll", System.Runtime.InteropServices.CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        public static extern int GetWindowText(int hwnd, StringBuilder lpString, int nMaxCount);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool GetWindowRect(int hwnd, out RECT rect);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(int hwnd);

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
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
            bool ok = GetWindowRect(hwnd, out RECT rect);
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
        $hwnd = [TeslaWindowFinder]::FindWindow($WindowTitle)
        if ($hwnd -le 0) {
            Write-Error "ScreenShare: could not find window titled '$WindowTitle'"
            exit 1
        }
        [TeslaWindowFinder]::SetForeground($hwnd) | Out-Null
        [TeslaWindowFinder]::GetWindowBounds($hwnd) | Out-Null
        $capX = [TeslaWindowFinder]::LastLeft
        $capY = [TeslaWindowFinder]::LastTop
        $capW = ([TeslaWindowFinder]::LastRight - [TeslaWindowFinder]::LastLeft)
        $capH = ([TeslaWindowFinder]::LastBottom - [TeslaWindowFinder]::LastTop)
    }

    $cheatHit = $false
    if ($WindowTitle) {
        $cheatHit = Get-ScreenShareCheatMatch -Haystack $WindowTitle
    }
    if ($cheatHit) {
        Write-Host ("Lyra ScreenShare: CHEAT CLIENT MATCHED -> '{0}'" -f $WindowTitle)
    }

    $bitmap = [System.Drawing.Bitmap]::new([int]$capW, [int]$capH)
    $graphics = New-Object System.Drawing.Graphics -ArgumentList $bitmap

    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $tcpClient.Connect($receiverIp, $receiverPort)
    $stream = $tcpClient.GetStream()
    $writer = New-Object System.IO.BinaryWriter($stream)

    $intervalMs = 1000 / $Fps
    if ($intervalMs -lt 10) { $intervalMs = 10 }

    try {
        while ($true) {
            $graphics.CopyFromScreen($capX, $capY, $capX, $capY, $capW, $capH)
            if ($Hard -or $cheatHit) {
                $toughPen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::Red), 6
                $graphics.DrawRectangle($toughPen, $capX, $capY, $capW, $capH)
                $toughPen.Dispose()
                $toughFont = New-Object System.Drawing.Font -ArgumentList 'Arial', 42, ([System.Drawing.FontStyle]::Bold)
                $toughBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::Red)
                $graphics.DrawString('LYRA GUARD', $toughFont, $toughBrush, ($capX + 12), ($capY + 12))
                $toughBrush.Dispose()
                $toughFont.Dispose()
            }
            $ms = New-Object System.IO.MemoryStream
            $jpegSaved = $false
            try {
                $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters
                $encoderType = [System.Drawing.Imaging.Encoder]::Quality
                $encoderArgs = @($encoderType, $Quality)
                $encoderParam = New-Object System.Drawing.Imaging.EncoderParameter -ArgumentList $encoderArgs
                $encoderParams.Add($encoderParam)
                $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg, $encoderParams)
                $jpegSaved = $true
            }
            catch {
                $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            }
            if (-not $jpegSaved) { Write-Host 'ScreenShare: jpeg encoder fallback used.' }
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
    $script:frameReady = $false
    $script:pendingFrame = $null
    $script:listener = New-Object System.Net.Sockets.TcpListener
    $script:listener.Start([System.Net.IPAddress]::Any, $Port)

    Write-Host ("{0} v{1}" -f $script:AppName, $script:AppVersion)
    Write-Host ("Creator: {0} (discord: {1})" -f $script:CreatorName, $script:CreatorDiscord)
    Write-Host ("Credits: {0}" -f ($script:ExtraCredits -join ', '))

    $threadStart = [System.Threading.ThreadStart] {
        try {
            $client = $script:listener.AcceptTcpClient()
            $stream = $client.GetStream()
            $reader = New-Object System.IO.BinaryReader($stream)

            while ($true) {
                $length = $reader.ReadInt32()
                if ($length -le 0 -or $length -gt 100000000) { break }

                $frameBytes = $reader.ReadBytes($length)
                $ms = New-Object System.IO.MemoryStream -ArgumentList $frameBytes
                $ms.Position = 0
                $script:pendingFrame = [System.Drawing.Image]::FromStream($ms)
                $ms.Dispose()
                $script:frameReady = $true

                if (-not $client.Connected) { break }
            }
        }
        catch {
            Write-Host "ScreenShare Receiver: client error -> $_"
        }
        finally {
            try { $script:listener.Stop() } catch { }
        }
    }

    $thread = New-Object System.Threading.Thread -ArgumentList $threadStart
    $thread.IsBackground = $true
    $thread.Start()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$($script:AppName) ScreenShare v$($script:AppVersion)"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $size = New-Object System.Drawing.Size
    $size.Width = $WindowWidth
    $size.Height = $WindowHeight
    $form.ClientSize = $size

    $script:topBar = New-Object System.Windows.Forms.Panel
    $script:topBar.Dock = [System.Windows.Forms.DockStyle]::Top
    $script:topBar.Height = 34
    $script:topBar.BackColor = [System.Drawing.Color]::FromArgb(25, 38, 50)

    $script:FpsLabel = New-Object System.Windows.Forms.Label
    $script:FpsLabel.Dock = [System.Windows.Forms.DockStyle]::Left
    $script:FpsLabel.Text = 'Waiting for stream...'
    $script:FpsLabel.AutoSize = $true
    $script:topBar.Controls.Add($script:FpsLabel)

    $script:FullButton = New-Object System.Windows.Forms.Button
    $script:FullButton.Dock = [System.Windows.Forms.DockStyle]::Right
    $script:FullButton.Width = 90
    $script:FullButton.Height = 24
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

    $script:CloseButton = New-Object System.Windows.Forms.Button
    $script:CloseButton.Dock = [System.Windows.Forms.DockStyle]::Right
    $script:CloseButton.Width = 30
    $script:CloseButton.Height = 24
    $script:CloseButton.Text = 'X'
    $script:CloseButton.BackColor = [System.Drawing.Color]::FromArgb(60, 20, 30)
    $script:CloseButton.ForeColor = [System.Drawing.Color]::White
    $script:CloseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $script:CloseButton.FlatAppearance.BorderSize = 0
    $script:CloseButton.Add_Click({ $form.Close() })
    $script:topBar.Controls.Add($script:CloseButton)

    $form.Controls.Add($script:topBar)

    $script:Pic = New-Object System.Windows.Forms.PictureBox
    $script:Pic.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:Pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $form.Controls.Add($script:Pic)

    $script:FrameCount = 0
    $script:FpsWindowStart = Get-Date

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(50)
    $timer.Add_Tick({
        if ($script:frameReady) {
            $script:frameReady = $false
            $script:Pic.Image = $script:pendingFrame
            $script:Pic.Invalidate()
            $script:FrameCount = $script:FrameCount + 1
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
    })
    $timer.Start()

    $null = $form.ShowDialog()

    $timer.Stop()
    try { $thread.Join(3000) | Out-Null } catch { }
    exit
}
