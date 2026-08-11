# PSFzf installation script (Windows)
# Bootstraps PackageManagement if needed (PowerShellGet 2.x requires >= 1.4.4,
# but fresh Windows installs only ship 1.0.0.1)

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

Install-Module -Name PSFzf -Scope CurrentUser -Force
Write-Host "PSFzf installed"
