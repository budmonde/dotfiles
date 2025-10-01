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
alias et='vi ~/.tmux.conf'
alias ev='vi ~/.vim/vimrc'
alias ea='vi ~/.shell/aliases.sh; src'
alias eg='git config --global -e'

# Command shortcuts
alias g='git'
alias v='vim -p'
alias pjson='python -m json.tool'

alias cdr='cd "$(git rev-parse --show-toplevel)"'

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

# Set terminal title
set_title() {
    if [ -n "$WT_SESSION" ]; then
        printf '\033]0;%s\007' "$*"
    fi
}

if [ -n "$WT_SESSION" ]; then
    export WINDOWS_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    export WINDOWS_HOME="/mnt/c/Users/$WINDOWS_USER"
fi
