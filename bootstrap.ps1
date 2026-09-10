$ErrorActionPreference = 'Stop'

$machineName = $null
$nonInteractive = $false
for ($argumentIndex = 0; $argumentIndex -lt $args.Count; $argumentIndex++) {
    $argument = $args[$argumentIndex]
    if ($argument -eq '--machine_name') {
        if ($argumentIndex + 1 -ge $args.Count) {
            throw '--machine_name requires a value.'
        }
        $argumentIndex++
        $machineName = $args[$argumentIndex]
        $nonInteractive = $true
        continue
    }
    if ($argument -like '--machine_name=*') {
        $machineName = $argument.Substring('--machine_name='.Length)
        $nonInteractive = $true
        continue
    }
    throw "Unknown bootstrap argument: $argument"
}

$machineNamePath = Join-Path $HOME '.name'
if (Test-Path -LiteralPath $machineNamePath) {
    throw "$machineNamePath already exists. Remove it explicitly before bootstrapping a different machine identity."
}

if (-not $nonInteractive) {
    $machineName = Read-Host 'Machine name'
}
if ([string]::IsNullOrWhiteSpace($machineName) -or
    $machineName -cnotmatch '^[a-z0-9][a-z0-9._-]{0,63}$') {
    throw 'Machine name must be 1-64 lowercase letters, digits, dots, underscores, or hyphens, and must start with a letter or digit.'
}

$defaultPath = Join-Path (Join-Path $HOME 'dotfiles') 'common'
if ($nonInteractive) {
    $clonePath = $defaultPath
} else {
    $clonePath = Read-Host "Clone path [$defaultPath]"
    if ([string]::IsNullOrWhiteSpace($clonePath)) {
        $clonePath = $defaultPath
    }
}
if (Test-Path -LiteralPath $clonePath) {
    throw "$clonePath already exists. Choose an empty destination or remove it before bootstrapping."
}

if ((Get-ExecutionPolicy -Scope CurrentUser) -eq 'Restricted') {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host 'Set execution policy to RemoteSigned'
}

$windowsApps = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -split ';' -notcontains $windowsApps) {
    [Environment]::SetEnvironmentVariable('PATH', "$userPath;$windowsApps", 'User')
    $env:PATH += ";$windowsApps"
    Write-Host 'Added WindowsApps to user PATH'
}

winget source remove msstore 2>$null

Write-Host 'Installing Git.Git...'
winget install --id Git.Git --accept-source-agreements --accept-package-agreements `
    --override '/VERYSILENT /NORESTART /o:SSHOption=ExternalOpenSSH'
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to install Git.Git.'
}

Write-Host 'Installing Python.Python.3.14...'
winget install --id Python.Python.3.14 --accept-source-agreements --accept-package-agreements
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to install Python.Python.3.14.'
}

$env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH', 'User')

if ((Get-Service ssh-agent).StartType -ne 'Automatic') {
    Set-Service ssh-agent -StartupType Automatic
}
Start-Service ssh-agent -ErrorAction SilentlyContinue

git clone https://github.com/budmonde/dotfiles.git $clonePath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to clone common dotfiles into $clonePath"
}

$recipePlanPath = Join-Path $clonePath '.install-recipes'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($recipePlanPath, "00-base`n", $utf8WithoutBom)
Write-Host "Created base recipe plan at $recipePlanPath"

$nameStream = [System.IO.File]::Open(
    $machineNamePath,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
)
try {
    $nameWriter = New-Object System.IO.StreamWriter($nameStream, $utf8WithoutBom)
    try {
        $nameWriter.Write("$machineName`n")
    } finally {
        $nameWriter.Dispose()
    }
} finally {
    $nameStream.Dispose()
}
$env:DOTFILES_MACHINE_ID = $machineName
Write-Host "Created machine identity at $machineNamePath"

Write-Host "`nBootstrap complete. The common installer and tester are ready:"
Write-Host "  cd $clonePath"
Write-Host '  .\install.ps1'
Write-Host '  .\test.ps1'
