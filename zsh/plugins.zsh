###############################################################################
# Syntax highlighting
###############################################################################
source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
###############################################################################
# Autosuggestions
###############################################################################
source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

###############################################################################
# Color Theme
###############################################################################
if [[ "$(tput colors)" == "256" ]]; then
    eval $(dircolors =(cat ~/.shell/plugins/dircolors-solarized/dircolors.256dark ~/.shell/dircolors.extra))
fi
