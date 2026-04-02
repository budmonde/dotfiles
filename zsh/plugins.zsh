###############################################################################
# Syntax highlighting
###############################################################################
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
source ~/.config/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
###############################################################################
# Autosuggestions
###############################################################################
source ~/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

###############################################################################
# Fuzzy Finder (fzf)
###############################################################################
[[ $- == *i* ]] && source "$HOME/.config/shell/plugins/fzf/shell/completion.zsh" 2>/dev/null
source "$HOME/.config/shell/plugins/fzf/shell/key-bindings.zsh" 2>/dev/null

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
    eval $(dircolors =(cat ~/.config/shell/plugins/dircolors-solarized/dircolors.256dark ~/.config/shell/dircolors.extra))
fi
