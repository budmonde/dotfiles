[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TestArguments
)

$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'envtest\envtest.py'
$commonConfig = Join-Path $PSScriptRoot 'test.conf.yaml'
$platformConfig = Join-Path $PSScriptRoot 'test.windows.conf.yaml'

& git -C $PSScriptRoot submodule update --init --recursive envtest
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& uv run $runner --root $PSScriptRoot --config $commonConfig --config $platformConfig @TestArguments
exit $LASTEXITCODE
