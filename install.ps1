$ErrorActionPreference = "Stop"

$COMMON_CONFIG = "install.conf.yaml"
$WINDOWS_CONFIG = "install.windows.conf.yaml"
$DOTBOT_DIR = "dotbot"
$DOTBOT_BIN = "bin/dotbot"
$BASEDIR = $PSScriptRoot

Set-Location $BASEDIR
git -C $DOTBOT_DIR submodule sync --quiet --recursive
git submodule update --init --recursive $DOTBOT_DIR

foreach ($PYTHON in ('python', 'python3')) {
    # Python redirects to Microsoft Store in Windows 10 when not installed
    if (& { $ErrorActionPreference = "SilentlyContinue"
            ![string]::IsNullOrEmpty((&$PYTHON -V))
            $ErrorActionPreference = "Stop" }) {
        $DOTBOT_PATH = Join-Path $BASEDIR -ChildPath $DOTBOT_DIR | Join-Path -ChildPath $DOTBOT_BIN
        &$PYTHON $DOTBOT_PATH -d $BASEDIR -c $COMMON_CONFIG $WINDOWS_CONFIG $Args
        return
    }
}
Write-Error "Error: Cannot find Python. Please install Python 3.8+ from https://python.org"
