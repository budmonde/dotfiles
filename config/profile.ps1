. "$PSScriptRoot\powershell\functions.ps1"
$isInteractive = Test-InteractiveShell
. "$PSScriptRoot\environment.ps1" -Interactive:$isInteractive

if ($isInteractive) {
    . "$PSScriptRoot\powershell\settings.ps1"
    . "$PSScriptRoot\powershell\plugins.ps1"
    . "$PSScriptRoot\powershell\aliases.ps1"
    . "$PSScriptRoot\powershell\prompt.ps1"
}
