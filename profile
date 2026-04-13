# ~/.profile: executed by login shells (sh, dash, etc.)
# For bash login shells, ~/.bash_profile is used instead.
# For zsh, ~/.zshenv is used instead.

# Early local env: HOME correction, secrets, cluster detection, XDG redirects
if [ -f "$HOME/.shellenv_local_early" ]; then
    . "$HOME/.shellenv_local_early"
fi

# Source shellenv for environment setup (PATH, etc.)
if [ -f "$HOME/.config/shell/shellenv.sh" ]; then
    . "$HOME/.config/shell/shellenv.sh"
fi

# Late local env: overrides that depend on the base dotfiles setup
if [ -f "$HOME/.shellenv_local" ]; then
    . "$HOME/.shellenv_local"
fi
