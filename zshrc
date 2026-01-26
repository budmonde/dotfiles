# zshrc is not loaded for non-interactive shells

source ~/.zsh/settings.zsh
source ~/.zsh/plugins.zsh
source ~/.shell/aliases.sh
source ~/.zsh/prompt.zsh

if [ -f ~/.shellrc_local ]; then
    source ~/.shellrc_local
fi
if [ -f ~/.zshrc_local ]; then
    source ~/.zshrc_local
fi
