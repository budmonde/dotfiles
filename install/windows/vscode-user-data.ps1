[CmdletBinding()]
param(
    [string]$HomePath = [Environment]::GetFolderPath('UserProfile'),
    [string]$RoamingAppDataPath = $env:APPDATA,
    [ValidateSet('User', 'Process')]
    [string]$EnvironmentTarget = 'User'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-SamePath {
    param([string]$Left, [string]$Right)

    return (Get-NormalizedPath $Left).Equals(
        (Get-NormalizedPath $Right),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

$configRoot = Get-NormalizedPath (Join-Path $HomePath '.config')
$sourcePath = Get-NormalizedPath (Join-Path $RoamingAppDataPath 'Code')
$targetPath = Get-NormalizedPath (Join-Path $configRoot 'Code')
$targetScope = [System.EnvironmentVariableTarget]$EnvironmentTarget
$previousScopedValue = [Environment]::GetEnvironmentVariable('VSCODE_APPDATA', $targetScope)
$previousProcessValue = $env:VSCODE_APPDATA

if ($previousScopedValue -and -not (Test-SamePath $previousScopedValue $configRoot)) {
    throw "Refusing to replace existing VSCODE_APPDATA value '$previousScopedValue' with '$configRoot'."
}

$sourceExists = Test-Path -LiteralPath $sourcePath
$targetExists = Test-Path -LiteralPath $targetPath

if ($sourceExists -and $targetExists) {
    throw "Refusing to merge VS Code user-data roots: '$sourcePath' and '$targetPath' both exist."
}

if ($sourceExists) {
    $sourceItem = Get-Item -Force -LiteralPath $sourcePath
    if ($sourceItem.LinkType -in @('SymbolicLink', 'Junction')) {
        throw "Refusing to migrate linked VS Code user-data root: $sourcePath"
    }

    $codeProcesses = @(Get-Process -Name Code -ErrorAction SilentlyContinue)
    if ($codeProcesses.Count -gt 0) {
        $processIds = ($codeProcesses.Id -join ', ')
        throw "Close VS Code before migrating '$sourcePath'. Running process IDs: $processIds"
    }
}

$moved = $false
try {
    if ($sourceExists) {
        New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
        Move-Item -LiteralPath $sourcePath -Destination $targetPath
        $moved = $true
        Write-Host "VS Code user data moved to $targetPath"
    }

    [Environment]::SetEnvironmentVariable('VSCODE_APPDATA', $configRoot, $targetScope)
    $env:VSCODE_APPDATA = $configRoot
} catch {
    $migrationError = $_
    $rollbackErrors = @()

    try {
        [Environment]::SetEnvironmentVariable('VSCODE_APPDATA', $previousScopedValue, $targetScope)
        if ($null -eq $previousProcessValue) {
            Remove-Item Env:\VSCODE_APPDATA -ErrorAction SilentlyContinue
        } else {
            $env:VSCODE_APPDATA = $previousProcessValue
        }
    } catch {
        $rollbackErrors += $_.Exception.Message
    }

    if ($moved -and (Test-Path -LiteralPath $targetPath) -and -not (Test-Path -LiteralPath $sourcePath)) {
        try {
            Move-Item -LiteralPath $targetPath -Destination $sourcePath
        } catch {
            $rollbackErrors += $_.Exception.Message
        }
    }

    if ($rollbackErrors.Count -gt 0) {
        throw "$($migrationError.Exception.Message) Rollback also failed: $($rollbackErrors -join '; ')"
    }

    throw $migrationError
}

Write-Host "VSCODE_APPDATA set to $configRoot for $EnvironmentTarget."
Write-Host "VS Code Stable resolves its user-data root to $targetPath."

if ($EnvironmentTarget -eq 'User') {
    if (-not ('VSCodeEnvironmentBroadcast' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class VSCodeEnvironmentBroadcast
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint message,
        UIntPtr wParam,
        string lParam,
        uint flags,
        uint timeout,
        out UIntPtr result);
}
'@
    }

    $broadcastResult = [UIntPtr]::Zero
    $broadcastReturn = [VSCodeEnvironmentBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff,
        0x001A,
        [UIntPtr]::Zero,
        'Environment',
        0x0002,
        5000,
        [ref]$broadcastResult
    )
    if ($broadcastReturn -eq [IntPtr]::Zero) {
        Write-Warning 'The user environment was persisted, but Windows did not acknowledge the environment-change broadcast. Sign out before launching VS Code.'
    }
}
