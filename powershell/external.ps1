# XDG Base Directory Specification
$env:XDG_CONFIG_HOME = "$HOME\.config"
$env:XDG_DATA_HOME = "$HOME\.local\share"
$env:XDG_STATE_HOME = "$HOME\.local\state"
$env:XDG_CACHE_HOME = "$HOME\.cache"

# Tool-specific overrides (for tools that don't check XDG)
$env:INPUTRC = "$env:XDG_CONFIG_HOME\readline\inputrc"
$env:CLAUDE_CONFIG_DIR = "$env:XDG_CONFIG_HOME\claude"
$env:PYTHONSTARTUP = "$env:XDG_CONFIG_HOME\python\pythonrc"
$env:IPYTHONDIR = "$env:XDG_CONFIG_HOME\ipython"
$env:JUPYTER_CONFIG_DIR = "$env:XDG_CONFIG_HOME\jupyter"
$env:NPM_CONFIG_USERCONFIG = "$env:XDG_CONFIG_HOME\npm\npmrc"
$env:GOPATH = "$env:XDG_DATA_HOME\go"
$env:GOMODCACHE = "$env:XDG_CACHE_HOME\go\mod"
$env:KERAS_HOME = "$env:XDG_DATA_HOME\keras"
$env:DOCKER_CONFIG = "$env:XDG_CONFIG_HOME\docker"
$env:BUN_INSTALL_CACHE_DIR = "$env:XDG_CACHE_HOME\bun"
$env:CUPY_CACHE_DIR = "$env:XDG_CACHE_HOME\cupy"
$env:MPLCONFIGDIR = "$env:XDG_CACHE_HOME\matplotlib"
$env:LESSHISTFILE = "$env:XDG_STATE_HOME\less\history"
$env:NODE_REPL_HISTORY = "$env:XDG_STATE_HOME\node\history"
$env:PYTHONHISTFILE = "$env:XDG_STATE_HOME\python\history"

# opencode: skip ~/.claude/skills and ~/.agents/skills discovery (IT-pushed
# skills like managing-omnistation and nvinfo-cli land there). Pull desired
# skills into ~/.config/opencode/skills/ individually instead.
$env:OPENCODE_DISABLE_EXTERNAL_SKILLS = 1

# opencode: disable built-in terminal title writer; the terminal-title.tsx
# TUI plugin owns the title and emits the `OC | <cwd>[ : <branch>] | <session>`
# pattern matching the NVIM/PS1 title scheme.
$env:OPENCODE_DISABLE_TERMINAL_TITLE = 1

$env:VIRTUAL_ENV_DISABLE_PROMPT = 1

if (Get-Command nvim -ErrorAction SilentlyContinue) {
    $env:EDITOR = 'nvim'
} else {
    $env:EDITOR = 'vim'
}
