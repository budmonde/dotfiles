Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$implementationRoot = Join-Path $PSScriptRoot 'lifecycle'
foreach ($implementation in @('Core.ps1', 'Environment.ps1', 'WinGet.ps1', 'PowerShellGallery.ps1')) {
    . (Join-Path $implementationRoot $implementation)
}

Export-ModuleMember -Function @(
    'Get-WindowsEnvironmentVariable',
    'Get-WindowsEnvironmentVariableState',
    'Invoke-DotbotInstaller',
    'Invoke-PowerShellGalleryModule',
    'Invoke-WindowsEnvironmentVariable',
    'Invoke-WinGetPackage',
    'Restart-DotbotInstallerInPowerShellCore',
    'Send-WindowsEnvironmentChange',
    'Set-WindowsEnvironmentVariable',
    'Test-WindowsEnvironmentValue',
    'Write-DotbotInstallerDiagnostic'
)
