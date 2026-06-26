function Remove-PathEntry {
    param([string]$Dir)
    $parts = $env:PATH -split ';' | Where-Object { $_ -ne $Dir -and $_ -ne '' }
    $env:PATH = $parts -join ';'
}

function Append-PathEntry {
    param([string]$Dir)
    Remove-PathEntry $Dir
    $env:PATH = "$env:PATH;$Dir"
}

function Prepend-PathEntry {
    param([string]$Dir)
    Remove-PathEntry $Dir
    $env:PATH = "$Dir;$env:PATH"
}

# List all Make Targets
function list_make_targets {
    param([string]$Makefile = 'Makefile')
    if (-not (Test-Path -LiteralPath $Makefile)) {
        Write-Host "Makefile '$Makefile' not found!"
        return
    }
    $make = Get-Command make -ErrorAction SilentlyContinue
    if (-not $make) {
        Write-Host "make not on PATH; cannot resolve targets."
        return
    }
    $dump = & make -pRrq -f $Makefile ':' 2>$null
    $targets = $dump |
        Select-String -Pattern '^[a-zA-Z0-9][^$#/\t=]*:([^=]|$)' |
        ForEach-Object { ($_.Line -split ':')[0] } |
        Sort-Object -Unique
    $phony = Get-Content -LiteralPath $Makefile |
        Where-Object { $_ -match '^\.PHONY:' } |
        ForEach-Object { ($_ -replace '^\.PHONY:\s*', '') -split '\s+' } |
        Where-Object { $_ }
    $yellow = "$([char]0x1b)[33m"; $reset = "$([char]0x1b)[0m"
    foreach ($t in $targets) {
        if ($phony -contains $t) { Write-Host "$yellow$t$reset" }
        else                     { Write-Host $t }
    }
}

# Symlink-marker navigation
function here {
    param([string]$Path)
    $loc = if ($Path) { (Resolve-Path -LiteralPath $Path).Path } else { (Get-Location).Path }
    $marker = Join-Path $HOME '.shell.here'
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
    New-Item -ItemType SymbolicLink -Path $marker -Target $loc | Out-Null
    Write-Host "here -> $loc"
}

function there {
    $marker = Join-Path $HOME '.shell.here'
    if (-not (Test-Path -LiteralPath $marker)) {
        Write-Host "No marker set; run \`here\` first."
        return
    }
    $target = (Get-Item -LiteralPath $marker).Target
    if ($target) { Set-Location -LiteralPath $target }
    else         { Set-Location -LiteralPath $marker }
}

# Find latest dir / file by modification time
function latest_dir {
    param([string]$Path = '.')
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Host "No such directory: $Path"; return
    }
    Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function latest_file {
    param([string]$Path = '.')
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Host "No such directory: $Path"; return
    }
    Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
