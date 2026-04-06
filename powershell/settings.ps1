###############################################################################
### PSReadLine
###############################################################################
Set-PSReadLineOption -EditMode Vi

Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteCharOrExit

# Emacs-style movement in vi insert mode (mirrors zsh bindkey ^A/^E/^F/^B)
Set-PSReadLineKeyHandler -ViMode Insert -Chord 'Ctrl+a' -Function BeginningOfLine
Set-PSReadLineKeyHandler -ViMode Insert -Chord 'Ctrl+e' -Function EndOfLine
Set-PSReadLineKeyHandler -ViMode Insert -Chord 'Ctrl+f' -Function ForwardWord
Set-PSReadLineKeyHandler -ViMode Insert -Chord 'Ctrl+b' -Function BackwardWord

# j/k in normal mode: history prefix search (mirrors zsh vicmd j/k)
Set-PSReadLineKeyHandler -ViMode Command -Chord 'j' -Function HistorySearchForward
Set-PSReadLineKeyHandler -ViMode Command -Chord 'k' -Function HistorySearchBackward

# Ctrl+V in normal mode: edit command in $EDITOR (mirrors zsh edit-command-line)
Set-PSReadLineKeyHandler -ViMode Command -Chord 'Ctrl+v' -Function ViEditVisually
