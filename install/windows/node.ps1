# Refresh PATH from registry so recently-installed winget binaries are visible
$env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH', 'User')

$fnm = Get-Command fnm -ErrorAction SilentlyContinue
if (-not $fnm) {
    Write-Error "fnm not found on PATH"
    exit 1
}

fnm install --lts
fnm default lts-latest
