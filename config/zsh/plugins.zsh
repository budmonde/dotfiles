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
[[ $- == *i* ]] && source "${XDG_DATA_HOME:-$HOME/.local/share}/fzf/shell/completion.zsh" 2>/dev/null
source "${XDG_DATA_HOME:-$HOME/.local/share}/fzf/shell/key-bindings.zsh" 2>/dev/null

###############################################################################
# Color Theme
###############################################################################
if [[ "$(tput colors)" == "256" ]]; then
    eval $(dircolors =(cat ~/.config/shell/plugins/dircolors-solarized/dircolors.256dark ~/.config/shell/dircolors.extra))
fi
