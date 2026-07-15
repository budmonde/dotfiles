$aliasesPath = Join-Path $PSScriptRoot '..\..\powershell\aliases.ps1'
. $aliasesPath

$failures = 0

function Assert-Equal {
    param(
        [string]$Name,
        $Actual,
        $Expected
    )

    if ($Actual -ne $Expected) {
        Write-Error "$Name`: expected '$Expected', got '$Actual'"
        $script:failures++
    }
}

function Test-Route {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$ExpectedSubcommand,
        [bool]$ExpectedProfile,
        [bool]$ExpectedRemote,
        [string]$ExpectedManagedSandbox = '',
        [bool]$ExpectedExplicitProfile = $false,
        [bool]$ExpectedExplicitRemote = $false,
        [bool]$ExpectedExplicitSandbox = $false
    )

    $plan = Get-CodexInvocationPlan -Arguments $Arguments -EnvironmentProfile 'windows'
    Assert-Equal "$Name subcommand" $plan.Subcommand $ExpectedSubcommand
    Assert-Equal "$Name profile" $plan.InjectProfile $ExpectedProfile
    Assert-Equal "$Name remote" $plan.UseManagedRemote $ExpectedRemote
    Assert-Equal "$Name managed sandbox" ([string]$plan.ManagedSandbox) $ExpectedManagedSandbox
    Assert-Equal "$Name explicit profile" $plan.HasExplicitProfile $ExpectedExplicitProfile
    Assert-Equal "$Name explicit remote" $plan.HasExplicitRemote $ExpectedExplicitRemote
    Assert-Equal "$Name explicit sandbox" $plan.HasExplicitSandbox $ExpectedExplicitSandbox
}

Test-Route -Name 'root' -Arguments @('--cd', 'C:\src') -ExpectedSubcommand '' -ExpectedProfile $true -ExpectedRemote $true -ExpectedManagedSandbox 'workspace-write'
Test-Route -Name 'resume' -Arguments @('resume', '--last') -ExpectedSubcommand 'resume' -ExpectedProfile $true -ExpectedRemote $true -ExpectedManagedSandbox 'workspace-write'
Test-Route -Name 'exec' -Arguments @('exec', 'summarize') -ExpectedSubcommand 'exec' -ExpectedProfile $true -ExpectedRemote $false
Test-Route -Name 'review' -Arguments @('review', '--base', 'main') -ExpectedSubcommand 'review' -ExpectedProfile $true -ExpectedRemote $false
Test-Route -Name 'app-server' -Arguments @('app-server', '--help') -ExpectedSubcommand 'app-server' -ExpectedProfile $false -ExpectedRemote $false
Test-Route -Name 'doctor' -Arguments @('doctor') -ExpectedSubcommand 'doctor' -ExpectedProfile $false -ExpectedRemote $false
Test-Route -Name 'version' -Arguments @('--version') -ExpectedSubcommand '' -ExpectedProfile $false -ExpectedRemote $false
Test-Route -Name 'explicit profile' -Arguments @('-p', 'other', 'resume') -ExpectedSubcommand 'resume' -ExpectedProfile $false -ExpectedRemote $true -ExpectedExplicitProfile $true
Test-Route -Name 'explicit Windows profile' -Arguments @('-p', 'windows', 'resume') -ExpectedSubcommand 'resume' -ExpectedProfile $false -ExpectedRemote $true -ExpectedManagedSandbox 'workspace-write' -ExpectedExplicitProfile $true
Test-Route -Name 'explicit remote' -Arguments @('--remote=ws://127.0.0.1:4600', 'resume') -ExpectedSubcommand 'resume' -ExpectedProfile $true -ExpectedRemote $false -ExpectedExplicitRemote $true
Test-Route -Name 'explicit sandbox' -Arguments @('--sandbox', 'read-only', 'resume') -ExpectedSubcommand 'resume' -ExpectedProfile $true -ExpectedRemote $false -ExpectedExplicitSandbox $true

if ($failures -gt 0) {
    exit 1
}

Write-Host 'Codex PowerShell wrapper routing tests passed.'
