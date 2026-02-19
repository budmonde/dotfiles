# Enable color
alias grep='grep --color'
alias ls='ls --color=auto'

# Typo fixes
alias sl=ls
alias dc=cd

# Overwrite safety
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

# ls shorcuts
alias ll='ls -lX --color'

# Config file edits
src() {
    if [[ $SHELL = '/bin/zsh' ]]; then
        . ~/.zshrc
    elif [[ $SHELL = '/bin/bash' ]]; then
        . ~/.bashrc
    fi
}
alias et='$EDITOR ~/.tmux.conf'
alias ev='$EDITOR ~/.vim/vimrc'
alias ea='$EDITOR ~/.shell/aliases.sh; src'
alias eg='git config --global -e'

# Command shortcuts
alias g='git'
alias v='$EDITOR -p'
alias vs='NVIM_SESSION=1 nvim'
alias pjson='python -m json.tool'
alias llmview='nvim -R - -c "setf llmlog"'

alias cdr='cd "$(git rev-parse --show-toplevel)"'
cdp() {
    local target="$1"
    if [ -z "$target" ]; then
        echo "Usage: cdp <path>"
        return 1
    fi

    if [ -d "$target" ]; then
        cd "$target" || return
    elif [ -f "$target" ]; then
        cd "$(dirname "$target")" || return
    else
        echo "Error: '$target' is not a valid file or directory"
        return 1
    fi
}


# List all Make Targets
list_make_targets() {
    local makefile="${1:-Makefile}"
    if [[ ! -f "$makefile" ]]; then
        echo "Makefile '$makefile' not found!"
        return 1
    fi

    # Extract all target names
    local targets
    targets=$(make -pRrq -f "$makefile" : 2>/dev/null \
        | awk -F: '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {print $1}' \
        | sort -u)

    # Extract phony targets
    local phony
    phony=$(awk '/\.PHONY:/ {for (i=2;i<=NF;i++) print $i}' "$makefile")

    # Print targets, highlighting phony ones
    for t in $targets; do
        if echo "$phony" | grep -qx "$t"; then
            echo -e "\e[33m$t\e[0m"   # yellow for PHONY
        else
            echo "$t"
        fi
    done
}
