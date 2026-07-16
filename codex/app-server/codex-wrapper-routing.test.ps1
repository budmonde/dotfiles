$aliasesPath = Join-Path $PSScriptRoot '..\..\powershell\aliases.ps1'
. $aliasesPath

$failures = 0

function Assert-Equal {
    param($Name, $Actual, $Expected)

    if ($Actual -ne $Expected) {
        Write-Error "$Name`: expected '$Expected', got '$Actual'"
        $script:failures++
    }
}

function Test-Route {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [bool]$ExpectedProfile,
        [bool]$ExpectedRemote,
        [string]$ExpectedWorkingDirectory = '',
        [string]$EnvironmentProfile = 'windows'
    )

    $plan = Get-CodexInvocationPlan `
        -Arguments $Arguments `
        -EnvironmentProfile $EnvironmentProfile `
        -CallerWorkingDirectory 'C:\caller\worktree'
    Assert-Equal "$Name profile" $plan.InjectProfile $ExpectedProfile
    Assert-Equal "$Name remote" $plan.UseManagedRemote $ExpectedRemote
    Assert-Equal "$Name working directory" ([string]$plan.ManagedWorkingDirectory) $ExpectedWorkingDirectory
}

Test-Route -Name 'root' -Arguments @() -ExpectedProfile $true -ExpectedRemote $true -ExpectedWorkingDirectory 'C:\caller\worktree'
Test-Route -Name 'root explicit cwd' -Arguments @('--cd', 'C:\src') -ExpectedProfile $true -ExpectedRemote $true
Test-Route -Name 'resume' -Arguments @('resume', '--last') -ExpectedProfile $true -ExpectedRemote $true -ExpectedWorkingDirectory 'C:\caller\worktree'
Test-Route -Name 'exec' -Arguments @('exec', 'summarize') -ExpectedProfile $true -ExpectedRemote $false
Test-Route -Name 'app server' -Arguments @('app-server', '--help') -ExpectedProfile $false -ExpectedRemote $false
Test-Route -Name 'explicit remote' -Arguments @('--remote=ws://127.0.0.1:4600') -ExpectedProfile $true -ExpectedRemote $false
Test-Route -Name 'explicit sandbox' -Arguments @('--sandbox', 'read-only') -ExpectedProfile $true -ExpectedRemote $false
Test-Route -Name 'non-Windows profile' -Arguments @() -ExpectedProfile $true -ExpectedRemote $false -EnvironmentProfile 'cluster'
Test-Route -Name 'explicit other profile' -Arguments @('--profile', 'other') -ExpectedProfile $false -ExpectedRemote $false

$env:CODEX_PROFILE = 'windows'
$script:hostStarts = 0
$script:codexArguments = @()
function codex-host {
    $script:hostStarts++
    $global:LASTEXITCODE = 0
}
function codex.cmd {
    $script:codexArguments = @($args)
}

$resolvedWorkingDirectory = (Resolve-Path -LiteralPath '.').ProviderPath
codex
Assert-Equal 'host starts' $script:hostStarts 1
Assert-Equal 'remote endpoint' $script:codexArguments[5] 'ws://127.0.0.1:4500'
Assert-Equal 'working directory flag' $script:codexArguments[6] '--cd'
Assert-Equal 'working directory value' $script:codexArguments[7] $resolvedWorkingDirectory

$script:codexCalled = $false
function codex-host {
    $global:LASTEXITCODE = 1
}
function codex.cmd {
    $script:codexCalled = $true
}
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
codex
$ErrorActionPreference = $previousPreference
Assert-Equal 'host failure is not silently bypassed' $script:codexCalled $false

if ($failures -gt 0) {
    exit 1
}

Write-Host 'Codex PowerShell wrapper routing tests passed.'
