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

here() {
    local loc
    if [ "$#" -eq 1 ]; then
        loc=$(realpath "$1")
    else
        loc=$(realpath ".")
    fi
    ln -sfn "${loc}" "$HOME/.shell.here"
    echo "here -> $(readlink $HOME/.shell.here)"
}

there="$HOME/.shell.here"

there() {
    cd "$(readlink "${there}")"
}

latest_dir() {
  local dir="${1:-.}"
  [ -d "$dir" ] || { echo "No such directory: $dir" >&2; return 1; }

  find -- "$dir" -maxdepth 1 -type d -printf '%T@ %p\0' \
    | sort -z -nr \
    | awk -v RS='\0' 'NR==1 { sub(/^[^ ]* /,""); print; exit }'
}

latest_file() {
  local dir="${1:-.}"
  [ -d "$dir" ] || { echo "No such directory: $dir" >&2; return 1; }

  find -- "$dir" -maxdepth 1 -type f -printf '%T@ %p\0' \
    | sort -z -nr \
    | awk -v RS='\0' 'NR==1 { sub(/^[^ ]* /,""); print; exit }'
}
