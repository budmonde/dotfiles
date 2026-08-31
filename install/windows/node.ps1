param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

function Get-FnmPath {
    $command = Get-Command fnm -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Path
    }
    $wingetPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\fnm.exe'
    if (Test-Path -LiteralPath $wingetPath) {
        return $wingetPath
    }
    return $null
}

function Invoke-Fnm {
    param([string]$Fnm, [string[]]$Arguments)

    $output = (& $Fnm @Arguments 2>&1 | Out-String).Trim()
    if ($output) {
        Write-DotbotInstallerDiagnostic $output
    }
    if ($LASTEXITCODE -ne 0) {
        throw "fnm failed with exit code $LASTEXITCODE"
    }
    return $output
}

function Get-NodeState {
    param([Parameter(Mandatory)][string]$Version)

    $fnm = Get-FnmPath
    if (-not $fnm) {
        return 'blocked'
    }
    $installed = (& $fnm exec --using $version -- node --version 2>$null | Out-String).Trim().TrimStart('v')
    if ($LASTEXITCODE -ne 0 -or $installed -ne $version) {
        return 'absent'
    }
    $default = (& $fnm default 2>$null | Out-String).Trim().TrimStart('v')
    if ($LASTEXITCODE -ne 0 -or $default -ne $version) {
        return 'drifted'
    }
    if ($env:DOTBOT_INSTALL_ONLINE -notin @('0', 'false', 'False', 'no', 'No', 'off', 'Off')) {
        $latest = (& $fnm list-remote --latest 2>$null | Out-String).Trim().TrimStart('v')
        if ($LASTEXITCODE -eq 0 -and $latest -and $latest -ne $version) {
            return 'update-available'
        }
    }
    return 'current'
}

function Set-NodeVersion {
    param([string]$Version)

    $fnm = Get-FnmPath
    if (-not $fnm) {
        throw 'fnm is unavailable'
    }
    $null = Invoke-Fnm -Fnm $fnm -Arguments @('install', $Version)
    $null = Invoke-Fnm -Fnm $fnm -Arguments @('default', $Version)
    $verified = (& $fnm exec --using $Version -- node --version 2>$null | Out-String).Trim().TrimStart('v')
    if ($LASTEXITCODE -ne 0 -or $verified -ne $Version.TrimStart('v')) {
        throw "Node.js verification failed for $Version"
    }
}

Invoke-DotbotInstaller {
    $target = ([string]$RequestedVersion).Trim().TrimStart('v')
    if (-not $target) {
        throw 'The Node.js recipe must declare an exact desired version'
    }
    $state = Get-NodeState -Version $target
    if ($Operation -eq 'status' -or $state -in @('current', 'update-available')) {
        return $state
    }
    if ($state -eq 'blocked') {
        return $state
    }

    Set-NodeVersion -Version $target
    return (Get-NodeState -Version $target)
}
