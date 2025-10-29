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

# Set terminal title
set_title() {
    if [ -n "$WT_SESSION" ]; then
        printf '\033]0;%s\007' "$*"
    fi
}

if [ -n "$WSL_DISTRO_NAME" ]; then
    export WINDOWS_USER=$(powershell.exe -NoProfile -Command "[Environment]::UserName" | tr -d '\r\n')
    export WINDOWS_HOME="/mnt/c/Users/$WINDOWS_USER"
fi

notify() {
    local title="${1:-Notification}"
    local message="${2:-Task finished}"
	if [ -z "$WSL_DISTRO_NAME" ]; then
        echo "Error: No Windows notification environment found (not running in WSL)" >&2
        return 1
	fi

    powershell.exe -NoLogo -NonInteractive -WindowStyle Hidden -Command \
    "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null;
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > \$null;
    \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);
    \$textNodes = \$template.GetElementsByTagName('text');
    \$textNodes.Item(0).AppendChild(\$template.CreateTextNode('$title')) > \$null;
    \$textNodes.Item(1).AppendChild(\$template.CreateTextNode('$message')) > \$null;
    \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template);
    \$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('WSL');
    \$notifier.Show(\$toast);" \
    > /dev/null 2>&1 || {
        echo "Error: Failed to send Windows notification." >&2
        return 1
    }
}
