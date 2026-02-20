###############################################################################
# Fuzzy Finder (fzf)
###############################################################################
[[ $- == *i* ]] && source "$HOME/.shell/plugins/fzf/shell/completion.bash" 2>/dev/null
source "$HOME/.shell/plugins/fzf/shell/key-bindings.bash" 2>/dev/null

###############################################################################
# NVM (Node Version Manager)
###############################################################################
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
