param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$fonts = @(
    @{
        Repo = 'microsoft/cascadia-code'
        Pattern = 'CascadiaCode-*.zip'
        Filter = '*NF*.ttf'
    },
    @{
        Repo = 'alerque/libertinus'
        Pattern = 'Libertinus-*.zip'
        Filter = '*.otf'
    }
)
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$registryKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

function Test-FontFamilyInstalled {
    param([hashtable]$Font)

    $extension = [System.IO.Path]::GetExtension($Font.Filter)
    return @(
        Get-ChildItem $fontDir -Filter "*$extension" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $Font.Filter }
    ).Count -gt 0
}

function Get-FontState {
    $installed = @($fonts | Where-Object { Test-FontFamilyInstalled $_ }).Count
    if ($installed -eq $fonts.Count) {
        return 'current'
    }
    return $(if ($installed -eq 0) { 'absent' } else { 'drifted' })
}

function Install-FontFamily {
    param([hashtable]$Font)

    if (Test-FontFamilyInstalled $Font) {
        return
    }
    $release = Invoke-RestMethod "https://api.github.com/repos/$($Font.Repo)/releases/latest"
    $assets = @($release.assets | Where-Object { $_.name -like $Font.Pattern })
    if ($assets.Count -ne 1) {
        throw "Expected one matching font asset for $($Font.Repo), found $($assets.Count)"
    }

    $temporary = Join-Path $env:TEMP "dotbot-fonts-$PID-$([Guid]::NewGuid().ToString('N'))"
    $archive = "$temporary.zip"
    try {
        New-Item -ItemType Directory -Path $temporary | Out-Null
        Invoke-WebRequest -Uri $assets[0].browser_download_url -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $temporary -Force
        $extension = [System.IO.Path]::GetExtension($Font.Filter)
        $registrySuffix = if ($extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
        foreach ($file in @(
            Get-ChildItem $temporary -Recurse -Filter "*$extension" |
                Where-Object { $_.Name -like $Font.Filter }
        )) {
            $destination = Join-Path $fontDir $file.Name
            if (-not (Test-Path -LiteralPath $destination)) {
                Copy-Item -LiteralPath $file.FullName -Destination $destination
                $fontName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                Set-ItemProperty -Path $registryKey -Name "$fontName ($registrySuffix)" -Value $destination
                Write-DotbotInstallerDiagnostic "Installed font: $($file.Name)"
            }
        }
    } finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-DotbotInstaller {
    if ($RequestedVersion) {
        throw 'Font bundles do not accept a requested version'
    }
    $state = Get-FontState
    if ($Operation -eq 'status' -or ($Operation -eq 'apply' -and $state -eq 'current')) {
        return $state
    }
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    New-Item -ItemType Directory -Force -Path $registryKey | Out-Null
    foreach ($font in $fonts) {
        Install-FontFamily -Font $font
    }
    return (Get-FontState)
}
