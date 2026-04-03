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
