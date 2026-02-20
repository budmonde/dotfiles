setopt prompt_subst

autoload -U colors && colors

if [[ "$(tput colors 2>/dev/null)" -ge 256 ]]; then
    source ~/.zsh/plugins/spectrum.zsh
    fg[red]=$FG[196]
    fg[green]=$FG[010]
    fg[yellow]=$FG[011]
    fg[blue]=$FG[033]
    fg[magenta]=$FG[127]
    fg[cyan]=$FG[081]

    fg[teal]=$FG[031]
    fg[orange]=$FG[166]
    fg[violet]=$FG[98]
    fg[neon]=$FG[120]
    fg[pink]=$FG[219]

    fg[olive]=$FG[148]
else
    fg[teal]=$fg[blue]
    fg[orange]=$fg[yellow]
    fg[violet]=$fg[magenta]
    fg[neon]=$fg[green]
    fg[pink]=$fg[magenta]

    fg[olive]=$fg[green]
fi

# Previous command error status
PR_ERROR_CHAR="%B!%b"

function PR_ERROR() {
    echo "%(?. .%(!.%{$fg[violet]%}.%{$fg[red]%})${PR_ERROR_CHAR}%{$reset_color%})"
}

# Prompt Arrow
PR_ARROW_CHAR="%B›%b"
_arrow_color="$fg[green]"
_root_arrow_color="$fg[red]"

# Change Arrow color depending on insert or command mode
function zle-line-init zle-keymap-select () {
    case $KEYMAP in
        (vicmd) _arrow_color="$fg[green]" ; _root_arrow_color="$fg[red]" ;;
        (viins|main) _arrow_color="$fg[blue]" ; _root_arrow_color="$fg[magenta]" ;;
    esac
    zle reset-prompt
}
zle -N zle-line-init
zle -N zle-keymap-select

function PR_ARROW() {
    echo "%(!.%{$_root_arrow_color%}.%{${_arrow_color}%})${PR_ARROW_CHAR}%{$reset_color%}"
}

# Show/Hide Environment Variables in prompt
_pr_var_list=()
_vars_multiline=false

