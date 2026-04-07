# push-notify — Windows notification script
# Usage: push-notify [OPTIONS] <title> <message>
#
# Options:
#   --sound <name>    Play specific sound (from C:\Windows\Media\)
#   --silent          No sound at all

param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$sound = ''
$silent = $false
$positional = @()

$i = 0
while ($i -lt $Arguments.Count) {
    switch ($Arguments[$i]) {
        '--sound'  { $sound = $Arguments[++$i] }
        '--pane'   { ++$i }
        '--silent' { $silent = $true }
        default    { $positional += $Arguments[$i] }
    }
    $i++
}

$title   = if ($positional.Count -ge 1) { $positional[0] } else { 'Notification' }
$message = if ($positional.Count -ge 2) { $positional[1] } else { 'Task finished' }

$escapedTitle = [System.Security.SecurityElement]::Escape($title)
$escapedMessage = [System.Security.SecurityElement]::Escape($message)

$audioXml = ''
if ($silent -or $sound) {
    $audioXml = "<audio silent='true'/>"
}

if ($sound -and -not $silent) {
    $soundPath = "C:\Windows\Media\$sound.wav"
    if (Test-Path $soundPath) {
        $player = New-Object Media.SoundPlayer $soundPath
        $player.Load()
    }
}

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

$xml = "<toast><visual><binding template=`"ToastText02`"><text id=`"1`">$escapedTitle</text><text id=`"2`">$escapedMessage</text></binding></visual>$audioXml</toast>"
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml($xml)
$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('push-notify')
$notifier.Show($toast)

if ($player) { $player.PlaySync() }
