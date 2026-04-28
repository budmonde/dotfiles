$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Install fzf binary into the submodule bin directory (mirrors ./shell/plugins/fzf/install --bin)
$fzfDir = Join-Path $PSScriptRoot '..\..\..\shell\plugins\fzf'
$fzfDir = (Resolve-Path $fzfDir).Path
$binDir = Join-Path $fzfDir 'bin'

$exe = Join-Path $binDir 'fzf.exe'
if (Test-Path $exe) {
    Write-Host "fzf already installed at $exe"
    exit 0
}

# Parse version from the bash install script (e.g. "version=0.70.0")
$installScript = Join-Path $fzfDir 'install'
$versionLine = Select-String -Path $installScript -Pattern '^version=' | Select-Object -First 1
$version = ($versionLine -split '=')[1]

$arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '386' }
$url = "https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-windows_${arch}.zip"

$zip = Join-Path $env:TEMP "fzf-${version}-windows_${arch}.zip"
Write-Host "Downloading fzf v${version}..."
(New-Object System.Net.WebClient).DownloadFile($url, $zip)

if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
Expand-Archive -Path $zip -DestinationPath $binDir -Force
Remove-Item $zip

Write-Host "fzf v${version} installed to $binDir"
