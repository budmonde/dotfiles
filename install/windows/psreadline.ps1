# PSReadLine upgrade script (Windows)
# Windows PowerShell 5.1 ships PSReadLine 2.0.0, which lacks -PredictionSource
# and -PredictionViewStyle (introduced in 2.1.0 and 2.2.0 respectively). This
# installs the latest PSReadLine from PSGallery into CurrentUser scope, which
# overrides the in-box version on subsequent session start.
#
# Note: PSReadLine is already loaded by the host before profile.ps1 runs, so
# the upgrade only takes effect after the next shell launch.
#
# Bootstraps PackageManagement if needed (PowerShellGet 2.x requires >= 1.4.4,
# but fresh Windows installs only ship 1.0.0.1).

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$minVersion = [Version]'1.4.4'
$installed = Get-Module PackageManagement -ListAvailable |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $installed -or $installed.Version -lt $minVersion) {
    Write-Host "PackageManagement $($installed.Version) < $minVersion - bootstrapping..."

    $bootstrapVersion = '1.4.8.1'
    $destDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) `
        "WindowsPowerShell\Modules\PackageManagement\$bootstrapVersion"

    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $zip = Join-Path $env:TEMP "PackageManagement.$bootstrapVersion.zip"
    $url = "https://www.powershellgallery.com/api/v2/package/PackageManagement/$bootstrapVersion"
    (New-Object System.Net.WebClient).DownloadFile($url, $zip)
    Expand-Archive -Path $zip -DestinationPath $destDir -Force
    Remove-Item $zip

    Import-Module PackageManagement -RequiredVersion $bootstrapVersion -Force
    Write-Host "PackageManagement $bootstrapVersion installed"
}

# Ensure NuGet provider is present (Install-Module prompts interactively without it)
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
}

# -SkipPublisherCheck is required because the in-box PSReadLine is signed by
# Microsoft and the PSGallery copy is signed by a different certificate.
Install-Module -Name PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
$latest = Get-Module PSReadLine -ListAvailable |
    Sort-Object Version -Descending |
    Select-Object -First 1
Write-Host "PSReadLine $($latest.Version) installed (restart shell to activate)"
