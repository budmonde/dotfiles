$env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH', 'User')
fnm env --shell powershell | Out-String | Invoke-Expression

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$hooksDir = Join-Path $repoRoot 'config\git\hooks'
Push-Location $hooksDir
try {
    npm install --silent --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        Write-Error "npm install in config/git/hooks failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}
