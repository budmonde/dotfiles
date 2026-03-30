#!/usr/bin/env bash
# Linux backend for push-notify
# Uses notify-send, kdialog, or zenity (in order of preference)
#
# Supported features:
#   --sound <name>    Not supported (ignored)
#   --pane <id>       Not supported (ignored)
#   --silent          Not supported (ignored)

set -e

send_notification() {
    local title="$1"
    local message="$2"
    local sound="$3"   # ignored on Linux
    local pane="$4"    # ignored on Linux
    local silent="$5"  # ignored on Linux

    if command -v notify-send &> /dev/null; then
        notify-send "$title" "$message"
    elif command -v kdialog &> /dev/null; then
        kdialog --passivepopup "$message" --title "$title" 5
    elif command -v zenity &> /dev/null; then
        zenity --notification --text="$title: $message"
    else
        echo "Error: No notification system available" >&2
        echo "$title: $message" >&2
        return 1
    fi
}

send_notification "$@"
