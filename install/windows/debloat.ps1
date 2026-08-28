param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$bloatApps = @(
    'Microsoft.BingSearch',
    'Microsoft.Copilot',
    'Microsoft.Edge.GameAssist',
    'Microsoft.GetHelp',
    'Microsoft.MicrosoftJournal',
    'Microsoft.MicrosoftStickyNotes',
    'Microsoft.Whiteboard',
    'Microsoft.Windows.DevHome',
    'Microsoft.WindowsCamera',
    'MicrosoftCorporationII.MicrosoftFamily',
    'MicrosoftCorporationII.QuickAssist',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.Todos',
    'Microsoft.WidgetsPlatformRuntime',
    'MicrosoftWindows.Client.WebExperience',
    'AppUp.IntelTechnologyMDE',
    'AppUp.IntelManagementandSecurityStatus',
    'aimgr',
    'Microsoft.Xbox.TCUI',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay'
)
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$removablePaths = @(
    (Join-Path $env:USERPROFILE '.copilot')
)
$removableEmptyDirectories = @(
    (Join-Path $env:USERPROFILE 'OneDrive'),
    (Join-Path $env:USERPROFILE '.ms-ad')
)
$localDocumentsPath = Join-Path $env:USERPROFILE 'Documents'
$reviewPaths = @(
    [pscustomobject]@{
        Name = 'NVIDIA Ansel'
        Path = (Join-Path $env:ProgramFiles 'NVIDIA Corporation\Ansel')
    }
)

function Test-EmptyDirectory {
    param([string]$Path)

    return (Test-Path -LiteralPath $Path -PathType Container) -and -not @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Test-ClassicTeamsInstalled {
    $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $winget) {
        return $false
    }
    $output = (& $winget.Path list --id Microsoft.Teams.Classic --exact --details --disable-interactivity 2>$null | Out-String)
    return $output -match '\[Microsoft\.Teams\.Classic\]'
}

function Get-PresentReviewPaths {
    $targets = @($reviewPaths)
    $documentsPath = [Environment]::GetFolderPath('MyDocuments')
    if ($documentsPath -and
        [IO.Path]::GetFullPath($documentsPath) -ne [IO.Path]::GetFullPath($localDocumentsPath)) {
        $targets += [pscustomobject]@{
            Name = 'local Documents'
            Path = $localDocumentsPath
        }
    }
    return @($targets | Where-Object { Test-Path -LiteralPath $_.Path })
}

function Get-DebloatState {
    foreach ($app in $bloatApps) {
        if (Get-AppxPackage -Name "*$app*" -ErrorAction SilentlyContinue) {
            return 'drifted'
        }
    }
    $properties = Get-ItemProperty $runKey -ErrorAction SilentlyContinue
    if ($properties) {
        if (@($properties.PSObject.Properties | Where-Object { $_.Name -like 'MicrosoftEdgeAutoLaunch_*' }).Count -gt 0) {
            return 'drifted'
        }
        if ($properties.PSObject.Properties.Name -contains 'Steam') {
            return 'drifted'
        }
    }
    if (Test-ClassicTeamsInstalled) {
        return 'drifted'
    }
    foreach ($path in $removablePaths) {
        if (Test-Path -LiteralPath $path) {
            return 'drifted'
        }
    }
    foreach ($path in $removableEmptyDirectories) {
        if (Test-EmptyDirectory $path) {
            return 'drifted'
        }
    }
    if (@(Get-PresentReviewPaths).Count -gt 0) {
        return 'drifted'
    }
    return 'current'
}

function Remove-Bloat {
    $failures = @()
    foreach ($app in $bloatApps) {
        foreach ($package in @(Get-AppxPackage -Name "*$app*" -ErrorAction SilentlyContinue)) {
            try {
                $package | Remove-AppxPackage -ErrorAction Stop
                Write-DotbotInstallerDiagnostic "Removed Appx package: $($package.Name)"
            } catch {
                $failures += $_.Exception.Message
            }
        }
    }

    $properties = Get-ItemProperty $runKey -ErrorAction SilentlyContinue
    if ($properties) {
        foreach ($property in @($properties.PSObject.Properties | Where-Object { $_.Name -like 'MicrosoftEdgeAutoLaunch_*' })) {
            Remove-ItemProperty -Path $runKey -Name $property.Name
            Write-DotbotInstallerDiagnostic "Removed startup entry: $($property.Name)"
        }
        if ($properties.PSObject.Properties.Name -contains 'Steam') {
            Remove-ItemProperty -Path $runKey -Name Steam
            Write-DotbotInstallerDiagnostic 'Removed startup entry: Steam'
        }
    }

    if (Test-ClassicTeamsInstalled) {
        $winget = (Get-Command winget -CommandType Application -ErrorAction Stop |
            Select-Object -First 1).Path
        $output = (& $winget uninstall --id Microsoft.Teams.Classic --exact --silent --disable-interactivity 2>&1 | Out-String).Trim()
        if ($output) {
            Write-DotbotInstallerDiagnostic $output
        }
        if ($LASTEXITCODE -ne 0) {
            $failures += "winget failed to remove Microsoft.Teams.Classic with exit code $LASTEXITCODE"
        }
    }

    foreach ($path in $removablePaths) {
        if (Test-Path -LiteralPath $path) {
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                Write-DotbotInstallerDiagnostic "Removed path: $path"
            } catch {
                $failures += $_.Exception.Message
            }
        }
    }

    foreach ($path in $removableEmptyDirectories) {
        if (Test-EmptyDirectory $path) {
            Remove-Item -LiteralPath $path -Force
            Write-DotbotInstallerDiagnostic "Removed empty directory: $path"
        }
    }
    if ($failures.Count -gt 0) {
        throw ($failures -join '; ')
    }
}

Invoke-DotbotInstaller {
    if ($RequestedVersion) {
        throw 'Windows cleanup does not accept a requested version'
    }
    foreach ($target in @(Get-PresentReviewPaths)) {
        Write-DotbotInstallerDiagnostic "Review-only debloat target detected and preserved: $($target.Name) [$($target.Path)]"
    }
    $state = Get-DebloatState
    if ($Operation -eq 'status' -or $state -eq 'current') {
        return $state
    }
    Remove-Bloat
    return (Get-DebloatState)
}
