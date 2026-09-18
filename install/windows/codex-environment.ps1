param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$userProfile = [Environment]::GetFolderPath('UserProfile')
$codexHome = Join-Path $userProfile '.config\codex'

Invoke-DotbotInstaller {
    if ($RequestedVersion) {
        throw 'The persistent Codex environment does not accept a requested version'
    }
    return (Invoke-WindowsEnvironmentVariable -Name 'CODEX_HOME' -Value $codexHome `
        -Scope User -Operation $Operation -Path)
}
