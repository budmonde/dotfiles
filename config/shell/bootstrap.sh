# TeX Live
export TEXLIVE_DIR="$XDG_DATA_HOME/texlive"
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
path_prepend "$XDG_DATA_HOME/go/bin"
path_prepend "$XDG_DATA_HOME/fzf/bin"
path_prepend "$XDG_DATA_HOME/fnm"

# Personal paths
path_prepend "$HOME/.local/bin"
path_prepend "$HOME/bin"
