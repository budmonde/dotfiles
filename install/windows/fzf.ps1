param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$dataHome = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local\share' }
$installDir = Join-Path $dataHome 'fzf'
$binary = Join-Path $installDir 'bin\fzf.exe'

function Get-FzfRelease {
    param([string]$Version)

    $uri = if ($Version) {
        "https://api.github.com/repos/junegunn/fzf/releases/tags/v$($Version.TrimStart('v'))"
    } else {
        'https://api.github.com/repos/junegunn/fzf/releases/latest'
    }
    $release = Invoke-RestMethod -Uri $uri -Headers @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'dotbot-fzf-installer'
    }
    $releaseVersion = ([string]$release.tag_name).TrimStart('v')
    $assetName = "fzf-$releaseVersion-windows_amd64.zip"
    $assets = @($release.assets | Where-Object { $_.name -eq $assetName })
    if ($releaseVersion -notmatch '^[0-9]' -or $assets.Count -ne 1) {
        throw "Could not resolve the Windows x64 asset for fzf $releaseVersion"
    }
    return [pscustomobject]@{
        Asset = $assets[0]
        Tag = [string]$release.tag_name
        Version = $releaseVersion
    }
}

function Get-FzfState {
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
        return 'absent'
    }
    $installed = (& $binary --version 2>$null | Out-String).Trim().Split(' ')[0]
    if ($LASTEXITCODE -ne 0) {
        return 'drifted'
    }
    if ($env:DOTBOT_INSTALL_ONLINE -notin @('0', 'false', 'False', 'no', 'No', 'off', 'Off')) {
        try {
            $latest = Get-FzfRelease
            if ($latest.Version -ne $installed) {
                return 'update-available'
            }
        } catch {
            Write-DotbotInstallerDiagnostic "Could not query the latest fzf version: $($_.Exception.Message)"
        }
    }
    return 'current'
}

function Install-Fzf {
    param([string]$Version)

    $release = Get-FzfRelease -Version $Version
    $temporaryDir = Join-Path $dataHome "fzf.install.$PID"
    $sourceArchivePath = Join-Path $dataHome "fzf.source.$PID.zip"
    $binaryArchivePath = Join-Path $dataHome "fzf.binary.$PID.zip"
    $backupDir = $null
    $runtimeItems = @('bin', 'plugin', 'shell', 'LICENSE')

    foreach ($path in @($temporaryDir, $sourceArchivePath, $binaryArchivePath)) {
        if (Test-Path -LiteralPath $path) {
            throw "Temporary fzf installation path already exists: $path"
        }
    }
    New-Item -ItemType Directory -Force -Path $dataHome | Out-Null

    try {
        Write-DotbotInstallerDiagnostic "Installing fzf $($release.Tag) into $installDir"
        Invoke-WebRequest -Uri "https://github.com/junegunn/fzf/archive/refs/tags/$($release.Tag).zip" -OutFile $sourceArchivePath
        New-Item -ItemType Directory -Path $temporaryDir | Out-Null
        Expand-Archive -LiteralPath $sourceArchivePath -DestinationPath $temporaryDir -Force
        $sourceDirectories = @(Get-ChildItem -LiteralPath $temporaryDir -Directory | Where-Object { $_.Name -like 'fzf-*' })
        if ($sourceDirectories.Count -ne 1) {
            throw "Could not resolve the fzf source directory for $($release.Tag)"
        }
        $sourceDir = $sourceDirectories[0].FullName

        Invoke-WebRequest -Uri $release.Asset.browser_download_url -OutFile $binaryArchivePath
        New-Item -ItemType Directory -Force -Path (Join-Path $sourceDir 'bin') | Out-Null
        Expand-Archive -LiteralPath $binaryArchivePath -DestinationPath (Join-Path $sourceDir 'bin') -Force
        foreach ($item in $runtimeItems) {
            if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $item))) {
                throw "fzf release is missing runtime item: $item"
            }
        }
        $stagedBinary = Join-Path $sourceDir 'bin\fzf.exe'
        $null = & $stagedBinary --version
        if ($LASTEXITCODE -ne 0) {
            throw 'Staged fzf binary validation failed'
        }

        if (Test-Path -LiteralPath $installDir) {
            if (-not (Test-Path -LiteralPath $installDir -PathType Container)) {
                throw "Refusing to replace non-directory fzf installation: $installDir"
            }
            $backupDir = Join-Path $dataHome "fzf.previous.$PID"
            Move-Item -LiteralPath $installDir -Destination $backupDir
        }
        Move-Item -LiteralPath $sourceDir -Destination $installDir
        $null = & $binary --version
        if ($LASTEXITCODE -ne 0) {
            throw 'Active fzf binary validation failed'
        }
        if ($backupDir) {
            Remove-Item -LiteralPath $backupDir -Recurse -Force
            $backupDir = $null
        }
    } catch {
        if ($backupDir -and (Test-Path -LiteralPath $backupDir)) {
            Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $backupDir -Destination $installDir
            $backupDir = $null
        }
        throw
    } finally {
        foreach ($path in @($temporaryDir, $sourceArchivePath, $binaryArchivePath)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-DotbotInstaller {
    $state = Get-FzfState
    if ($Operation -eq 'status' -or ($Operation -eq 'apply' -and $state -in @('current', 'update-available'))) {
        return $state
    }
    Install-Fzf -Version $RequestedVersion
    return (Get-FzfState)
}
