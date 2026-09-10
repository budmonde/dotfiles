param(
    [string]$HomePath = $HOME
)

$machineNamePath = Join-Path $HomePath '.name'
if (-not (Test-Path -LiteralPath $machineNamePath -PathType Leaf)) {
    Remove-Item Env:DOTFILES_MACHINE_ID -ErrorAction SilentlyContinue
    return
}

try {
    $machineNameLines = [System.IO.File]::ReadAllLines($machineNamePath)
} catch {
    Remove-Item Env:DOTFILES_MACHINE_ID -ErrorAction SilentlyContinue
    Write-Warning "Unable to read machine name from $machineNamePath."
    return
}
if ($machineNameLines.Count -eq 1 -and $machineNameLines[0] -cmatch '^[a-z0-9][a-z0-9._-]{0,63}$') {
    $env:DOTFILES_MACHINE_ID = $machineNameLines[0]
    return
}

Remove-Item Env:DOTFILES_MACHINE_ID -ErrorAction SilentlyContinue
Write-Warning "Ignoring invalid machine name in $machineNamePath."
