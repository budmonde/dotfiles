###############################################################################
### fnm (Fast Node Manager)
###############################################################################
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

###############################################################################
### PSFzf (fzf integration for PSReadLine)
###############################################################################
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

###############################################################################
### CompletionPredictor (richer PSReadLine predictions)
###############################################################################
# Adds completion-based predictions alongside history. Paired with the
# -PredictionSource setting from settings.ps1; promotes to HistoryAndPlugin
# only after the module successfully imports.
if (Get-Module -ListAvailable -Name CompletionPredictor) {
    Import-Module CompletionPredictor
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
}
