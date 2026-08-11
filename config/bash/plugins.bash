###############################################################################
# Fuzzy Finder (fzf)
###############################################################################
[[ $- == *i* ]] && source "${XDG_DATA_HOME:-$HOME/.local/share}/fzf/shell/completion.bash" 2>/dev/null
source "${XDG_DATA_HOME:-$HOME/.local/share}/fzf/shell/key-bindings.bash" 2>/dev/null

###############################################################################
# fnm (Fast Node Manager)
###############################################################################
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell bash)"
fi
