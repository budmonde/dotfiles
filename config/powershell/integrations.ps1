param(
    [switch]$Interactive
)

###############################################################################
# Fast Node Managed (fnm)
###############################################################################
# Base activation exposes Node and npm in every shell;
# directory switching is interactive-only.
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    $fnmArguments = @('env', '--shell', 'powershell')
    if ($Interactive) {
        $fnmArguments += '--use-on-cd'
    }
    & fnm @fnmArguments | Out-String | Invoke-Expression
}
