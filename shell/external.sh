# Platform detection
if [ -n "$WSL_DISTRO_NAME" ]; then
    export IS_WSL=1
fi
if [[ "$OSTYPE" == darwin* ]]; then
    export IS_MACOS=1
fi

# XDG Base Directory Specification paths
# https://specifications.freedesktop.org/basedir/latest/
export INPUTRC="${XDG_CONFIG_HOME:-$HOME/.config}/readline/inputrc"
export CLAUDE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude"
export PYTHONSTARTUP="${XDG_CONFIG_HOME:-$HOME/.config}/python/pythonrc"
export IPYTHONDIR="${XDG_CONFIG_HOME:-$HOME/.config}/ipython"
export JUPYTER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jupyter"
export NPM_CONFIG_USERCONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/npm/npmrc"
export GOPATH="${XDG_DATA_HOME:-$HOME/.local/share}/go"
export GOMODCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/go/mod"
export TEXLIVE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/texlive"
export KERAS_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/keras"
export BUN_INSTALL_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bun"
export CUPY_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cupy"
export LESSHISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/less/history"
export NODE_REPL_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/node/history"
export PYTHONHISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/python/history"

export VIRTUAL_ENV_DISABLE_PROMPT=1

if command -v nvim &> /dev/null; then
    export EDITOR=nvim
else
    export EDITOR=vim
fi

if [ -n "$IS_WSL" ]; then
    export PDF_VIEWER=wslview
    if [ -z "${WINDOWS_USER:-}" ]; then
        export WINDOWS_USER=$(powershell.exe -NoProfile -Command \
            "[Environment]::UserName" | tr -d '\r\n')
    fi
    export WINDOWS_HOME="/mnt/c/Users/$WINDOWS_USER"
fi
