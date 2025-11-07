ATTRIBUTE_BOLD='\[\e[1m\]'
ATTRIBUTE_RESET='\[\e[0m\]'
COLOR_DEFAULT='\[\e[39m\]'

RAW_COLOR_DEFAULT=$'\e[39m'
RAW_ATTRIBUTE_BOLD=$'\e[1m'
RAW_ATTRIBUTE_RESET=$'\e[0m'

if [[ "$(tput colors 2>/dev/null)" -ge 256 ]]; then
    COLOR_RED='\[\e[38;5;196m\]'
    COLOR_GREEN='\[\e[38;5;10m\]'
    COLOR_YELLOW='\[\e[38;5;11m\]'
    COLOR_BLUE='\[\e[38;5;33m\]'
    COLOR_MAGENTA='\[\e[38;5;127m\]'
    COLOR_CYAN='\[\e[38;5;81m\]'

    COLOR_TEAL='\[\e[38;5;31m\]'
    COLOR_ORANGE='\[\e[38;5;166m\]'
    COLOR_OLIVE='\[\e[38;5;148m\]'
    COLOR_NEON='\[\e[38;5;120m\]'
    COLOR_VIOLET='\[\e[38;5;98m\]'
    COLOR_GRAY='\[\e[38;5;246m\]'

    RAW_COLOR_RED=$'\e[38;5;196m'
    RAW_COLOR_GREEN=$'\e[38;5;10m'
    RAW_COLOR_YELLOW=$'\e[38;5;11m'
    RAW_COLOR_BLUE=$'\e[38;5;33m'
    RAW_COLOR_MAGENTA=$'\e[38;5;127m'
    RAW_COLOR_CYAN=$'\e[38;5;81m'

    RAW_COLOR_TEAL=$'\e[38;5;33m'
    RAW_COLOR_ORANGE=$'\e[38;5;166m'
    RAW_COLOR_OLIVE=$'\e[38;5;148m'
    RAW_COLOR_NEON=$'\e[38;5;120m'
    RAW_COLOR_VIOLET=$'\e[38;5;98m'
    RAW_COLOR_GRAY=$'\e[38;5;246m'
else
    COLOR_RED='\[\e[31m\]'
    COLOR_GREEN='\[\e[32m\]'
    COLOR_YELLOW='\[\e[33m\]'
    COLOR_BLUE='\[\e[34m\]'
    COLOR_MAGENTA='\[\e[35m\]'
    COLOR_CYAN='\[\e[36m\]'

    COLOR_TEAL="${COLOR_BLUE}"
    COLOR_ORANGE="${COLOR_YELLOW}"
    COLOR_OLIVE="${COLOR_GREEN}"
    COLOR_NEON="${COLOR_GREEN}"
    COLOR_VIOLET="${COLOR_MAGENTA}"
    COLOR_GRAY="${COLOR_DEFAULT}"

    RAW_COLOR_RED=$'\e[31m'
    RAW_COLOR_GREEN=$'\e[32m'
    RAW_COLOR_YELLOW=$'\e[33m'
    RAW_COLOR_BLUE=$'\e[34m'
    RAW_COLOR_MAGENTA=$'\e[35m'
    RAW_COLOR_CYAN=$'\e[36m'

    RAW_COLOR_TEAL=$'\e[33m'
    RAW_COLOR_ORANGE=$'\e[33m'
    RAW_COLOR_OLIVE=$'\e[32m'
    RAW_COLOR_NEON=$'\e[32m'
    RAW_COLOR_VIOLET=$'\e[35m'
    RAW_COLOR_GRAY=$'\e[37m'
fi

# Helper: print given text in all named colors
print_named_colors() {
    local text="$*"
    local name var color
    for name in RED GREEN YELLOW BLUE MAGENTA CYAN TEAL ORANGE OLIVE NEON VIOLET GRAY; do
        var="RAW_COLOR_${name}"
        color="${!var}"
        printf "%-7s %s%s%s \t %s%s%s\n" "$name" "$color" "$text" "$RAW_ATTRIBUTE_BOLD" "$text" "$RAW_ATTRIBUTE_RESET" "$RAW_COLOR_DEFAULT"
    done
}

