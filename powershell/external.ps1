# XDG Base Directory Specification
$env:XDG_CONFIG_HOME = "$HOME\.config"
$env:XDG_DATA_HOME = "$HOME\.local\share"
$env:XDG_STATE_HOME = "$HOME\.local\state"
$env:XDG_CACHE_HOME = "$HOME\.cache"

# Tool-specific overrides (for tools that don't check XDG)
$env:PYTHONSTARTUP = "$env:XDG_CONFIG_HOME\python\pythonrc"
$env:NPM_CONFIG_USERCONFIG = "$env:XDG_CONFIG_HOME\npm\npmrc"
$env:GOPATH = "$env:XDG_DATA_HOME\go"
$env:GOMODCACHE = "$env:XDG_CACHE_HOME\go\mod"
$env:DOCKER_CONFIG = "$env:XDG_CONFIG_HOME\docker"
$env:BUN_INSTALL_CACHE_DIR = "$env:XDG_CACHE_HOME\bun"

$env:VIRTUAL_ENV_DISABLE_PROMPT = 1

if (Get-Command nvim -ErrorAction SilentlyContinue) {
    $env:EDITOR = 'nvim'
} else {
    $env:EDITOR = 'vim'
}
