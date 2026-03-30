#!/usr/bin/env bash
# WSL backend for push-notify
# Uses Windows Toast notifications via PowerShell
#
# Supported features:
#   --sound <name>    Windows sound from C:\Windows\Media\
#   --pane <id>       Click-to-focus via wsltoast:// protocol
#   --silent          Suppress sound

set -e

send_notification() {
    local title="$1"
    local message="$2"
    local sound="$3"
    local pane="$4"
    local silent="$5"

    local ps_title="${title//\'/\'\'}"
    local ps_message="${message//\'/\'\'}"

    local audio_xml=""
    if [[ "$silent" == true ]] || [[ -n "$sound" ]]; then
        audio_xml="<audio silent='true'/>"
    fi

    local launch_xml=""
    if [[ -n "$pane" ]]; then
        local encoded_pane="${pane//%/%25}"
        launch_xml="launch='wsltoast://focus?pane=${encoded_pane}'"
    fi

    if [[ -n "$sound" ]] && [[ "$silent" != true ]]; then
        powershell.exe -NoLogo -NonInteractive -WindowStyle Hidden -Command \
        "(New-Object Media.SoundPlayer 'C:\Windows\Media\\$sound.wav').PlaySync()" \
        > /dev/null 2>&1 &
    fi

    powershell.exe -NoLogo -NonInteractive -WindowStyle Hidden -Command \
    "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null;
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > \$null;
    \$xml = '<toast $launch_xml><visual><binding template=\"ToastText02\"><text id=\"1\">$ps_title</text><text id=\"2\">$ps_message</text></binding></visual>$audio_xml</toast>';
    \$doc = New-Object Windows.Data.Xml.Dom.XmlDocument;
    \$doc.LoadXml(\$xml);
    \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$doc);
    \$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('WSL');
    \$notifier.Show(\$toast);" \
    > /dev/null 2>&1
}

send_notification "$@"
