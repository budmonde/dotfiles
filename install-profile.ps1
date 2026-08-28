# Install optional application profiles via dotbot.
# Usage: .\install-profile.ps1 <profile> [profile...] [dotbot-options...]
#
# Profiles are discovered dynamically from profiles\windows\*.conf.yaml.
# Matching profiles\<name>.before.conf.yaml and profiles\<name>.after.conf.yaml
# fragments are applied around the platform fragment when present.
#
# Examples:
#   .\install-profile.ps1 collab
#   .\install-profile.ps1 collab gaming
#   .\install-profile.ps1 collab --only link

$ErrorActionPreference = "Stop"

$DOTBOT_DIR = "dotbot"
$DOTBOT_BIN = "bin/dotbot"
$BASEDIR = $PSScriptRoot
$DOTBOT_FAILURE_OUTPUT_PLUGIN = Join-Path $BASEDIR "dotbot-plugins\failure_output.py"
$DOTBOT_INSTALL_DIR = "dotbot-plugins/install"
$DOTBOT_INSTALL_PLUGIN = Join-Path $BASEDIR "dotbot-plugins\install\install.py"
$DOTFILES_LOCAL_BIN = Join-Path $HOME ".local\bin"
$env:Path = "$DOTFILES_LOCAL_BIN;$env:Path"

$ProfilesDir = Join-Path $BASEDIR "profiles\windows"
$ValidProfiles = @(Get-ChildItem -LiteralPath $ProfilesDir -Filter "*.conf.yaml" -File |
    ForEach-Object { $_.BaseName -replace '\.conf$', '' } |
    Sort-Object)

$Profiles = @()
$DotbotArgs = @()
$ForwardDotbotArgs = $false
foreach ($argument in $Args) {
    if (-not $ForwardDotbotArgs) {
        if ($argument -eq '--') {
            $ForwardDotbotArgs = $true
            continue
        }
        if ($argument.StartsWith('-')) {
            $ForwardDotbotArgs = $true
        }
    }
    if ($ForwardDotbotArgs) {
        $DotbotArgs += $argument
    } else {
        $Profiles += $argument
    }
}

if ($Profiles.Count -eq 0) {
    Write-Host "Available profiles:"
    foreach ($p in $ValidProfiles) { Write-Host "  $p" }
    Write-Host "`nUsage: .\install-profile.ps1 <profile> [profile...] [dotbot-options...]"
    exit 0
}

$Configs = @()
foreach ($profile in $Profiles) {
    if ($profile -notin $ValidProfiles) {
        Write-Error "Unknown profile: $profile. Valid profiles: $($ValidProfiles -join ', ')"
    }
    $conf = "profiles\windows\$profile.conf.yaml"
    if (!(Test-Path (Join-Path $BASEDIR $conf))) {
        Write-Error "Config not found: $conf"
    }
    $beforeConf = "profiles\$profile.before.conf.yaml"
    if (Test-Path (Join-Path $BASEDIR $beforeConf)) {
        $Configs += $beforeConf
    }
    $Configs += $conf
    $afterConf = "profiles\$profile.after.conf.yaml"
    if (Test-Path (Join-Path $BASEDIR $afterConf)) {
        $Configs += $afterConf
    }
}

Set-Location $BASEDIR
git submodule sync --quiet --recursive -- $DOTBOT_DIR $DOTBOT_INSTALL_DIR
git submodule update --init --recursive -- $DOTBOT_DIR $DOTBOT_INSTALL_DIR

foreach ($PYTHON in ('python', 'python3')) {
    if (& { $ErrorActionPreference = "SilentlyContinue"
            ![string]::IsNullOrEmpty((&$PYTHON -V))
            $ErrorActionPreference = "Stop" }) {
        $DOTBOT_PATH = Join-Path $BASEDIR -ChildPath $DOTBOT_DIR | Join-Path -ChildPath $DOTBOT_BIN
        &$PYTHON $DOTBOT_PATH --plugin $DOTBOT_FAILURE_OUTPUT_PLUGIN --plugin $DOTBOT_INSTALL_PLUGIN -d $BASEDIR -c @Configs @DotbotArgs
        return
    }
}
Write-Error "Error: Cannot find Python. Please install Python 3.8+ from https://python.org"
