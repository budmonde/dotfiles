[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TestArguments
)

$ErrorActionPreference = 'Stop'
$profilesDirectory = Join-Path $PSScriptRoot 'profiles\windows'
$validProfiles = @(Get-ChildItem -LiteralPath $profilesDirectory -Filter '*.conf.yaml' -File |
    Where-Object { $_.Name -notlike '*.test.conf.yaml' } |
    ForEach-Object { $_.BaseName -replace '\.conf$', '' } |
    Sort-Object)
$profiles = @()
$forwardedArguments = @()
$forward = $false

foreach ($argument in $TestArguments) {
    if (-not $forward -and $argument -eq '--') {
        $forward = $true
        continue
    }
    if (-not $forward -and $argument.StartsWith('-')) {
        $forward = $true
    }
    if ($forward) {
        $forwardedArguments += $argument
    } else {
        $profiles += $argument
    }
}

if ($profiles.Count -eq 0) {
    Write-Host 'Available profiles:'
    foreach ($profile in $validProfiles) { Write-Host "  $profile" }
    exit 0
}

$runnerArguments = @('--root', $PSScriptRoot)
foreach ($profile in $profiles) {
    if ($profile -notin $validProfiles) {
        Write-Error "Unknown profile: $profile. Valid profiles: $($validProfiles -join ', ')"
    }
    $shared = Join-Path $PSScriptRoot "profiles\$profile.test.conf.yaml"
    $platform = Join-Path $profilesDirectory "$profile.test.conf.yaml"
    $found = $false
    foreach ($config in @($shared, $platform)) {
        if (Test-Path -LiteralPath $config -PathType Leaf) {
            $runnerArguments += '--config'
            $runnerArguments += $config
            $found = $true
        }
    }
    if (-not $found) {
        Write-Error "No test configuration found for profile: $profile"
    }
}

& git -C $PSScriptRoot submodule update --init --recursive envtest
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& uv run (Join-Path $PSScriptRoot 'envtest\envtest.py') @runnerArguments @forwardedArguments
exit $LASTEXITCODE
