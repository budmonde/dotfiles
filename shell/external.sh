# Platform detection
if [ -n "$WSL_DISTRO_NAME" ]; then
    export IS_WSL=1
fi
if [[ "$OSTYPE" == darwin* ]]; then
    export IS_MACOS=1
fi

export PYTHONSTARTUP=$HOME/.pythonrc
export NVM_DIR="$HOME/.shell/plugins/nvm"
export GOPATH="$HOME/.go"

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
