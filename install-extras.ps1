# Install optional application profiles via dotbot.
# Usage: .\install-extras.ps1 <profile> [profile...]
# Profiles: collab, gaming, creative, gamedev
#
# Examples:
#   .\install-extras.ps1 collab
#   .\install-extras.ps1 collab gaming

$ErrorActionPreference = "Stop"

$DOTBOT_DIR = "dotbot"
$DOTBOT_BIN = "bin/dotbot"
$BASEDIR = $PSScriptRoot

$ValidProfiles = @("collab", "creative", "gamedev", "gaming", "iqa", "research", "wsl")

if ($Args.Count -eq 0) {
    Write-Host "Available profiles:"
    foreach ($p in $ValidProfiles) { Write-Host "  $p" }
    Write-Host "`nUsage: .\install-extras.ps1 <profile> [profile...]"
    exit 0
}

$Configs = @()
foreach ($profile in $Args) {
    if ($profile -notin $ValidProfiles) {
        Write-Error "Unknown profile: $profile. Valid profiles: $($ValidProfiles -join ', ')"
    }
    $conf = "windows\extras\$profile.conf.yaml"
    if (!(Test-Path (Join-Path $BASEDIR $conf))) {
        Write-Error "Config not found: $conf"
    }
    $Configs += $conf
}

Set-Location $BASEDIR
git -C $DOTBOT_DIR submodule sync --quiet --recursive
git submodule update --init --recursive $DOTBOT_DIR

foreach ($PYTHON in ('python', 'python3')) {
    if (& { $ErrorActionPreference = "SilentlyContinue"
            ![string]::IsNullOrEmpty((&$PYTHON -V))
            $ErrorActionPreference = "Stop" }) {
        $DOTBOT_PATH = Join-Path $BASEDIR -ChildPath $DOTBOT_DIR | Join-Path -ChildPath $DOTBOT_BIN
        &$PYTHON $DOTBOT_PATH -d $BASEDIR -c @Configs
        return
    }
}
Write-Error "Error: Cannot find Python. Please install Python 3.8+ from https://python.org"
