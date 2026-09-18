param(
    [Parameter(Mandatory, Position = 0)][string]$PackageId,
    [Parameter(Position = 1)][ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

Invoke-DotbotInstaller {
    Invoke-WinGetPackage -PackageId $PackageId -Operation $Operation -RequestedVersion $RequestedVersion
}
