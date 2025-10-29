# Import Functions
source ~/.shell/functions.sh
# Settings
source ~/.bash/settings.bash
# Bootstrap
source ~/.shell/bootstrap.sh
# External settings
source ~/.shell/external.sh
# Plug-ins
source ~/.bash/plugins.bash
# Aliases
source ~/.shell/aliases.sh
# Prompt
source ~/.bash/prompt.bash
# Load local configurations
if [ -f ~/.shell_local_after ]; then
    source ~/.shell_local_after
fi
if [ -f ~/.bashrc_local_after ]; then
    source ~/.bashrc_local_after
fi
