[CmdletBinding()]
param(
    [string]$DocumentsPath = [Environment]::GetFolderPath('MyDocuments'),
    [string]$HomePath = $HOME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProfileSourcePath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\config\profile.ps1')).Path
$HomeLoaderStart = '# >>> dotfiles PowerShell profile entry point >>>'
$HomeLoaderEnd = '# <<< dotfiles PowerShell profile entry point <<<'
$DocumentsLoaderStart = '# >>> dotfiles PowerShell profile loader >>>'
$DocumentsLoaderEnd = '# <<< dotfiles PowerShell profile loader <<<'
$escapedProfileSourcePath = $ProfileSourcePath.Replace("'", "''")
$HomeLoaderBlock = @"
$HomeLoaderStart
`$dotfilesProfile = '$escapedProfileSourcePath'

if (Test-Path -LiteralPath `$dotfilesProfile) {
    . `$dotfilesProfile
}
$HomeLoaderEnd
"@.TrimEnd()
$DocumentsLoaderBlock = @"
$DocumentsLoaderStart
`$dotfilesProfile = Join-Path `$HOME '.profile.ps1'

if (Test-Path -LiteralPath `$dotfilesProfile) {
    . `$dotfilesProfile
}
$DocumentsLoaderEnd
"@.TrimEnd()

function Test-DotfilesProfileLink {
    param([System.IO.FileSystemInfo]$ProfileItem)

    foreach ($target in @($ProfileItem.Target)) {
        if ($null -eq $target) {
            continue
        }

        $targetPath = [string]$target
        if ($targetPath -ieq $ProfileSourcePath) {
            return $true
        }

        if ($targetPath.Replace('/', '\') -match '(?i)(^|\\)dotfiles\\common\\(config\\)?profile\.ps1$') {
            return $true
        }
    }

    return $false
}

function Get-UpdatedProfileContent {
    param(
        [string]$ExistingContent,
        [string]$LoaderStart,
        [string]$LoaderEnd,
        [string]$LoaderBlock
    )

    $loaderPattern = '(?ms)^' + [regex]::Escape($LoaderStart) + '\r?\n.*?^' + [regex]::Escape($LoaderEnd) + '\r?\n?'
    if ($ExistingContent -match $loaderPattern) {
        return [regex]::Replace($ExistingContent, $loaderPattern, $LoaderBlock)
    }

    if ([string]::IsNullOrWhiteSpace($ExistingContent)) {
        return $LoaderBlock
    }

    return $ExistingContent.TrimEnd("`r", "`n") + [Environment]::NewLine + [Environment]::NewLine + $LoaderBlock
}

function Install-ProfileLoader {
    param(
        [string]$ProfilePath,
        [string]$LoaderStart,
        [string]$LoaderEnd,
        [string]$LoaderBlock
    )

    $existingContent = ''
    if (Test-Path -LiteralPath $ProfilePath) {
        $profileItem = Get-Item -LiteralPath $ProfilePath -Force
        # OneDrive Files On-Demand marks ordinary synced files as reparse points.
        if ($profileItem.LinkType -in @('SymbolicLink', 'Junction')) {
            if (-not (Test-DotfilesProfileLink $profileItem)) {
                throw "Refusing to replace unrelated profile link: $ProfilePath"
            }

            Remove-Item -LiteralPath $ProfilePath -Force
        } else {
            $existingContent = Get-Content -LiteralPath $ProfilePath -Raw
        }
    }

    $profileDirectory = Split-Path -Parent $ProfilePath
    New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null

    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    $updatedContent = Get-UpdatedProfileContent -ExistingContent $existingContent -LoaderStart $LoaderStart -LoaderEnd $LoaderEnd -LoaderBlock $LoaderBlock
    [System.IO.File]::WriteAllText($ProfilePath, $updatedContent + [Environment]::NewLine, $encoding)
    Write-Host "PowerShell profile loader installed at $ProfilePath"
}

$HomeProfilePath = Join-Path $HomePath '.profile.ps1'
Install-ProfileLoader -ProfilePath $HomeProfilePath -LoaderStart $HomeLoaderStart -LoaderEnd $HomeLoaderEnd -LoaderBlock $HomeLoaderBlock

$DocumentsProfilePaths = @(
    (Join-Path $DocumentsPath 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $DocumentsPath 'PowerShell\Microsoft.PowerShell_profile.ps1')
)

foreach ($profilePath in $DocumentsProfilePaths) {
    Install-ProfileLoader -ProfilePath $profilePath -LoaderStart $DocumentsLoaderStart -LoaderEnd $DocumentsLoaderEnd -LoaderBlock $DocumentsLoaderBlock
}
