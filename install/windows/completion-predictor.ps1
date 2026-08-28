param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force
Restart-DotbotInstallerInPowerShellCore -ScriptPath $PSCommandPath -Operation $Operation -RequestedVersion $RequestedVersion
Invoke-DotbotInstaller {
    Invoke-PowerShellGalleryModule -Name CompletionPredictor -Operation $Operation -RequestedVersion $RequestedVersion
}
