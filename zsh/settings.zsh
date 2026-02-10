# Improve History
HISTSIZE=1048576
HISTFILE="$HOME/.zsh_history"
SAVEHIST=$HISTSIZE
setopt appendhistory
setopt incappendhistory
setopt extendedhistory

# Disable beeping
unsetopt beep

# Extended glob
setopt extended_glob

# Time to wait for additional characters in a sequence
export KEYTIMEOUT=1 # 10ms

# Use vim editing mode
bindkey -v

# Enable completions
source ~/.zsh/completion.zsh

# Enable edit-command-line
autoload -U edit-command-line && zle -N edit-command-line
bindkey -a '^V' edit-command-line

# Enable *-line-or-beginning-search
autoload -U up-line-or-beginning-search && zle -N up-line-or-beginning-search
autoload -U down-line-or-beginning-search && zle -N down-line-or-beginning-search
bindkey "^[OA" up-line-or-beginning-search
bindkey "^[OB" down-line-or-beginning-search
bindkey -M vicmd "k" up-line-or-beginning-search
bindkey -M vicmd "j" down-line-or-beginning-search

# Enable emacs quick movement
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^F' forward-word
bindkey '^B' backward-word

# Disable builtin
disable r
