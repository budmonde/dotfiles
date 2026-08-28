param(
    [ValidateSet('status', 'apply', 'upgrade')][string]$Operation = 'apply',
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'install\lib\windows\Lifecycle.psm1') -Force

$profileSourcePath = (Resolve-Path (Join-Path $env:DOTBOT_INSTALL_REPO_ROOT 'config\profile.ps1')).Path
$loaderStart = '# >>> dotfiles PowerShell profile loader >>>'
$loaderEnd = '# <<< dotfiles PowerShell profile loader <<<'
$loaderBlock = @"
$loaderStart
`$dotfilesProfile = Join-Path `$HOME '.profile.ps1'

if (Test-Path -LiteralPath `$dotfilesProfile) {
    . `$dotfilesProfile
}
$loaderEnd
"@.TrimEnd()

function Test-DotfilesProfileLink {
    param([System.IO.FileSystemInfo]$ProfileItem)

    foreach ($target in @($ProfileItem.Target)) {
        if ($null -eq $target) {
            continue
        }
        $targetPath = [string]$target
        if ($targetPath -ieq $profileSourcePath -or $targetPath.Replace('/', '\') -match '(?i)(^|\\)dotfiles\\common\\(config\\)?profile\.ps1$') {
            return $true
        }
    }
    return $false
}

function Get-UpdatedProfileContent {
    param([string]$ExistingContent)

    $loaderPattern = '(?ms)^' + [regex]::Escape($loaderStart) + '\r?\n.*?^' + [regex]::Escape($loaderEnd) + '\r?\n?'
    if ($ExistingContent -match $loaderPattern) {
        return [regex]::Replace($ExistingContent, $loaderPattern, $loaderBlock).TrimEnd("`r", "`n")
    }
    if ([string]::IsNullOrWhiteSpace($ExistingContent)) {
        return $loaderBlock
    }
    return $ExistingContent.TrimEnd("`r", "`n") + [Environment]::NewLine + [Environment]::NewLine + $loaderBlock
}

function Get-ProfileLoaderState {
    foreach ($profilePath in $profilePaths) {
        if (-not (Test-Path -LiteralPath $profilePath)) {
            return 'drifted'
        }
        $profileItem = Get-Item -LiteralPath $profilePath -Force
        if ($profileItem.LinkType -in @('SymbolicLink', 'Junction')) {
            return $(if (Test-DotfilesProfileLink $profileItem) { 'drifted' } else { 'blocked' })
        }
        $content = Get-Content -LiteralPath $profilePath -Raw
        if ($content.TrimEnd("`r", "`n") -ne (Get-UpdatedProfileContent -ExistingContent $content)) {
            return 'drifted'
        }
    }
    return 'current'
}

function Install-ProfileLoader {
    param([string]$ProfilePath)

    $existingContent = ''
    if (Test-Path -LiteralPath $ProfilePath) {
        $profileItem = Get-Item -LiteralPath $ProfilePath -Force
        if ($profileItem.LinkType -in @('SymbolicLink', 'Junction')) {
            if (-not (Test-DotfilesProfileLink $profileItem)) {
                throw "Refusing to replace unrelated profile link: $ProfilePath"
            }
            Remove-Item -LiteralPath $ProfilePath -Force
        } else {
            $existingContent = Get-Content -LiteralPath $ProfilePath -Raw
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProfilePath) | Out-Null
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $ProfilePath,
        (Get-UpdatedProfileContent -ExistingContent $existingContent) + [Environment]::NewLine,
        $encoding
    )
    Write-DotbotInstallerDiagnostic "PowerShell profile loader installed at $ProfilePath"
}

$documentsPath = [Environment]::GetFolderPath('MyDocuments')
$profilePaths = @(
    (Join-Path $documentsPath 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $documentsPath 'PowerShell\Microsoft.PowerShell_profile.ps1')
)

Invoke-DotbotInstaller {
    if ($RequestedVersion) {
        throw 'PowerShell profile loaders do not accept a requested version'
    }
    $state = Get-ProfileLoaderState
    if ($Operation -eq 'status' -or $state -eq 'current' -or $state -eq 'blocked') {
        return $state
    }
    foreach ($profilePath in $profilePaths) {
        Install-ProfileLoader -ProfilePath $profilePath
    }
    return (Get-ProfileLoaderState)
}
