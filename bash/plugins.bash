###############################################################################
# Fuzzy Finder (fzf)
###############################################################################
# Add to fzf to path
path_append $HOME/.shell/plugins/fzf/bin
# Auto-completion
[[ $- == *i* ]] && source "$HOME/.shell/plugins/fzf/shell/completion.bash" 2> /dev/null
# Key-binds
source "$HOME/.shell/plugins/fzf/shell/key-bindings.bash"
