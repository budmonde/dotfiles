# Preserve process-specific PATH entries and pick up machine or user PATH entries
# registered by installers since the parent terminal started.
Merge-EnvironmentPath

# Tool-managed paths
$fzfBin = Join-Path $env:XDG_DATA_HOME 'fzf\bin'
if (Test-Path $fzfBin) { Prepend-PathEntry $fzfBin }

# Personal paths (highest priority)
if (Test-Path "$HOME\.local\bin") { Prepend-PathEntry "$HOME\.local\bin" }
if (Test-Path "$HOME\bin") { Prepend-PathEntry "$HOME\bin" }
