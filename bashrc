# Environment variables and PATH setup

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

# Interactive shell setup
source ~/.config/bash/settings.bash
source ~/.config/bash/plugins.bash
source ~/.config/shell/aliases.sh
source ~/.config/bash/prompt.bash

if [ -f ~/.shellrc_local ]; then
    source ~/.shellrc_local
fi
if [ -f ~/.bashrc_local ]; then
    source ~/.bashrc_local
fi
