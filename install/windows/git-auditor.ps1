$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pluginDir = Join-Path $repoRoot 'config\agents\plugins\git-auditor'
Push-Location $pluginDir
try {
    npm install --silent --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        Write-Error "npm install in config/agents/plugins/git-auditor failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}
