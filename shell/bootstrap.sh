# Lowest priority paths
path_append $HOME/.shell/plugins/fzf/bin

# Texlive (dynamic platform detection)
if [ -d "$HOME/.texlive/bin" ]; then
    TEXLIVE_PLATFORM=$(ls "$HOME/.texlive/bin" | head -1)
    path_append "$HOME/.texlive/bin/$TEXLIVE_PLATFORM"
    manpath_append "$HOME/.texlive/texmf-dist/doc/man"
    infopath_append "$HOME/.texlive/texmf-dist/doc/info"
fi

# System paths
path_prepend /usr/local/cuda/bin
path_prepend /usr/local/bin

# Tool-managed paths
path_prepend $HOME/.go/bin
path_prepend $HOME/.opencode/bin
path_prepend ${XDG_DATA_HOME:-$HOME/.local/share}/fnm

# Personal paths
path_prepend $HOME/.local/bin
path_prepend $HOME/.dotfiles/bin
path_prepend $HOME/bin
