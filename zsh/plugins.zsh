###############################################################################
# Fuzzy Finder (fzf)
###############################################################################
# Add to fzf to path
path_append $HOME/.shell/plugins/fzf/bin
# Auto-completion
[[ $- == *i* ]] && source "$HOME/.shell/plugins/fzf/shell/completion.zsh" 2> /dev/null
# Key-binds
source "$HOME/.shell/plugins/fzf/shell/key-bindings.zsh"
###############################################################################
# Syntax highlighting
###############################################################################
source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
###############################################################################
# Autosuggestions
###############################################################################
source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
