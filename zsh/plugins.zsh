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
# NVM (Node Version Manager)
###############################################################################
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

###############################################################################
# Miniconda
###############################################################################
[ -x "$HOME/.miniconda3/bin/conda" ] && eval "$($HOME/.miniconda3/bin/conda shell.zsh hook)"

###############################################################################
# Color Theme
###############################################################################
if [[ "$(tput colors)" == "256" ]]; then
    eval $(dircolors =(cat ~/.shell/plugins/dircolors-solarized/dircolors.256dark ~/.shell/dircolors.extra))
fi
