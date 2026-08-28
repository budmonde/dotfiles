param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force
Invoke-DotbotInstaller {
    Invoke-WinGetPackage -PackageId 'GIMP.GIMP' -Operation $Operation -RequestedVersion $RequestedVersion
}
