# Import Functions
source ~/.shell/functions.sh
# Settings
source ~/.bash/settings.bash
# Bootstrap
source ~/.shell/bootstrap.sh
# Plug-ins
source ~/.bash/plugins.bash
# Aliases
source ~/.shell/aliases.sh
# Prompt
source ~/.bash/prompt.bash
# Load local configurations
if [ -f ~/.bashrc_local_after ]; then
    source ~/.bashrc_local_after
fi
