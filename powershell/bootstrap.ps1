# Personal paths (highest priority)
if (Test-Path "$HOME\bin") { Prepend-PathEntry "$HOME\bin" }
if (Test-Path "$HOME\.local\bin") { Prepend-PathEntry "$HOME\.local\bin" }

# Tool-managed paths (fnm PATH is set by plugins.ps1 via `fnm env`)
if (Test-Path "$HOME\.opencode\bin") { Prepend-PathEntry "$HOME\.opencode\bin" }
