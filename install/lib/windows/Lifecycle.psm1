Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Restart-DotbotInstallerInPowerShellCore {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$Operation,
        [string]$RequestedVersion
    )

    if ($PSVersionTable.PSEdition -eq 'Core') {
        return
    }
    $pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $pwsh) {
        $programFilesPwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (Test-Path -LiteralPath $programFilesPwsh) {
            $pwsh = Get-Item -LiteralPath $programFilesPwsh
        }
    }
    if (-not $pwsh) {
        Write-DotbotInstallerDiagnostic 'PowerShell 7 is required to install PowerShell Gallery modules'
        exit 1
    }

    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $ScriptPath, $Operation)
    if ($RequestedVersion) {
        $arguments += $RequestedVersion
    }
    & $pwsh.Path @arguments
    exit $LASTEXITCODE
}

function Get-WinGetPackageState {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [switch]$CheckUpdates
    )

    $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $winget) {
        return 'blocked'
    }

    $details = Invoke-DotbotCapturedCommand -FilePath $winget.Path -ArgumentList @(
        'list', '--id', $PackageId, '--exact', '--details', '--disable-interactivity'
    )
    $packagePattern = '\[' + [regex]::Escape($PackageId) + '\]'
    if ($details.Output -notmatch $packagePattern) {
        if ($details.Output -match 'No installed package found' -or $details.ExitCode -eq -1978335212) {
            return 'absent'
        }
        if ($details.ExitCode -ne 0) {
            throw "winget could not inspect $PackageId`: $($details.Output)"
        }
        return 'absent'
    }

    if (-not $CheckUpdates -or -not (Test-DotbotInstallerOnline)) {
        return 'current'
    }
    $upgrade = Invoke-DotbotCapturedCommand -FilePath $winget.Path -ArgumentList @(
        'list', '--id', $PackageId, '--exact', '--upgrade-available', '--include-unknown',
        '--include-pinned', '--details', '--disable-interactivity'
    )
    if ($upgrade.Output -match $packagePattern) {
        return 'update-available'
    }
    return 'current'
}

function Invoke-WinGetPackage {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][ValidateSet('status', 'apply', 'upgrade')][string]$Operation,
        [string]$RequestedVersion
    )

    $state = Get-WinGetPackageState -PackageId $PackageId -CheckUpdates
    if ($Operation -eq 'status' -or ($Operation -eq 'apply' -and $state -ne 'absent')) {
        return $state
    }
    if ($state -eq 'blocked') {
        return $state
    }

    $winget = (Get-Command winget -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Path
    $verb = if ($state -eq 'absent') { 'install' } else { 'upgrade' }
    $arguments = @(
        $verb, '--id', $PackageId, '--exact', '--accept-source-agreements',
        '--accept-package-agreements', '--disable-interactivity'
    )
    if ($RequestedVersion) {
        $arguments += @('--version', $RequestedVersion)
    }
    $result = Invoke-DotbotCapturedCommand -FilePath $winget -ArgumentList $arguments
    if ($result.Output) {
        Write-DotbotInstallerDiagnostic $result.Output
    }
    if ($result.ExitCode -ne 0 -and $result.ExitCode -ne -1978335189) {
        throw "winget $verb failed for $PackageId with exit code $($result.ExitCode)"
    }

    $verified = Get-WinGetPackageState -PackageId $PackageId -CheckUpdates
    if ($verified -eq 'absent' -or $verified -eq 'blocked') {
        throw "winget did not verify $PackageId after $verb"
    }
    return $verified
}

function Initialize-PowerShellGallery {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $minimumVersion = [Version]'1.4.4'
    $installed = Get-Module PackageManagement -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $installed -or $installed.Version -lt $minimumVersion) {
        $bootstrapVersion = '1.4.8.1'
        $destination = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Modules\PackageManagement\$bootstrapVersion"
        $archive = Join-Path $env:TEMP "PackageManagement.$bootstrapVersion.$PID.zip"
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        try {
            (New-Object System.Net.WebClient).DownloadFile(
                "https://www.powershellgallery.com/api/v2/package/PackageManagement/$bootstrapVersion",
                $archive
            )
            Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force
        } finally {
            Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        }
        Import-Module PackageManagement -RequiredVersion $bootstrapVersion -Force
    }
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    }
}

function Invoke-PowerShellGalleryModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('status', 'apply', 'upgrade')][string]$Operation,
        [string]$RequestedVersion,
        [switch]$SkipPublisherCheck
    )

    $installed = Get-Module $Name -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($Operation -eq 'status') {
        return $(if ($installed) { 'current' } else { 'absent' })
    }
    if ($Operation -eq 'apply' -and $installed) {
        return 'current'
    }

    Initialize-PowerShellGallery
    $arguments = @{
        Name = $Name
        Scope = 'CurrentUser'
        Force = $true
        AllowClobber = $true
    }
    if ($RequestedVersion) {
        $arguments.RequiredVersion = $RequestedVersion
    }
    if ($SkipPublisherCheck) {
        $arguments.SkipPublisherCheck = $true
    }
    Install-Module @arguments | Out-Null

    $verified = Get-Module $Name -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $verified) {
        throw "PowerShell Gallery did not install $Name"
    }
    if ($RequestedVersion -and $verified.Version -ne [Version]$RequestedVersion) {
        throw "Installed $Name $($verified.Version), expected $RequestedVersion"
    }
    return 'current'
}

Export-ModuleMember -Function @(
    'Invoke-DotbotInstaller',
    'Invoke-PowerShellGalleryModule',
    'Invoke-WinGetPackage',
    'Restart-DotbotInstallerInPowerShellCore',
    'Write-DotbotInstallerDiagnostic'
)
