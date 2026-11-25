# XDG Base Directory Specification
# https://specifications.freedesktop.org/basedir/latest/
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = "$HOME\.config" }
if (-not $env:XDG_DATA_HOME) { $env:XDG_DATA_HOME = "$HOME\.local\share" }
if (-not $env:XDG_STATE_HOME) { $env:XDG_STATE_HOME = "$HOME\.local\state" }
if (-not $env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME = "$HOME\.cache" }
