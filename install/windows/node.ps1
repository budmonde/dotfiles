param(
    [Parameter(Mandatory)]
    [string] $VersionFile
)

$nodeVersionFile = (Resolve-Path -LiteralPath $VersionFile).Path
$nodeVersion = (Get-Content -Raw -LiteralPath $nodeVersionFile).Trim()
$fnm = Get-Command fnm -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($nodeVersion)) {
    Write-Error "$nodeVersionFile is empty."
    exit 1
}

if (-not $fnm) {
    Write-Error "fnm not found on PATH"
    exit 1
}

fnm install $nodeVersion
if ($LASTEXITCODE -ne 0) {
    Write-Error "fnm failed to install Node.js $nodeVersion."
    exit $LASTEXITCODE
}

fnm default $nodeVersion
if ($LASTEXITCODE -ne 0) {
    Write-Error "fnm failed to select Node.js $nodeVersion as the default."
    exit $LASTEXITCODE
}
