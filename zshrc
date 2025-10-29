# Import Functions
source ~/.shell/functions.sh
# Settings
source ~/.zsh/settings.zsh
# Bootstrap
source ~/.shell/bootstrap.sh
# External
source ~/.shell/external.sh
# Plug-ins
source ~/.zsh/plugins.zsh
# Aliases
source ~/.shell/aliases.sh
# Prompt
source ~/.zsh/prompt.zsh
# Load local configurations
if [ -f ~/.shell_local_after ]; then
    source ~/.shell_local_after
fi
if [ -f ~/.zshrc_local_after ]; then
    source ~/.zshrc_local_after
fi
