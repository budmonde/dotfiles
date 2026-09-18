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
    $state = if (-not $installed) {
        'absent'
    } elseif ($RequestedVersion -and $installed.Version -ne [Version]$RequestedVersion) {
        'drifted'
    } else {
        'current'
    }
    if ($Operation -eq 'status') {
        return $state
    }
    if (($Operation -eq 'apply' -and $state -eq 'current') -or
        ($Operation -eq 'upgrade' -and $RequestedVersion -and $state -eq 'current')) {
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
