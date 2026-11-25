if [ -d "$HOME/.config/shell" ] && DOTFILES_SHELL_DIR=$(CDPATH= cd -P -- "$HOME/.config/shell" && pwd -P); then
    export DOTFILES_SHELL_DIR
else
    unset DOTFILES_SHELL_DIR
fi

unset DOTFILES_WORKSPACE_ROOT
if [ -n "${DOTFILES_SHELL_DIR:-}" ] && [ -L "$HOME/.config/shell" ]; then
    DOTFILES_WORKSPACE_ROOT=${DOTFILES_SHELL_DIR%/*}
    DOTFILES_WORKSPACE_ROOT=${DOTFILES_WORKSPACE_ROOT%/*}
    export DOTFILES_WORKSPACE_ROOT="${DOTFILES_WORKSPACE_ROOT:-/}"
fi

_dotfiles_machine_id_path="$HOME/.name"
if [ -f "$_dotfiles_machine_id_path" ]; then
    if ! _dotfiles_machine_id=$(cat "$_dotfiles_machine_id_path" 2>/dev/null); then
        unset DOTFILES_MACHINE_ID
        printf 'Warning: unable to read machine name from %s.\n' "$_dotfiles_machine_id_path" >&2
    elif [[ "$_dotfiles_machine_id" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]]; then
        export DOTFILES_MACHINE_ID="$_dotfiles_machine_id"
    else
        unset DOTFILES_MACHINE_ID
        printf 'Warning: ignoring invalid machine name in %s.\n' "$_dotfiles_machine_id_path" >&2
    fi
else
    unset DOTFILES_MACHINE_ID
fi
unset _dotfiles_machine_id _dotfiles_machine_id_path
