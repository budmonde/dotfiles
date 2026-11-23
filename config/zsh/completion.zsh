# Initialize zsh completion system and load custom completions

autoload -Uz compinit
() {
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
    if mkdir -p -- "$cache_dir"; then
        compinit -d "$cache_dir/zcompdump"
    else
        compinit -D
    fi
}

# Source all custom completion definitions
for f in ~/.config/zsh/completions/*.zsh(N); do
    [[ -r "$f" ]] && source "$f"
done

# Source completions from external repos (e.g. dotfiles-nvidia)
for f in ~/.config/zsh/completions.d/*.zsh(N); do
    [[ -r "$f" ]] && source "$f"
done
