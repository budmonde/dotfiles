# Improve History
HISTSIZE=1048576
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
SAVEHIST=$HISTSIZE
shopt -s histappend
