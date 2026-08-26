$profileItem = Get-Item -LiteralPath $PSCommandPath -Force
$profileTarget = @($profileItem.Target)[0]
$profilePath = if ($profileTarget) { [string]$profileTarget } else { $PSCommandPath }
$profileRoot = Split-Path -Parent $profilePath

. "$profileRoot\powershell\functions.ps1"
$isInteractive = Test-InteractiveShell
. "$profileRoot\environment.ps1" -Interactive:$isInteractive

if ($isInteractive) {
    . "$profileRoot\powershell\settings.ps1"
    . "$profileRoot\powershell\plugins.ps1"
    . "$profileRoot\powershell\aliases.ps1"
    . "$profileRoot\powershell\prompt.ps1"
}
