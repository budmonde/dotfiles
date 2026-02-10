# Completion for llmlog command
# Completes session log files based on current directory

_llmlog() {
    local logs_root="$HOME/.local/share/opencode/logs"
    local current_dir="$(pwd)"
    
    # Convert current directory to log directory name (same logic as session-logger plugin)
    local sanitized_path="${current_dir#/}"
    sanitized_path="${sanitized_path//\//-}"
    
    local log_dir="$logs_root/$sanitized_path"
    
    # Check if log directory exists
    if [[ ! -d "$log_dir" ]]; then
        return
    fi
    
    # Get list of log files and extract just the title part
    local -a sessions
    
    for f in "$log_dir"/*.jsonl(N); do
        [[ -f "$f" ]] || continue
        local basename="${f:t}"  # filename only
        # Extract title: remove session ID prefix (ses_xxx-) and .jsonl suffix
        local title="${basename#*-}"
        title="${title%.jsonl}"
        sessions+=("$title")
    done
    
    if (( ${#sessions} == 0 )); then
        return
    fi
    
    _describe -t sessions 'session logs' sessions
}

compdef _llmlog llmlog
