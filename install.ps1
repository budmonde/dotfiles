$ErrorActionPreference = "Stop"

$BEFORE_CONFIG = "install.before.conf.yaml"
$WINDOWS_CONFIG = "install.windows.conf.yaml"
$AFTER_CONFIG = "install.after.conf.yaml"
$DOTBOT_DIR = "dotbot"
$DOTBOT_BIN = "bin/dotbot"
$BASEDIR = $PSScriptRoot
$DOTBOT_FAILURE_OUTPUT_PLUGIN = Join-Path $BASEDIR "dotbot-plugins\failure_output.py"
$DOTBOT_INSTALL_DIR = "dotbot-plugins/install"
$DOTBOT_INSTALL_PLUGIN = Join-Path $BASEDIR "dotbot-plugins\install\install.py"
$DOTFILES_LOCAL_BIN = Join-Path $HOME ".local\bin"
$env:Path = "$DOTFILES_LOCAL_BIN;$env:Path"

Set-Location $BASEDIR
git submodule sync --quiet --recursive -- $DOTBOT_DIR $DOTBOT_INSTALL_DIR
git submodule update --init --recursive -- $DOTBOT_DIR $DOTBOT_INSTALL_DIR

foreach ($PYTHON in ('python', 'python3')) {
    # Python redirects to Microsoft Store in Windows 10 when not installed
    if (& { $ErrorActionPreference = "SilentlyContinue"
            ![string]::IsNullOrEmpty((&$PYTHON -V))
            $ErrorActionPreference = "Stop" }) {
        $DOTBOT_PATH = Join-Path $BASEDIR -ChildPath $DOTBOT_DIR | Join-Path -ChildPath $DOTBOT_BIN
        &$PYTHON $DOTBOT_PATH --plugin $DOTBOT_FAILURE_OUTPUT_PLUGIN --plugin $DOTBOT_INSTALL_PLUGIN -d $BASEDIR -c $BEFORE_CONFIG $WINDOWS_CONFIG $AFTER_CONFIG $Args
        return
    }
}
Write-Error "Error: Cannot find Python. Please install Python 3.8+ from https://python.org"
