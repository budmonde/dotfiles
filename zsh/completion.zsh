# Initialize zsh completion system and load custom completions

autoload -Uz compinit && compinit

# Source all custom completion definitions
for f in ~/.zsh/completions/*.zsh(N); do
    source "$f"
done
