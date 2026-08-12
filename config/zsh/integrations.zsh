# Base activation exposes Node and npm in every shell;
# directory switching is interactive-only.
if command -v fnm &>/dev/null; then
    if [[ -o interactive ]]; then
        eval "$(fnm env --use-on-cd --shell zsh)"
    else
        eval "$(fnm env --shell zsh)"
    fi
fi
