#!/usr/bin/env bash
set -euo pipefail

machine_name=''
noninteractive=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        -y|--yes)
            noninteractive=true
            ;;
        --machine_name)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' 'Public bootstrap: --machine_name requires a value.' >&2
                exit 2
            fi
            shift
            machine_name="$1"
            noninteractive=true
            ;;
        --machine_name=*)
            machine_name="${1#*=}"
            noninteractive=true
            ;;
        *)
            printf 'Public bootstrap: unknown argument: %s\n' "$1" >&2
            exit 2
            ;;
    esac
    shift
done

machine_name_path="$HOME/.name"
if ! $noninteractive && ! { : </dev/tty; } 2>/dev/null; then
    printf '%s\n' 'Public bootstrap: no terminal is available; pass --yes to keep an existing name or --machine_name to supply one.' >&2
    exit 1
fi

identity_action=create
if [ -e "$machine_name_path" ] || [ -L "$machine_name_path" ]; then
    if [ ! -f "$machine_name_path" ]; then
        printf 'Public bootstrap: %s must be a file.\n' "$machine_name_path" >&2
        exit 1
    fi
    identity_action=reuse
    if ! $noninteractive; then
        printf 'Overwrite the machine name in %s? [y/N] ' "$machine_name_path" >/dev/tty
        IFS= read -r answer </dev/tty || answer=''
        case "$answer" in
            [yY]|[yY][eE][sS]) identity_action=replace ;;
        esac
    fi
fi

if [ "$identity_action" = reuse ]; then
    machine_name=$(cat -- "$machine_name_path")
elif ! $noninteractive; then
    printf 'Machine name: ' >/dev/tty
    IFS= read -r machine_name </dev/tty
elif [ -z "$machine_name" ]; then
    printf 'Public bootstrap: no machine name found at %s. Pass --machine_name to supply one.\n' "$machine_name_path" >&2
    exit 2
fi
if [[ ! "$machine_name" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]]; then
    printf '%s\n' 'Machine name must be 1-64 lowercase letters, digits, dots, underscores, or hyphens, and must start with a letter or digit.' >&2
    exit 1
fi

clone_path="$HOME/dotfiles"
if ! $noninteractive; then
    printf 'Clone path [%s]: ' "$clone_path" >/dev/tty
    IFS= read -r chosen_path </dev/tty
    clone_path="${chosen_path:-$clone_path}"
fi
if [ -e "$clone_path" ] || [ -L "$clone_path" ]; then
    printf '%s already exists. Choose an empty destination or remove it before bootstrapping.\n' "$clone_path" >&2
    exit 1
fi

export PATH="$HOME/.local/bin:$PATH"
if ! command -v git >/dev/null 2>&1; then
    printf '%s\n' 'Public bootstrap: git is required.' >&2
    exit 1
fi
if command -v python3 >/dev/null 2>&1; then
    python_command=python3
elif command -v python >/dev/null 2>&1; then
    python_command=python
else
    printf '%s\n' 'Public bootstrap: Python 3 is required.' >&2
    exit 1
fi
if ! "$python_command" -c 'import sys; raise SystemExit(sys.version_info < (3, 9))'; then
    printf '%s\n' 'Public bootstrap: Python 3.9 or newer is required.' >&2
    exit 1
fi

git -c core.fsmonitor= clone https://github.com/budmonde/dotfiles.git "$clone_path"
git_state="$(DOTBOT_INSTALL_REPO_ROOT="$clone_path" "$python_command" "$clone_path/install/resources/git.unix.py" apply)"
case "$git_state" in
    current|unsupported) ;;
    *)
        printf 'Public bootstrap: Git installation did not converge: %s\n' "$git_state" >&2
        exit 1
        ;;
esac
printf '00-base\n' >"$clone_path/.install-recipes"
printf 'Created base recipe plan at %s/.install-recipes\n' "$clone_path"

case "$identity_action" in
    create) (umask 077; set -C; printf '%s\n' "$machine_name" >"$machine_name_path") ;;
    replace) printf '%s\n' "$machine_name" >"$machine_name_path" ;;
esac
export DOTFILES_MACHINE_ID="$machine_name"
printf 'Using machine identity %s from %s\n' "$machine_name" "$machine_name_path"

printf '\nBootstrap complete. The public installer and tester are ready:\n'
printf '  cd %s\n' "$clone_path"
printf '  ./install.sh\n'
printf '  ./test.sh\n'
