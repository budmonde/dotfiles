$uvCommand = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue
if ($null -eq $uvCommand) {
    $wingetUv = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\uv.exe'
    if (Test-Path -LiteralPath $wingetUv) {
        $uvPath = $wingetUv
    } else {
        Write-Error 'Cannot find uv after installing astral-sh.uv'
        exit 1
    }
} else {
    $uvPath = $uvCommand.Path
}

& $uvPath tool install --force --refresh-package shellver 'git+https://github.com/budmonde/shellver.git@main'
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
