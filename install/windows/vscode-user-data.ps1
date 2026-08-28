param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

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

$homePath = [Environment]::GetFolderPath('UserProfile')
$configRoot = Get-NormalizedPath (Join-Path $homePath '.config')
$sourcePath = Get-NormalizedPath (Join-Path $env:APPDATA 'Code')
$targetPath = Get-NormalizedPath (Join-Path $configRoot 'Code')
$targetScope = [System.EnvironmentVariableTarget]::User

function Get-VSCodeUserDataState {
    $scopedValue = [Environment]::GetEnvironmentVariable('VSCODE_APPDATA', $targetScope)
    if ($scopedValue -and -not (Test-SamePath $scopedValue $configRoot)) {
        return 'blocked'
    }
    $sourceExists = Test-Path -LiteralPath $sourcePath
    $targetExists = Test-Path -LiteralPath $targetPath
    if ($sourceExists -and $targetExists) {
        return 'blocked'
    }
    if ($sourceExists -or -not $scopedValue) {
        return 'drifted'
    }
    return 'current'
}

function Send-EnvironmentChange {
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
    $result = [VSCodeEnvironmentBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff,
        0x001A,
        [UIntPtr]::Zero,
        'Environment',
        0x0002,
        5000,
        [ref]$broadcastResult
    )
    if ($result -eq [IntPtr]::Zero) {
        Write-DotbotInstallerDiagnostic 'The user environment was persisted, but Windows did not acknowledge the environment-change broadcast'
    }
}

function Set-VSCodeUserData {
    $previousScopedValue = [Environment]::GetEnvironmentVariable('VSCODE_APPDATA', $targetScope)
    $previousProcessValue = $env:VSCODE_APPDATA
    $sourceExists = Test-Path -LiteralPath $sourcePath
    $targetExists = Test-Path -LiteralPath $targetPath
    if ($previousScopedValue -and -not (Test-SamePath $previousScopedValue $configRoot)) {
        throw "Refusing to replace existing VSCODE_APPDATA value '$previousScopedValue'"
    }
    if ($sourceExists -and $targetExists) {
        throw "Refusing to merge VS Code user-data roots: '$sourcePath' and '$targetPath' both exist"
    }
    if ($sourceExists) {
        $sourceItem = Get-Item -Force -LiteralPath $sourcePath
        if ($sourceItem.LinkType -in @('SymbolicLink', 'Junction')) {
            throw "Refusing to migrate linked VS Code user-data root: $sourcePath"
        }
        $codeProcesses = @(Get-Process -Name Code -ErrorAction SilentlyContinue)
        if ($codeProcesses.Count -gt 0) {
            throw "Close VS Code before migrating '$sourcePath'. Running process IDs: $($codeProcesses.Id -join ', ')"
        }
    }

    $moved = $false
    try {
        if ($sourceExists) {
            New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
            Move-Item -LiteralPath $sourcePath -Destination $targetPath
            $moved = $true
            Write-DotbotInstallerDiagnostic "VS Code user data moved to $targetPath"
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
    Send-EnvironmentChange
}

Invoke-DotbotInstaller {
    if ($RequestedVersion) {
        throw 'VS Code user-data convergence does not accept a requested version'
    }
    $state = Get-VSCodeUserDataState
    if ($Operation -eq 'status' -or $state -eq 'current' -or $state -eq 'blocked') {
        return $state
    }
    Set-VSCodeUserData
    return (Get-VSCodeUserDataState)
}
