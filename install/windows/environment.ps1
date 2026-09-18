param(
    [Parameter(Mandatory, Position = 0)][string]$Specification,
    [Parameter(Position = 1)][ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$assignment = $Specification -split '=', 2
if ($assignment.Count -ne 2 -or [string]::IsNullOrWhiteSpace($assignment[0])) {
    throw 'Environment specifications must use NAME=Scope:Kind:Value'
}

$attributes = $assignment[1] -split ':', 3
if ($attributes.Count -ne 3) {
    throw 'Environment specifications must use NAME=Scope:Kind:Value'
}

$name = $assignment[0]
$scope = switch ($attributes[0].ToLowerInvariant()) {
    'user' { [EnvironmentVariableTarget]::User }
    'machine' { [EnvironmentVariableTarget]::Machine }
    default { throw "Unsupported environment scope: $($attributes[0])" }
}
$path = switch ($attributes[1].ToLowerInvariant()) {
    'value' { $false }
    'path' { $true }
    default { throw "Unsupported environment value kind: $($attributes[1])" }
}
$value = $attributes[2]

if ($path -and ($value -eq '~' -or $value.StartsWith('~/') -or $value.StartsWith('~\'))) {
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $value = if ($value -eq '~') {
        $userProfile
    } else {
        Join-Path $userProfile $value.Substring(2)
    }
}
if ($path) {
    $value = [IO.Path]::GetFullPath($value)
}

Invoke-DotbotInstaller {
    Invoke-WindowsEnvironmentVariable -Name $name -Value $value -Scope $scope `
        -Operation $Operation -Path:$path
}
