# zshenv is loaded for interactive (before zshrc) and non-interactive shells

source ~/.config/shell/functions.sh

# Early local env: HOME correction, secrets, cluster detection, XDG redirects
# Must run before external.sh so $HOME and XDG vars are correct for downstream.
if [ -f ~/.shellenv_local_early ]; then
    source ~/.shellenv_local_early
fi

# External tool environment variables
source ~/.config/shell/external.sh
# PATH setup
source ~/.config/shell/bootstrap.sh

# Late local env: overrides that depend on the base dotfiles setup
if [ -f ~/.shellenv_local ]; then
    source ~/.shellenv_local
fi
