# zshenv is loaded for interactive (before zshrc) and non-interactive shells

source ~/.shell/functions.sh
# PATH setup
source ~/.shell/bootstrap.sh
# External tool environment variables
source ~/.shell/external.sh

if [ -f ~/.shellenv_local ]; then
    source ~/.shellenv_local
fi
