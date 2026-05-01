# Create a Start Menu shortcut for WSL Ubuntu and assign a keyboard hotkey.
# Usage: powershell -NoProfile -File windows\bin\wsl-shortcut.ps1
#
# Creates: Start Menu\Programs\Ubuntu Terminal.lnk
# Hotkey:  Ctrl+Alt+T (standard terminal shortcut)

$ErrorActionPreference = "Stop"

$startMenu = [Environment]::GetFolderPath("StartMenu")
$shortcutPath = Join-Path $startMenu "Programs\Ubuntu Terminal.lnk"

if (Test-Path $shortcutPath) {
    Write-Host "Shortcut already exists: $shortcutPath"
    return
}

$wshell = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "wt.exe"
$shortcut.Arguments = "-p Ubuntu"
$shortcut.Description = "Open Windows Terminal with Ubuntu (WSL)"
$shortcut.Hotkey = "Ctrl+Alt+T"
$shortcut.Save()

Write-Host "Created shortcut: $shortcutPath (Ctrl+Alt+T)"
