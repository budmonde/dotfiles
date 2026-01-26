# Environment variables and PATH setup

source ~/.shell/functions.sh
# PATH setup
source ~/.shell/bootstrap.sh
# External tool environment variables
source ~/.shell/external.sh

if [ -f ~/.shellenv_local ]; then
    source ~/.shellenv_local
fi

# Interactive shell setup
source ~/.bash/settings.bash
source ~/.bash/plugins.bash
source ~/.shell/aliases.sh
source ~/.bash/prompt.bash

if [ -f ~/.shellrc_local ]; then
    source ~/.shellrc_local
fi
if [ -f ~/.bashrc_local ]; then
    source ~/.bashrc_local
fi
