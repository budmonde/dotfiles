###############################################################################
# Fast Node Managed (fnm)
###############################################################################
# Base activation exposes Node and npm in every sourced environment;
# directory switching is interactive-only.
if command -v fnm &>/dev/null; then
    if [[ $- == *i* ]]; then
        eval "$(fnm env --use-on-cd --shell bash)"
    else
        eval "$(fnm env --shell bash)"
    fi
fi
