$ErrorActionPreference = 'Stop'

$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/junegunn/fzf/releases/latest' -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'dotfiles-fzf-installer' }
$releaseTag = [string]$release.tag_name
$releaseVersion = $releaseTag.TrimStart('v')
$assetName = "fzf-$releaseVersion-windows_amd64.zip"
$asset = @($release.assets | Where-Object { $_.name -eq $assetName })

if ($releaseTag -notmatch '^v[0-9]' -or $asset.Count -ne 1) {
    throw "Could not resolve the Windows x64 asset for fzf release '$releaseTag'"
}

$dataHome = if ($env:XDG_DATA_HOME) {
    $env:XDG_DATA_HOME
} else {
    Join-Path $HOME '.local\share'
}
$installDir = Join-Path $dataHome 'fzf'
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
    Write-Host "Installing fzf $releaseTag into $installDir"
    Invoke-WebRequest -Uri "https://github.com/junegunn/fzf/archive/refs/tags/$releaseTag.zip" -OutFile $sourceArchivePath
    New-Item -ItemType Directory -Path $temporaryDir | Out-Null
    Expand-Archive -LiteralPath $sourceArchivePath -DestinationPath $temporaryDir -Force
    $sourceDir = @(Get-ChildItem -LiteralPath $temporaryDir -Directory | Where-Object { $_.Name -like 'fzf-*' })
    if ($sourceDir.Count -ne 1) {
        throw "Could not resolve fzf source directory for release '$releaseTag'"
    }

    Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $binaryArchivePath
    New-Item -ItemType Directory -Force -Path (Join-Path $sourceDir[0].FullName 'bin') | Out-Null
    Expand-Archive -LiteralPath $binaryArchivePath -DestinationPath (Join-Path $sourceDir[0].FullName 'bin') -Force

    foreach ($item in $runtimeItems) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceDir[0].FullName $item))) {
            throw "fzf release is missing runtime item: $item"
        }
    }

    if (Test-Path -LiteralPath $installDir) {
        $backupDir = Join-Path $dataHome "fzf.previous.$PID"
        New-Item -ItemType Directory -Path $backupDir | Out-Null
        Get-ChildItem -LiteralPath $installDir -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $backupDir -Recurse -Force
        }
        Remove-Item -LiteralPath $installDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $installDir | Out-Null
    foreach ($item in $runtimeItems) {
        Copy-Item -LiteralPath (Join-Path $sourceDir[0].FullName $item) -Destination $installDir -Recurse -Force
    }

    $binary = Join-Path $installDir 'bin\fzf.exe'
    if (-not (Test-Path -LiteralPath $binary)) {
        throw 'fzf installation did not produce bin\fzf.exe'
    }

    & $binary --version
    if ($LASTEXITCODE -ne 0) {
        throw "fzf binary validation failed with exit code $LASTEXITCODE"
    }

    if ($backupDir) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force
        $backupDir = $null
    }
} catch {
    if ($backupDir -and (Test-Path -LiteralPath $backupDir)) {
        if (Test-Path -LiteralPath $installDir) {
            Remove-Item -LiteralPath $installDir -Recurse -Force
        }

        New-Item -ItemType Directory -Path $installDir | Out-Null
        Get-ChildItem -LiteralPath $backupDir -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $installDir -Recurse -Force
        }
        Remove-Item -LiteralPath $backupDir -Recurse -Force
        $backupDir = $null
    }

    throw
} finally {
    foreach ($path in @($temporaryDir, $sourceArchivePath, $binaryArchivePath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}