machine_name() {
    if [[ -f $HOME/.name ]]; then
        cat $HOME/.name
    else
        hostname
    fi
}

# Previous command error status
PR_ERROR_CHAR="!"
PR_ARROW_CHAR="${ATTRIBUTE_BOLD}›${ATTRIBUTE_RESET}"

PROMPT_DIRTRIM=3
_pr_var_list=()
_vars_multiline=true

vshow() {
    local v x found
    for v in "$@"; do
        if [[ "$v" =~ ^[A-Z_]+$ ]]; then
            found=0
            for x in "${_pr_var_list[@]}"; do
                if [[ "$x" == "$v" ]]; then found=1; break; fi
            done
            if [[ $found -eq 0 ]]; then _pr_var_list+=("$v"); fi
        fi
    done
}

vhide() {
    local v x tmp=()
    for v in "$@"; do
        for x in "${_pr_var_list[@]}"; do
            [[ "$x" == "$v" ]] || tmp+=("$x")
        done
        _pr_var_list=("${tmp[@]}")
        tmp=()
    done
}

PR_HEADER() {
    local last_status=$?
    # PR_VARS
    local v spc nl
    if $_vars_multiline; then spc=""; nl=$'\n'; else spc=" "; nl=""; fi
    for v in "${_pr_var_list[@]}"; do
        if [[ ${!v+x} ]]; then
            if export -p | grep -Eq "^declare -x ${v}(=|$)"; then
                printf "%s%s%s=%s%s" "$spc" "$RAW_COLOR_YELLOW" "$v" "${!v}" "$RAW_COLOR_DEFAULT"
            else
                printf "%s%s%s=%s%s" "$spc" "$RAW_COLOR_RED" "$v" "${!v}" "$RAW_COLOR_DEFAULT"
            fi
            printf "%s" "$nl"
        fi
    done
    # PR_ERROR
    if [ $last_status -ne 0 ]; then
        printf "%s%s%s" "$RAW_COLOR_RED" "$PR_ERROR_CHAR" "$RAW_COLOR_DEFAULT"
    else
        printf "%s#%s" "$RAW_COLOR_BLUE" "$RAW_COLOR_DEFAULT"
    fi
}

# Simple Git branch segment
git_branch_prompt() {
    local ref
    ref="$(git symbolic-ref -q --short HEAD 2>/dev/null)" || ref="$(git rev-parse --short HEAD 2>/dev/null)" || return 0
    [[ -z "$ref" ]] && return 0
    printf " %sgit:%s(%s%s%s)%s" \
        "$RAW_COLOR_CYAN" "$RAW_COLOR_DEFAULT" \
        "$RAW_COLOR_RED" "$ref" "$RAW_COLOR_DEFAULT" \
        "$RAW_COLOR_DEFAULT"
}

PS1="\n"\
"\$(PR_HEADER) "\
"${COLOR_TEAL}\u${COLOR_DEFAULT} "\
"${COLOR_GRAY}at${COLOR_DEFAULT} "\
"${COLOR_VIOLET}$(machine_name)${COLOR_DEFAULT} "\
"${COLOR_GRAY}in${COLOR_DEFAULT} "\
"${COLOR_OLIVE}${ATTRIBUTE_BOLD}\\w${ATTRIBUTE_RESET}${COLOR_DEFAULT}"\
"\$(git_branch_prompt)"\
"\n"\
"${COLOR_BLUE}${PR_ARROW_CHAR}${COLOR_DEFAULT} "

PS2="${COLOR_BLUE}>${COLOR_DEFAULT} "

demoprompt() {
    PROMPT_DIRTRIM=1
    PS1="${COLOR_GRAY}\w ${COLOR_BLUE}\$ "
    trap '[[ -t 1 ]] && tput sgr0' DEBUG
}
