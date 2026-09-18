function Get-WinGetPackageState {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [string]$RequestedVersion,
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

    if ($RequestedVersion) {
        $requested = Invoke-DotbotCapturedCommand -FilePath $winget.Path -ArgumentList @(
            'list', '--id', $PackageId, '--exact', '--version', $RequestedVersion,
            '--details', '--disable-interactivity'
        )
        if ($requested.Output -notmatch $packagePattern) {
            return 'drifted'
        }
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

    $state = Get-WinGetPackageState -PackageId $PackageId -RequestedVersion $RequestedVersion -CheckUpdates
    if ($Operation -eq 'status' -or
        ($Operation -eq 'apply' -and $state -in @('current', 'update-available')) -or
        ($Operation -eq 'upgrade' -and $RequestedVersion -and $state -in @('current', 'update-available'))) {
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

    $verified = Get-WinGetPackageState -PackageId $PackageId -RequestedVersion $RequestedVersion -CheckUpdates
    if ($verified -in @('absent', 'blocked', 'drifted')) {
        throw "winget did not verify $PackageId after $verb"
    }
    return $verified
}
