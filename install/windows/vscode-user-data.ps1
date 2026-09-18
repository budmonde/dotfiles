param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$homePath = [Environment]::GetFolderPath('UserProfile')
$configRoot = [IO.Path]::GetFullPath((Join-Path $homePath '.config')).TrimEnd('\', '/')
$sourcePath = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Code')).TrimEnd('\', '/')
$targetPath = [IO.Path]::GetFullPath((Join-Path $configRoot 'Code')).TrimEnd('\', '/')
$targetScope = [System.EnvironmentVariableTarget]::User

function Get-VSCodeUserDataState {
    $environmentState = Get-WindowsEnvironmentVariableState `
        -Name 'VSCODE_APPDATA' -Value $configRoot -Scope $targetScope -Path
    if ($environmentState -eq 'drifted') {
        return 'blocked'
    }
    $sourceExists = Test-Path -LiteralPath $sourcePath
    $targetExists = Test-Path -LiteralPath $targetPath
    if ($sourceExists -and $targetExists) {
        return 'blocked'
    }
    if ($sourceExists -or $environmentState -eq 'absent') {
        return 'drifted'
    }
    return 'current'
}

function Set-VSCodeUserData {
    $previousScopedValue = Get-WindowsEnvironmentVariable -Name 'VSCODE_APPDATA' -Scope $targetScope
    $previousProcessValue = Get-WindowsEnvironmentVariable -Name 'VSCODE_APPDATA' -Scope Process
    $sourceExists = Test-Path -LiteralPath $sourcePath
    $targetExists = Test-Path -LiteralPath $targetPath
    if ($previousScopedValue -and -not (Test-WindowsEnvironmentValue -Actual $previousScopedValue -Expected $configRoot -Path)) {
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
        Set-WindowsEnvironmentVariable -Name 'VSCODE_APPDATA' -Value $configRoot `
            -Scope $targetScope -SkipBroadcast
    } catch {
        $migrationError = $_
        $rollbackErrors = @()
        try {
            Set-WindowsEnvironmentVariable -Name 'VSCODE_APPDATA' -Value $previousScopedValue `
                -Scope $targetScope -SkipBroadcast
            Set-WindowsEnvironmentVariable -Name 'VSCODE_APPDATA' -Value $previousProcessValue `
                -Scope Process -SkipBroadcast
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
    Send-WindowsEnvironmentChange
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
