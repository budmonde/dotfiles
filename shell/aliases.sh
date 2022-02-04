# Enable color
alias grep='grep --color'
alias ls='ls --color=auto'

# Overwrite safety
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

# ls shorcuts
alias ll='ls -lX --color'
alias sl=ls

# Config file edits
alias src='. ~/.zshrc'
alias et='vi ~/.tmux.conf'
alias ev='vi ~/.vim/vimrc'
alias ez='vi ~/.zshrc; . ~/.zshrc'

# Command shortcuts
alias g='git'
alias v='vim -p'
alias pjson='python -m json.tool'

# Linux shortcuts
alias alert='notify-send "Job Finished!"'
alias chrome='google-chrome'
