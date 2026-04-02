###############################################################################
# Fuzzy Finder (fzf)
###############################################################################
[[ $- == *i* ]] && source "$HOME/.shell/plugins/fzf/shell/completion.bash" 2>/dev/null
source "$HOME/.shell/plugins/fzf/shell/key-bindings.bash" 2>/dev/null

###############################################################################
# fnm (Fast Node Manager)
###############################################################################
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell bash)"
fi

###############################################################################
# Miniconda
###############################################################################
[ -x "$CONDA_DIR/bin/conda" ] && eval "$($CONDA_DIR/bin/conda shell.bash hook)"
