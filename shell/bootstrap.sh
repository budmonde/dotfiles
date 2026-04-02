# Lowest priority paths
path_append $HOME/.config/shell/plugins/fzf/bin

# Texlive (dynamic platform detection)
if [ -d "$TEXLIVE_DIR/bin" ]; then
    TEXLIVE_PLATFORM=$(ls "$TEXLIVE_DIR/bin" | head -1)
    path_append "$TEXLIVE_DIR/bin/$TEXLIVE_PLATFORM"
    manpath_append "$TEXLIVE_DIR/texmf-dist/doc/man"
    infopath_append "$TEXLIVE_DIR/texmf-dist/doc/info"
fi

# System paths
path_prepend /usr/local/cuda/bin
path_prepend /usr/local/bin

# Tool-managed paths
path_prepend ${XDG_DATA_HOME:-$HOME/.local/share}/go/bin
path_prepend $HOME/.opencode/bin
path_prepend ${XDG_DATA_HOME:-$HOME/.local/share}/fnm

# Personal paths
path_prepend $HOME/.local/bin
path_prepend $HOME/.dotfiles/bin
path_prepend $HOME/bin
