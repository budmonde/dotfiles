# Improve History
HISTSIZE=1048576
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
[ -d "${HISTFILE%/*}" ] || mkdir -p "${HISTFILE%/*}"
SAVEHIST=$HISTSIZE
shopt -s histappend

# On Bash 5.1, tab-completing a path under $HOME can leave \$HOME/ on the
# command line. The backslash makes the dollar sign literal when the command
# runs, so the completed path can fail to resolve. With direxpand, completion
# writes the expanded directory into the command line. Limit that change to
# 5.1 so other versions keep the variable as typed.
if (( BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] == 1 )); then
    shopt -s direxpand
fi
