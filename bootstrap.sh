#!/usr/bin/env bash
set -euo pipefail

machine_name=''
noninteractive=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --machine_name)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' 'bootstrap.sh: --machine_name requires a value.' >&2
                exit 2
            fi
            machine_name="$2"
            noninteractive=true
            shift 2
            ;;
        --machine_name=*)
            machine_name="${1#*=}"
            noninteractive=true
            shift
            ;;
        *)
            printf 'bootstrap.sh: unknown argument: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

machine_name_path="$HOME/.name"
if [ -e "$machine_name_path" ] || [ -L "$machine_name_path" ]; then
    printf '%s already exists. Remove it explicitly before bootstrapping a different machine identity.\n' "$machine_name_path" >&2
    exit 1
fi

if ! $noninteractive; then
    if [ ! -r /dev/tty ]; then
        printf '%s\n' 'bootstrap.sh: no terminal is available; pass --machine_name for non-interactive use.' >&2
        exit 1
    fi
    printf 'Machine name: ' >/dev/tty
    IFS= read -r machine_name </dev/tty
fi
if [[ ! "$machine_name" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]]; then
    printf '%s\n' 'Machine name must be 1-64 lowercase letters, digits, dots, underscores, or hyphens, and must start with a letter or digit.' >&2
    exit 1
fi

default_path="$HOME/dotfiles/common"
if $noninteractive; then
    clone_path="$default_path"
else
    printf 'Clone path [%s]: ' "$default_path" >/dev/tty
    IFS= read -r clone_path </dev/tty
    clone_path="${clone_path:-$default_path}"
fi
if [ -e "$clone_path" ] || [ -L "$clone_path" ]; then
    printf '%s already exists. Choose an empty destination or remove it before bootstrapping.\n' "$clone_path" >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    printf '%s\n' 'bootstrap.sh: git is required.' >&2
    exit 1
fi
if command -v python3 >/dev/null 2>&1; then
    python_command=python3
elif command -v python >/dev/null 2>&1; then
    python_command=python
else
    printf '%s\n' 'bootstrap.sh: Python 3 is required.' >&2
    exit 1
fi
if ! "$python_command" -c 'import sys; raise SystemExit(sys.version_info < (3, 9))'; then
    printf '%s\n' 'bootstrap.sh: Python 3.9 or newer is required.' >&2
    exit 1
fi

git clone https://github.com/budmonde/dotfiles.git "$clone_path"
printf '00-base\n' >"$clone_path/.install-recipes"
printf 'Created base recipe plan at %s/.install-recipes\n' "$clone_path"

if ! (umask 077; set -C; printf '%s\n' "$machine_name" >"$machine_name_path") 2>/dev/null; then
    printf 'bootstrap.sh: could not create %s because it already exists.\n' "$machine_name_path" >&2
    exit 1
fi
export DOTFILES_MACHINE_ID="$machine_name"
printf 'Created machine identity at %s\n' "$machine_name_path"

printf '\nBootstrap complete. The common installer and tester are ready:\n'
printf '  cd %s\n' "$clone_path"
printf '  ./install.sh\n'
printf '  ./test.sh\n'
