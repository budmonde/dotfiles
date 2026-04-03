# Resolve real directory when loaded through a symlink
$script:DotfilesDir = $PSScriptRoot
$script:ProfileTarget = (Get-Item $PSCommandPath).Target
if ($ProfileTarget) { $script:DotfilesDir = Split-Path $ProfileTarget }

# Environment variables and PATH setup

. $DotfilesDir\powershell\functions.ps1
. $DotfilesDir\powershell\bootstrap.ps1
. $DotfilesDir\powershell\external.ps1

if (Test-Path "$HOME\.psprofile_local.ps1") {
    . "$HOME\.psprofile_local.ps1"
}

# Interactive shell setup
. $DotfilesDir\powershell\settings.ps1
. $DotfilesDir\powershell\plugins.ps1
. $DotfilesDir\powershell\aliases.ps1
. $DotfilesDir\powershell\prompt.ps1
