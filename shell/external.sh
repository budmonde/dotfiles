# Platform detection
if [ -n "$WSL_DISTRO_NAME" ]; then
    export IS_WSL=1
fi
if [[ "$OSTYPE" == darwin* ]]; then
    export IS_MACOS=1
fi

export PYTHONSTARTUP="${XDG_CONFIG_HOME:-$HOME/.config}/python/pythonrc"
export JUPYTER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jupyter"
export GOPATH="${XDG_DATA_HOME:-$HOME/.local/share}/go"
export GOMODCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/go/mod"
export TEXLIVE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/texlive"
export VIRTUAL_ENV_DISABLE_PROMPT=1
export BUN_INSTALL_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bun"

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
