Set-Alias -Name g -Value git

function v { & $env:EDITOR -p @args }
function vs { $env:NVIM_SESSION = 1; nvim @args; Remove-Item Env:\NVIM_SESSION }

function src { . $PROFILE }

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
