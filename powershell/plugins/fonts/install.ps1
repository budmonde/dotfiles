# Font installation script (Windows)
# Fetches font archives from GitHub and installs them to the user font directory.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$fonts = @(
    @{
        Repo    = 'microsoft/cascadia-code'
        Pattern = 'CascadiaCode-*.zip'
        Filter  = '*NF*.ttf'
    }
)

$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) { New-Item -ItemType Directory -Path $fontDir -Force | Out-Null }

$regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

foreach ($font in $fonts) {
    # Skip download if matching fonts are already installed.
    $existing = Get-ChildItem $fontDir -Filter '*.ttf' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $font.Filter }
    if ($existing) {
        Write-Host "Fonts from $($font.Repo) already installed"
        continue
    }

    $release = Invoke-RestMethod "https://api.github.com/repos/$($font.Repo)/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -like $font.Pattern } | Select-Object -First 1
    if (-not $asset) {
        Write-Warning "No matching asset for $($font.Repo)"
        continue
    }

    $zip = Join-Path $env:TEMP $asset.name
    $extractDir = Join-Path $env:TEMP ($asset.name -replace '\.zip$', '')

    Write-Host "Downloading $($asset.name)..."
    (New-Object System.Net.WebClient).DownloadFile($asset.browser_download_url, $zip)
    Expand-Archive -Path $zip -DestinationPath $extractDir -Force

    $installed = 0
    Get-ChildItem $extractDir -Recurse -Filter '*.ttf' |
        Where-Object { $_.Name -like $font.Filter } |
        ForEach-Object {
            $dest = Join-Path $fontDir $_.Name
            if (-not (Test-Path $dest)) {
                Copy-Item $_.FullName $dest
                $fontName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                Set-ItemProperty -Path $regKey -Name "$fontName (TrueType)" -Value $dest
                $installed++
            }
        }

    Remove-Item $zip -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -ErrorAction SilentlyContinue

    if ($installed -gt 0) {
        Write-Host "Installed $installed fonts from $($font.Repo)"
    }
}
