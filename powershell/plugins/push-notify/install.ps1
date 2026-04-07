# push-notify installation script (Windows)
# Creates a .cmd shim in ~/.local/bin so push-notify is callable as a bare command

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ps1Path = Join-Path $scriptDir 'push-notify.ps1'
$binDir = Join-Path $HOME '.local\bin'

if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }

$shimPath = Join-Path $binDir 'push-notify.cmd'
$shimContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ps1Path`" %*"
Set-Content -Path $shimPath -Value $shimContent -Encoding ASCII

Write-Host "Installed push-notify shim to $shimPath"
