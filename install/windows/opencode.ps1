param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

function Get-OpenCodeState {
    $installedVersion = $null
    foreach ($application in @(Get-Command opencode -All -CommandType Application -ErrorAction SilentlyContinue | Group-Object Path | ForEach-Object { $_.Group[0] })) {
        $version = (& $application.Path --version 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
            $displayVersion = if ($version) { $version } else { '<no version>' }
            Write-DotbotInstallerDiagnostic "Preserving non-public OpenCode variant: $($application.Path) ($displayVersion)"
            return 'unsupported'
        }
        $installedVersion = $version
    }
    if (-not $installedVersion) {
        return 'absent'
    }
    return 'current'
}

function Install-PublicOpenCode {
    param([string]$Version)

    $npm = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $npm) {
        throw 'npm is unavailable'
    }
    $package = if ($Version) { "opencode-ai@$Version" } else { 'opencode-ai' }
    $output = (& $npm.Path install --global $package --no-audit --no-fund 2>&1 | Out-String).Trim()
    if ($output) {
        Write-DotbotInstallerDiagnostic $output
    }
    if ($LASTEXITCODE -ne 0) {
        throw "npm failed to install $package"
    }
}

Invoke-DotbotInstaller {
    $state = Get-OpenCodeState
    if ($Operation -eq 'status' -or $state -eq 'unsupported' -or ($Operation -eq 'apply' -and $state -ne 'absent')) {
        return $state
    }
    if (-not (Get-Command npm -CommandType Application -ErrorAction SilentlyContinue)) {
        return 'blocked'
    }
    Install-PublicOpenCode -Version $RequestedVersion
    return (Get-OpenCodeState)
}
