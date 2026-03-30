# push-notify-handler.ps1
# Windows protocol handler for wsltoast:// URLs
# Called by Windows when a toast notification is clicked
# Usage: push-notify-handler.ps1 <url>

param(
    [Parameter(Position=0)]
    [string]$Url
)

if (-not $Url) {
    exit 0
}

$wslDistro = $env:WSL_DISTRO_NAME
if (-not $wslDistro) {
    $wslDistro = (wsl.exe -l -q | Where-Object { $_ -ne '' } | Select-Object -First 1).Trim()
}

wsl.exe -d $wslDistro -- push-notify-callback "$Url"

$terminalProcess = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($terminalProcess) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32 {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
    }
"@
    [Win32]::SetForegroundWindow($terminalProcess.MainWindowHandle) | Out-Null
}
