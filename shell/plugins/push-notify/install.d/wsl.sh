#!/usr/bin/env bash
# WSL-specific installation for push-notify
# Sets up the wsltoast:// protocol handler for click-to-focus

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

WINDOWS_USER=$(powershell.exe -NoProfile -Command "[Environment]::UserName" 2>/dev/null | tr -d '\r\n')
WINDOWS_HOME="/mnt/c/Users/$WINDOWS_USER"
HANDLER_DIR="$WINDOWS_HOME/.local/share/wsl"

mkdir -p "$HANDLER_DIR"

cp "$PLUGIN_DIR/windows/push-notify-handler.ps1" "$HANDLER_DIR/push-notify-handler.ps1"
echo "Installed push-notify-handler.ps1 to $HANDLER_DIR"

HANDLER_PATH="$HANDLER_DIR/push-notify-handler.ps1"
WIN_HANDLER_PATH=$(wslpath -w "$HANDLER_PATH")

# Use a temp script to avoid quoting issues
PS_SCRIPT=$(mktemp --suffix=.ps1)
cat > "$PS_SCRIPT" <<EOF
\$protocolKey = 'HKCU:\Software\Classes\wsltoast'
\$commandKey = "\$protocolKey\shell\open\command"

if (-not (Test-Path \$protocolKey)) {
    New-Item -Path \$protocolKey -Force | Out-Null
}
Set-ItemProperty -Path \$protocolKey -Name '(Default)' -Value 'URL:WSL Toast Protocol'
Set-ItemProperty -Path \$protocolKey -Name 'URL Protocol' -Value ''

if (-not (Test-Path \$commandKey)) {
    New-Item -Path \$commandKey -Force | Out-Null
}

\$command = 'powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "${WIN_HANDLER_PATH}" "%1"'
Set-ItemProperty -Path \$commandKey -Name '(Default)' -Value \$command
EOF

WIN_PS_SCRIPT=$(wslpath -w "$PS_SCRIPT")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_PS_SCRIPT" 2>/dev/null
rm -f "$PS_SCRIPT"

echo "Registered wsltoast:// protocol handler in Windows registry."
