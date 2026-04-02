# ~/.profile: executed by login shells (sh, dash, etc.)
# For bash login shells, ~/.bash_profile is used instead.
# For zsh, ~/.zshenv is used instead.

# Source shellenv for environment setup (PATH, etc.)
if [ -f "$HOME/.config/shell/shellenv.sh" ]; then
    . "$HOME/.config/shell/shellenv.sh"
fi

# Source local overrides
if [ -f "$HOME/.shellenv_local" ]; then
    . "$HOME/.shellenv_local"
fi
