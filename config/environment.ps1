# environment.ps1 is the environment loader for powershell
param(
    [switch]$Interactive
)

. "$PSScriptRoot\powershell\machine.ps1"

if (Test-Path -LiteralPath "$HOME\.profile_local_before.ps1" -PathType Leaf) {
    . "$HOME\.profile_local_before.ps1"
}

. "$env:DOTFILES_SHELL_DIR\xdg.ps1"
. "$env:DOTFILES_SHELL_DIR\bootstrap.ps1"
. "$env:DOTFILES_SHELL_DIR\external.ps1"

if (Test-Path -LiteralPath "$HOME\.profile_local_after.ps1" -PathType Leaf) {
    . "$HOME\.profile_local_after.ps1"
}

. "$env:DOTFILES_SHELL_DIR\integrations.ps1" -Interactive:$Interactive
