# Tool-managed paths
$fzfBin = if ($env:XDG_DATA_HOME) { Join-Path $env:XDG_DATA_HOME 'fzf\bin' } else { "$HOME\.local\share\fzf\bin" }
if (Test-Path $fzfBin) { Prepend-PathEntry $fzfBin }

# Personal paths (highest priority)
if (Test-Path "$HOME\.local\bin") { Prepend-PathEntry "$HOME\.local\bin" }
if (Test-Path "$HOME\bin") { Prepend-PathEntry "$HOME\bin" }
