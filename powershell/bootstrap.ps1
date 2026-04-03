# Personal paths (highest priority)
if (Test-Path "$HOME\bin") { Prepend-PathEntry "$HOME\bin" }
Prepend-PathEntry "$HOME\.dotfiles\bin"
if (Test-Path "$HOME\.local\bin") { Prepend-PathEntry "$HOME\.local\bin" }

# fzf (from dotfiles submodule)
$fzfBin = "$HOME\.dotfiles\shell\plugins\fzf\bin"
if (Test-Path $fzfBin) { Prepend-PathEntry $fzfBin }

# Tool-managed paths (fnm PATH is set by plugins.ps1 via `fnm env`)
if (Test-Path "$HOME\.opencode\bin") { Prepend-PathEntry "$HOME\.opencode\bin" }
