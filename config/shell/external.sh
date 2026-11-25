# Platform detection
if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    export IS_WSL=1
fi
case "${OSTYPE:-}" in
    darwin*) export IS_MACOS=1 ;;
esac

export INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"
export CLAUDE_CONFIG_DIR="$XDG_CONFIG_HOME/claude"
export PYTHONSTARTUP="$XDG_CONFIG_HOME/python/pythonrc"
export IPYTHONDIR="$XDG_CONFIG_HOME/ipython"
export JUPYTER_CONFIG_DIR="$XDG_CONFIG_HOME/jupyter"
export JUPYTER_DATA_DIR="$XDG_DATA_HOME/jupyter"
export CODEX_HOME="$XDG_CONFIG_HOME/codex"
export COPILOT_HOME="$XDG_STATE_HOME/copilot"
export PARALLEL_HOME="$XDG_STATE_HOME/parallel"
export FNM_DIR="$XDG_DATA_HOME/fnm"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export GOPATH="$XDG_DATA_HOME/go"
export GOMODCACHE="$XDG_CACHE_HOME/go/mod"
export KERAS_HOME="$XDG_DATA_HOME/keras"
export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun"
export CUPY_CACHE_DIR="$XDG_CACHE_HOME/cupy"
export MPLCONFIGDIR="$XDG_CACHE_HOME/matplotlib"
export LESSHISTFILE="$XDG_STATE_HOME/less/history"
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node/history"
export PYTHONHISTFILE="$XDG_STATE_HOME/python/history"
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export UV_TOOL_BIN_DIR="$HOME/.local/bin"

export VIRTUAL_ENV_DISABLE_PROMPT=1

if command -v nvim >/dev/null 2>&1; then
    export EDITOR=nvim
else
    export EDITOR=vim
fi

if [ -n "${IS_WSL:-}" ]; then
    if command -v wslview >/dev/null 2>&1; then
        export PDF_VIEWER="${PDF_VIEWER:-wslview}"
    fi
    if [ -z "${WINDOWS_USER:-}" ] && command -v powershell.exe >/dev/null 2>&1; then
        WINDOWS_USER="$(powershell.exe -NoProfile -Command \
            "[Environment]::UserName" | tr -d '\r\n')"
        export WINDOWS_USER
    fi
    if [ -n "${WINDOWS_USER:-}" ]; then
        export WINDOWS_HOME="/mnt/c/Users/$WINDOWS_USER"
    fi
fi
