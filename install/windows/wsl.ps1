param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

function Get-WslState {
    $wsl = Get-Command wsl -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $wsl) {
        return 'absent'
    }
    $null = & $wsl.Path --status 2>$null
    return $(if ($LASTEXITCODE -eq 0) { 'current' } else { 'absent' })
}

Invoke-DotbotInstaller {
    if ($RequestedVersion) {
        throw 'WSL does not accept a requested version'
    }
    $state = Get-WslState
    if ($Operation -eq 'status' -or ($Operation -eq 'apply' -and $state -eq 'current')) {
        return $state
    }

    $arguments = if ($Operation -eq 'upgrade' -and $state -eq 'current') {
        @('--update')
    } else {
        @('--install', '--no-launch')
    }
    $output = (& wsl @arguments 2>&1 | Out-String).Trim()
    if ($output) {
        Write-DotbotInstallerDiagnostic $output
    }
    if ($LASTEXITCODE -ne 0) {
        throw "wsl failed with exit code $LASTEXITCODE"
    }
    return 'current'
}
