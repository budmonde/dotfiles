$hostPath = Join-Path $PSScriptRoot 'codex-host.ps1'
$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $hostPath,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_.Message }
    exit 1
}

. $hostPath -LibraryMode

$failures = 0

function Assert-Equal {
    param($Name, $Actual, $Expected)

    if ($Actual -ne $Expected) {
        Write-Error "$Name`: expected '$Expected', got '$Actual'"
        $script:failures++
    }
}

function Assert-SequenceEqual {
    param($Name, [object[]]$Actual, [object[]]$Expected)

    Assert-Equal "$Name count" $Actual.Count $Expected.Count
    for ($index = 0; $index -lt [Math]::Min($Actual.Count, $Expected.Count); $index++) {
        Assert-Equal "$Name item $index" $Actual[$index] $Expected[$index]
    }
}

Assert-Equal 'endpoint' $Endpoint 'ws://127.0.0.1:4500'
Assert-SequenceEqual 'App Server arguments' (Get-AppServerArguments) @(
    'app-server', '--listen', 'ws://127.0.0.1:4500'
)
Assert-SequenceEqual 'monitor arguments' (Get-MonitorArguments) @(
    $MonitorPath, '--endpoint', 'ws://127.0.0.1:4500'
)

$savedBaseConfigPath = $BaseConfigPath
$savedProfileConfigPath = $ProfileConfigPath
$BaseConfigPath = $MonitorPath
$ProfileConfigPath = $MonitorPath
if (-not (Test-WindowsConfigReady)) {
    Write-Error 'Identical installed config content must pass the preflight.'
    $failures++
}
$ProfileConfigPath = $hostPath
if (Test-WindowsConfigReady) {
    Write-Error 'Different installed config content must fail the preflight.'
    $failures++
}
$BaseConfigPath = $savedBaseConfigPath
$ProfileConfigPath = $savedProfileConfigPath

if (-not (Test-AppServerCommandLine -CommandLine 'codex.exe app-server --listen ws://127.0.0.1:4500')) {
    Write-Error 'The managed App Server command line must be recognized.'
    $failures++
}
if (Test-AppServerCommandLine -CommandLine 'codex.exe app-server --listen ws://0.0.0.0:4500') {
    Write-Error 'Only the exact loopback listener may be managed.'
    $failures++
}

$source = Get-Content -Raw -LiteralPath $hostPath
if ($source -notmatch 'Test-WindowsConfigReady') {
    Write-Error 'The host must refuse to start when the installed Windows config is not the base config.'
    $failures++
}
foreach ($forbidden in @(
    'manifest',
    'fingerprint',
    'sourceHash',
    'healthFile',
    'WindowsProfileConfigPath',
    'Resolve-CodexNativeExecutable',
    'unix://'
)) {
    if ($source -match [regex]::Escape($forbidden)) {
        Write-Error "Supervisor still contains retired machinery: $forbidden"
        $failures++
    }
}

if ($failures -gt 0) {
    exit 1
}

Write-Host 'Codex host policy tests passed.'
