# Environment variables and PATH setup

source ~/.config/shell/functions.sh
# PATH setup
source ~/.config/shell/bootstrap.sh
# External tool environment variables
source ~/.config/shell/external.sh

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
