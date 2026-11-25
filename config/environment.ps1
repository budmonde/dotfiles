# environment.ps1 is the environment loader for powershell
param(
    [switch]$Interactive
)

. "$PSScriptRoot\powershell\machine.ps1"

if (Test-Path -LiteralPath "$HOME\.profile_local_before.ps1" -PathType Leaf) {
    . "$HOME\.profile_local_before.ps1"
}

. "$PSScriptRoot\powershell\xdg.ps1"
. "$PSScriptRoot\powershell\bootstrap.ps1"
. "$PSScriptRoot\powershell\external.ps1"

if (Test-Path -LiteralPath "$HOME\.profile_local_after.ps1" -PathType Leaf) {
    . "$HOME\.profile_local_after.ps1"
}

. "$PSScriptRoot\powershell\integrations.ps1" -Interactive:$Interactive
