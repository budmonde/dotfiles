param(
    [Parameter(Mandatory, Position = 0)][string]$Name,
    [Parameter(Position = 1)][ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion,
    [switch]$SkipPublisherCheck
)

Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$restartArguments = @($Name)
if ($RequestedVersion) {
    $restartArguments += @('-RequestedVersion', $RequestedVersion)
}
if ($SkipPublisherCheck) {
    $restartArguments += '-SkipPublisherCheck'
}
$restartArguments += $Operation
Restart-DotbotInstallerInPowerShellCore -ScriptPath $PSCommandPath -Arguments $restartArguments

Invoke-DotbotInstaller {
    Invoke-PowerShellGalleryModule -Name $Name -Operation $Operation `
        -RequestedVersion $RequestedVersion -SkipPublisherCheck:$SkipPublisherCheck
}
