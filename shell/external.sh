export PYTHONSTARTUP=$HOME/.pythonrc
export NVM_DIR="$HOME/.shell/plugins/nvm"

if command -v nvim &> /dev/null; then
    export EDITOR=nvim
else
    export EDITOR=vim
fi
