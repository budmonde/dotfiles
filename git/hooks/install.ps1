$env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH', 'User')
fnm env --shell powershell | Out-String | Invoke-Expression

$hooksDir = Split-Path -Parent $PSCommandPath
Push-Location $hooksDir
try {
    npm install --silent --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        Write-Error "npm install in git/hooks failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}
