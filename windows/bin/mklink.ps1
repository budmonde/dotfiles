# Create a symlink, with parent directory creation. Requires admin.
# Usage: mklink.ps1 [-Link <path> | -Env <var>\subpath | -Special <folder>\subpath] -Target <path>
#
# -Link: literal path
# -Env: expands %VAR%\subpath (e.g., "%LOCALAPPDATA%\Foo\bar.json")
# -Special: expands .NET special folder (e.g., "MyDocuments\Foo\bar.ps1")
param(
    [string]$Link,
    [string]$Env,
    [string]$Special,
    [Parameter(Mandatory)][string]$Target
)

if ($Special) {
    $parts = $Special -split '\\', 2
    $root = [Environment]::GetFolderPath($parts[0])
    if (-not $root) { Write-Error "Unknown special folder: $($parts[0])"; exit 1 }
    $Link = if ($parts.Length -gt 1) { Join-Path $root $parts[1] } else { $root }
} elseif ($Env) {
    $Link = [Environment]::ExpandEnvironmentVariables($Env)
}

if (-not $Link) {
    Write-Error "Must specify -Link, -Env, or -Special"
    exit 1
}

$dir = Split-Path $Link
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
if (Test-Path $Link) {
    Remove-Item $Link -Force
}

$resolved = Resolve-Path $Target
cmd /c mklink $Link $resolved
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create symlink: $Link -> $resolved"
    exit 1
}
