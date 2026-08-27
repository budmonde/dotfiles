# environment.ps1 is the environment loader for powershell
param(
    [switch]$Interactive
)

Merge-EnvironmentPath

# External tool environment variables.
. "$PSScriptRoot\powershell\external.ps1"

# PATH setup.
. "$PSScriptRoot\powershell\bootstrap.ps1"

# Late local environment: overrides that depend on the base dotfiles setup.
if (Test-Path "$HOME\.profile_local.ps1") {
    . "$HOME\.profile_local.ps1"
}

# Runtime integrations mutate the current shell; static values and paths stay in external and bootstrap.
. "$PSScriptRoot\powershell\integrations.ps1" -Interactive:$Interactive
