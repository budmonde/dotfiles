path_remove() {
    PATH=$(echo -n "$PATH" | awk -v RS=: -v ORS=: "\$0 != \"$1\"" | sed 's/:$//')
}

path_append() {
    path_remove "$1"
    PATH="${PATH:+"$PATH:"}$1"
}

path_prepend() {
    path_remove "$1"
    PATH="$1${PATH:+":$PATH"}"
}
manpath_remove() {
    MANPATH=$(echo -n "$MANPATH" | awk -v RS=: -v ORS=: "\$0 != \"$1\"" | sed 's/:$//')
}

manpath_append() {
    manpath_remove "$1"
    MANPATH="${MANPATH:+"$MANPATH:"}$1"
}

manpath_prepend() {
    manpath_remove "$1"
    MANPATH="$1${MANPATH:+":$MANPATH"}"
}
infopath_remove() {
    INFOPATH=$(echo -n "$INFOPATH" | awk -v RS=: -v ORS=: "\$0 != \"$1\"" | sed 's/:$//')
}

infopath_append() {
    infopath_remove "$1"
    INFOPATH="${INFOPATH:+"$INFOPATH:"}$1"
}

infopath_prepend() {
    infopath_remove "$1"
    INFOPATH="$1${INFOPATH:+":$INFOPATH"}"
}
