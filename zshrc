# Import Functions
source ~/.shell/functions.sh
# Settings
source ~/.zsh/settings.zsh
# Bootstrap
source ~/.shell/bootstrap.sh
# Plug-ins
source ~/.zsh/plugins.zsh
# Aliases
source ~/.shell/aliases.sh
# Prompt
source ~/.zsh/prompt.zsh
# Load local configurations
if [ -f ~/.zshrc_local_after ]; then
    source ~/.zshrc_local_after
fi
