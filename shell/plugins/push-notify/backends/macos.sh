#!/usr/bin/env bash
# macOS backend for push-notify
# Uses osascript for native notifications
#
# Supported features:
#   --sound <name>    macOS sound name
#   --pane <id>       Not supported (ignored)
#   --silent          Suppress sound

set -e

send_notification() {
    local title="$1"
    local message="$2"
    local sound="$3"
    local pane="$4"  # ignored on macOS
    local silent="$5"

    local script="display notification \"$message\" with title \"$title\""

    if [[ -n "$sound" ]] && [[ "$silent" != true ]]; then
        script="$script sound name \"$sound\""
    fi

    osascript -e "$script"
}

send_notification "$@"
