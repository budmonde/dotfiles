param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$versionFile = Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'profiles\node-version'

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

function Get-LockedNodeVersion {
    return (Get-Content -Raw -LiteralPath $versionFile).Trim().TrimStart('v')
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
    $fnm = Get-FnmPath
    if (-not $fnm) {
        return 'blocked'
    }
    $version = Get-LockedNodeVersion
    if (-not $version) {
        throw "$versionFile is empty"
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
    $state = Get-NodeState
    if ($Operation -eq 'status' -or ($Operation -eq 'apply' -and $state -in @('current', 'update-available'))) {
        return $state
    }
    if ($state -eq 'blocked') {
        return $state
    }

    if ($Operation -eq 'upgrade') {
        $target = $RequestedVersion
        if (-not $target) {
            $fnm = Get-FnmPath
            $target = (& $fnm list-remote --latest 2>$null | Out-String).Trim().TrimStart('v')
        }
        if (-not $target) {
            throw 'Could not resolve a Node.js upgrade version'
        }
        $target = $target.TrimStart('v')
        Set-NodeVersion -Version $target
        $temporary = "$versionFile.$PID.tmp"
        [System.IO.File]::WriteAllText($temporary, "$target`n", (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $versionFile -Force
    } else {
        Set-NodeVersion -Version (Get-LockedNodeVersion)
    }
    return (Get-NodeState)
}
