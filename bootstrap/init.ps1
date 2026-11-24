$ErrorActionPreference = 'Stop'

$machineName = $null
$nonInteractive = $false
for ($argumentIndex = 0; $argumentIndex -lt $args.Count; $argumentIndex++) {
    $argument = $args[$argumentIndex]
    if ($argument -in '-y', '--yes') {
        $nonInteractive = $true
        continue
    }
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
$nameMode = [System.IO.FileMode]::CreateNew
if (Test-Path -LiteralPath $machineNamePath) {
    if (-not (Test-Path -LiteralPath $machineNamePath -PathType Leaf)) {
        throw "$machineNamePath must be a file."
    }
    $nameMode = $null
    if (-not $nonInteractive) {
        $answer = Read-Host "Overwrite the machine name in ${machineNamePath}? [y/N]"
        if ($answer -match '^(y|yes)$') {
            $nameMode = [System.IO.FileMode]::Truncate
        }
    }
}

if ($null -eq $nameMode) {
    $names = [System.IO.File]::ReadAllLines($machineNamePath)
    if ($names.Count -ne 1) {
        throw "$machineNamePath must contain one machine name."
    }
    $machineName = $names[0]
} elseif (-not $nonInteractive) {
    $machineName = Read-Host 'Machine name'
} elseif ([string]::IsNullOrEmpty($machineName)) {
    throw "No machine name found at $machineNamePath. Pass --machine_name to supply one."
}
if ([string]::IsNullOrWhiteSpace($machineName) -or
    $machineName -cnotmatch '^[a-z0-9][a-z0-9._-]{0,63}$') {
    throw 'Machine name must be 1-64 lowercase letters, digits, dots, underscores, or hyphens, and must start with a letter or digit.'
}

$clonePath = Join-Path $HOME 'dotfiles'
if (-not $nonInteractive) {
    $chosenPath = Read-Host "Clone path [$clonePath]"
    if (-not [string]::IsNullOrWhiteSpace($chosenPath)) {
        $clonePath = $chosenPath
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

$wingetOptions = @('--accept-source-agreements', '--accept-package-agreements')
if ($nonInteractive) {
    $wingetOptions += '--disable-interactivity'
}
# WinGet can report no applicable update when the package is already current.
$noApplicableUpdate = -1978335189

Write-Host 'Installing Git.Git...'
winget install --id Git.Git @wingetOptions `
    --override '/VERYSILENT /NORESTART /o:SSHOption=ExternalOpenSSH'
if ($LASTEXITCODE -notin 0, $noApplicableUpdate) {
    throw 'Failed to install Git.Git.'
}

Write-Host 'Installing Python.Python.3.14...'
winget install --id Python.Python.3.14 @wingetOptions
if ($LASTEXITCODE -notin 0, $noApplicableUpdate) {
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
    throw "Failed to clone public dotfiles into $clonePath"
}

$recipePlanPath = Join-Path $clonePath '.install-recipes'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($recipePlanPath, "00-base`n", $utf8WithoutBom)
Write-Host "Created base recipe plan at $recipePlanPath"

if ($null -ne $nameMode) {
    $nameBytes = $utf8WithoutBom.GetBytes("$machineName`n")
    $nameStream = [System.IO.File]::Open(
        $machineNamePath,
        $nameMode,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    try {
        $nameStream.Write($nameBytes, 0, $nameBytes.Length)
    } finally {
        $nameStream.Dispose()
    }
}
$env:DOTFILES_MACHINE_ID = $machineName
Write-Host "Using machine identity $machineName from $machineNamePath"

Write-Host "`nBootstrap complete. The public installer and tester are ready:"
Write-Host "  cd $clonePath"
Write-Host '  .\install.ps1'
Write-Host '  .\test.ps1'
