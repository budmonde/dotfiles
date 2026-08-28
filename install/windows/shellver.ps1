param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

function Get-UvPath {
    $command = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Path
    }
    $wingetPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\uv.exe'
    if (Test-Path -LiteralPath $wingetPath) {
        return $wingetPath
    }
    return $null
}

function Test-ShellverInstalled {
    if (Get-Command shellver -CommandType Application -ErrorAction SilentlyContinue) {
        return $true
    }
    return Test-Path -LiteralPath (Join-Path $HOME '.local\bin\shellver.exe')
}

function Install-Shellver {
    param([string]$Revision)

    $uv = Get-UvPath
    if (-not $uv) {
        throw 'uv is unavailable'
    }
    if (-not $Revision) {
        $Revision = 'main'
    }
    $output = (& $uv tool install --force --refresh-package shellver "git+https://github.com/budmonde/shellver.git@$Revision" 2>&1 | Out-String).Trim()
    if ($output) {
        Write-DotbotInstallerDiagnostic $output
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-ShellverInstalled)) {
        throw 'shellver installation failed'
    }
}

Invoke-DotbotInstaller {
    $state = if (Test-ShellverInstalled) { 'current' } else { 'absent' }
    if ($Operation -eq 'status' -or ($Operation -eq 'apply' -and $state -eq 'current')) {
        return $state
    }
    Install-Shellver -Revision $RequestedVersion
    return 'current'
}
