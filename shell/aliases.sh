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

# Command shortcuts
alias g='git'
alias v='vim -p'
alias pjson='python -m json.tool'

# Linux shortcuts
alias alert='notify-send "Job Finished!"'
alias chrome='google-chrome'
