$fnm = Get-Command fnm -ErrorAction SilentlyContinue
if (-not $fnm) {
    Write-Error "fnm not found on PATH"
    exit 1
}

fnm install --lts
fnm default lts-latest
