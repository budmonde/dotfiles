###############################################################################
# Syntax highlighting
###############################################################################
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
###############################################################################
# Autosuggestions
###############################################################################
source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

###############################################################################
# Fuzzy Finder (fzf)
###############################################################################
[[ $- == *i* ]] && source "$HOME/.shell/plugins/fzf/shell/completion.zsh" 2>/dev/null
source "$HOME/.shell/plugins/fzf/shell/key-bindings.zsh" 2>/dev/null

###############################################################################
# fnm (Fast Node Manager)
###############################################################################
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi

###############################################################################
# Color Theme
###############################################################################
if [[ "$(tput colors)" == "256" ]]; then
    eval $(dircolors =(cat ~/.shell/plugins/dircolors-solarized/dircolors.256dark ~/.shell/dircolors.extra))
fi
