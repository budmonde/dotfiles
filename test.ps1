$ErrorActionPreference = "Stop"

$BASEDIR = $PSScriptRoot
$ORCHESTRATOR = Join-Path $BASEDIR "orchestrate.py"
$DOTFILES_LOCAL_BIN = Join-Path $HOME ".local\bin"
$env:Path = "$DOTFILES_LOCAL_BIN;$env:Path"

foreach ($PYTHON in ('python', 'python3')) {
    if (& { $ErrorActionPreference = "SilentlyContinue"
            ![string]::IsNullOrEmpty((&$PYTHON -V))
            $ErrorActionPreference = "Stop" }) {
        &$PYTHON $ORCHESTRATOR test @Args
        exit $LASTEXITCODE
    }
}
Write-Error "Error: Cannot find Python. Please install Python 3.8+ from https://python.org"
