Set-Alias -Name g -Value git

# Typo fixes
function dc { Set-Location @args }

function v { & $env:EDITOR -p @args }
function vs { $env:NVIM_SESSION = 1; nvim @args; Remove-Item Env:\NVIM_SESSION }

function src { . $PROFILE }

function ev { & $env:EDITOR (Join-Path $HOME '.vim/vimrc') }
function ea { & $env:EDITOR (Join-Path $env:XDG_CONFIG_HOME 'powershell/aliases.ps1'); src }
function eg { git config --global -e }

function cdr { Set-Location (git rev-parse --show-toplevel) }

function cdp {
    param([string]$Target)
    if (-not $Target) { Write-Host "Usage: cdp <path>"; return }
    if (Test-Path $Target -PathType Container) {
        Set-Location $Target
    } elseif (Test-Path $Target -PathType Leaf) {
        Set-Location (Split-Path $Target -Parent)
    } else {
        Write-Host "Error: '$Target' is not a valid file or directory"
    }
}

# Python venv activation
function venv {
    param([string]$Name)
    $venvDir = if ($env:XDG_DATA_HOME) { Join-Path $env:XDG_DATA_HOME 'python-venvs' } `
               else { Join-Path $HOME '.local\share\python-venvs' }
    if (-not $Name) {
        Write-Host 'Available venvs:'
        if (Test-Path $venvDir) {
            Get-ChildItem -LiteralPath $venvDir -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host $_.Name }
        } else {
            Write-Host '  (none)'
        }
        return
    }
    $target = Join-Path $venvDir $Name
    $activate = Join-Path $target 'Scripts\Activate.ps1'
    if (Test-Path $activate) {
        . $activate
    } else {
        Write-Host "Venv '$Name' not found in $venvDir"
    }
}

function opencode { & opencode.exe --hostname 127.0.0.1 @args }
