$hostPath = Join-Path $PSScriptRoot 'codex-host.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $hostPath,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_.Message }
    exit 1
}

$hostLaunches = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Start-Process' -and
        $node.Extent.Text -match "'app-server'"
}, $true))

if ($hostLaunches.Count -ne 1) {
    Write-Error "Expected one App Server launch command, found $($hostLaunches.Count)."
    exit 1
}

if ($hostLaunches[0].Extent.Text -notmatch '(?m)-WorkingDirectory\s+\$HOME') {
    Write-Error 'The App Server launch must use $HOME instead of inheriting the caller working directory.'
    exit 1
}

$requiredRuntimeDefaults = @(
    'sandbox_mode=workspace-write'
    'approval_policy=on-request'
    'approvals_reviewer=auto_review'
)

foreach ($runtimeDefault in $requiredRuntimeDefaults) {
    if ($hostLaunches[0].Extent.Text -notmatch [regex]::Escape($runtimeDefault)) {
        Write-Error "The App Server launch must set $runtimeDefault."
        exit 1
    }
}

$hostSource = Get-Content -Raw $hostPath
$monitorFailureGuards = [regex]::Matches(
    $hostSource,
    'if \(-not \(Start-NotificationMonitor\)\) \{[^}]*return \$false',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if ($monitorFailureGuards.Count -ne 2) {
    Write-Error 'Managed mode must fail closed when the notification and policy monitor cannot start.'
    exit 1
}

Write-Host 'Codex host launch policy tests passed.'
