$script:InstallerStates = @(
    'absent',
    'blocked',
    'current',
    'drifted',
    'unsupported',
    'update-available'
)

function Write-DotbotInstallerDiagnostic {
    param([Parameter(Mandatory)][string]$Message)

    [Console]::Error.WriteLine($Message)
}

function Invoke-DotbotInstaller {
    param([Parameter(Mandatory)][scriptblock]$Handler)

    try {
        $results = @(& $Handler)
        if ($results.Count -ne 1 -or $results[0] -notin $script:InstallerStates) {
            throw "Installer returned an invalid lifecycle result: $($results -join ', ')"
        }
        [Console]::Out.WriteLine([string]$results[0])
    } catch {
        Write-DotbotInstallerDiagnostic $_.Exception.Message
        exit 1
    }
}

function Invoke-DotbotCapturedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    $output = (& $FilePath @ArgumentList 2>&1 | Out-String).Trim()
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}

function Test-DotbotInstallerOnline {
    return $env:DOTBOT_INSTALL_ONLINE -notin @('0', 'false', 'False', 'no', 'No', 'off', 'Off')
}
