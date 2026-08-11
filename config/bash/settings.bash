# Improve History
HISTSIZE=1048576
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
[ -d "${HISTFILE%/*}" ] || mkdir -p "${HISTFILE%/*}"
SAVEHIST=$HISTSIZE
shopt -s histappend