function vshow() {
    local v
    for v in "$@"; do
        if [[ "${v}" =~ '[A-Z_]+' ]]; then
            if [[ ${_pr_var_list[(i)${v}]} -gt ${#_pr_var_list} ]]; then
                _pr_var_list+=("${v}")
            fi
        fi
    done
}

function vhide() {
    local v
    for v in "$@"; do
        _pr_var_list[${_pr_var_list[(i)${v}]}]=()
    done
}

function PR_VARS() {
    local i v spc nl
    if $_vars_multiline; then
        spc=""
        nl="\n"
    else
        spc=" "
        nl=""
    fi
    for ((i=1; i <= ${#_pr_var_list}; ++i)) do
        local v=${_pr_var_list[i]}
        if [[ -v "${v}" ]]; then
            # if variable is set
            if export | grep -Eq "^${v}="; then
                # if exported, show regularly
                printf '%s' "$spc%{$fg[yellow]%}${v}=${(P)${v}}%{$reset_color%}$nl"
            else
                printf '%s' "$spc%{$fg[red]%}${v}=${(P)${v}}%{$reset_color%}$nl"
            fi
        fi
    done
}


# Directory
function PR_DIR() {
    echo "%{$fg[olive]%}%B%c%b%{$reset_color%}"
}



function PYENV() {
    if [[ -n $CONDA_DEFAULT_ENV ]]; then
        echo "%{$fg[yellow]%}[conda:%{$fg[orange]%}${CONDA_DEFAULT_ENV}%{$fg[yellow]%}]%{$reset_color%} "
    fi
}


# LHS Prompt Display
function PCMD() {
    if $_vars_multiline; then
        echo "$(PR_VARS)$(PR_ERROR) $(PR_DIR) $(PYENV)$(PR_ARROW) " # space at the end
    else
        echo "$(PR_ERROR)$(PR_VARS) $(PR_DIR) $(PYENV)$(PR_ARROW) " # space at the end
    fi
}

PROMPT='$(PCMD)' # single quotes to prevent immediate execution
RPROMPT='' # set asynchronously and dynamically

DIFF_SYMBOL="✗"
GIT_PROMPT_SYMBOL="%{$fg[olive]%}%Bgit:%b%{$reset_color%}"
GIT_PROMPT_PREFIX="%{$fg[olive]%}%B(%b%{$reset_color%}"
GIT_PROMPT_SUFFIX="%{$fg[olive]%}%B)%b%{$reset_color%}"
GIT_PROMPT_AHEAD="%{$fg[teal]%}%B+NUM%b%{$reset_color%}"
GIT_PROMPT_BEHIND="%{$fg[orange]%}%B-NUM%b%{$reset_color%}"
GIT_PROMPT_MERGING="%{$fg[cyan]%}%Bx%b%{$reset_color%}"
GIT_PROMPT_UNTRACKED="%{$fg[red]%}%B$DIFF_SYMBOL%b%{$reset_color%}"
GIT_PROMPT_MODIFIED="%{$fg[yellow]%}%B$DIFF_SYMBOL%b%{$reset_color%}"
GIT_PROMPT_STAGED="%{$fg[olive]%}%B$DIFF_SYMBOL%b%{$reset_color%}"
GIT_PROMPT_DETACHED="%{$fg[neon]%}%B!%b%{$reset_color%}"

function parse_git_branch() {
    (git symbolic-ref -q HEAD || git name-rev --name-only --no-undefined --always HEAD) 2> /dev/null
}

function parse_git_detached() {
    if ! git symbolic-ref HEAD >/dev/null 2>&1; then
        echo "${GIT_PROMPT_DETACHED}"
    fi
}

function parse_git_state() {
    local GIT_STATE="" GIT_DIFF=""

    local NUM_AHEAD="$(git log --oneline @{u}.. 2> /dev/null | wc -l | tr -d ' ')"
    if [ "$NUM_AHEAD" -gt 0 ]; then
        GIT_STATE=$GIT_STATE${GIT_PROMPT_AHEAD//NUM/$NUM_AHEAD}
    fi

    local NUM_BEHIND="$(git log --oneline ..@{u} 2> /dev/null | wc -l | tr -d ' ')"
    if [ "$NUM_BEHIND" -gt 0 ]; then
        if [[ -n $GIT_STATE ]]; then
            GIT_STATE="$GIT_STATE "
        fi
        GIT_STATE=$GIT_STATE${GIT_PROMPT_BEHIND//NUM/$NUM_BEHIND}
    fi

    local GIT_DIR="$(git rev-parse --git-dir 2> /dev/null)"
    if [ -n $GIT_DIR ] && test -r $GIT_DIR/MERGE_HEAD; then
        if [[ -n $GIT_STATE ]]; then
            GIT_STATE="$GIT_STATE "
        fi
        GIT_STATE=$GIT_STATE$GIT_PROMPT_MERGING
    fi

    if [[ -n $(git ls-files --other --exclude-standard :/ 2> /dev/null) ]]; then
        GIT_DIFF=$GIT_PROMPT_UNTRACKED
    fi

    if ! git diff --quiet 2> /dev/null; then
        GIT_DIFF=$GIT_DIFF$GIT_PROMPT_MODIFIED
    fi

    if ! git diff --cached --quiet 2> /dev/null; then
        GIT_DIFF=$GIT_DIFF$GIT_PROMPT_STAGED
    fi

    if [[ -n $GIT_STATE && -n $GIT_DIFF ]]; then
        GIT_STATE="$GIT_STATE "
    fi
    GIT_STATE="$GIT_STATE$GIT_DIFF"

    if [[ -n $GIT_STATE ]]; then
        echo "$GIT_STATE"
    fi
}

function git_prompt_string() {
    local git_where="$(parse_git_branch)"
    local git_detached="$(parse_git_detached)"
    [ -n "$git_where" ] && echo " $GIT_PROMPT_SYMBOL$GIT_PROMPT_PREFIX%{$fg[red]%}%B${git_where#(refs/heads/|tags/)}%b$git_detached%{$reset_color%}$GIT_PROMPT_SUFFIX$(parse_git_state)"
}


# RHS Prompt Display
function RCMD() {
    echo "$(git_prompt_string)"
}

ASYNC_PROC=0
function precmd() {
    function async() {
        # save to temp file
        printf "%s" "$(RCMD)" > "/tmp/zsh_prompt_$$"
        # signal parent
        kill -s USR1 $$
    }
    # do not clear RPROMPT, let it persist

    # kill child if necessary
    if [[ "${ASYNC_PROC}" != 0 ]]; then
        kill -s HUP $ASYNC_PROC >/dev/null 2>&1 || :
    fi

    # start background computation
    async &!
    ASYNC_PROC=$!
}

function TRAPUSR1() {
    # read from temp file
    RPROMPT="$(cat /tmp/zsh_prompt_$$)"

    # reset proc number
    ASYNC_PROC=0

    # redisplay
    zle && zle reset-prompt
}
