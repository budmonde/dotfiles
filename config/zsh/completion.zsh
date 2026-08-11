# Initialize zsh completion system and load custom completions

autoload -Uz compinit && compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

# Source all custom completion definitions
for f in ~/.config/zsh/completions/*.zsh(N); do
    source "$f"
done

# Source completions from external repos (e.g. dotfiles-nvidia)
for f in ~/.config/zsh/completions.d/*.zsh(N); do
    source "$f"
done
