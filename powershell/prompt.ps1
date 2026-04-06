$script:ESC = [char]0x1b

$script:Color = @{
    Red     = "$ESC[38;5;196m"
    Green   = "$ESC[38;5;10m"
    Yellow  = "$ESC[38;5;11m"
    Blue    = "$ESC[38;5;33m"
    Magenta = "$ESC[38;5;127m"
    Cyan    = "$ESC[38;5;81m"
    Teal    = "$ESC[38;5;31m"
    Orange  = "$ESC[38;5;166m"
    Olive   = "$ESC[38;5;148m"
    Neon    = "$ESC[38;5;120m"
    Violet  = "$ESC[38;5;98m"
    Gray    = "$ESC[38;5;246m"
    Reset   = "$ESC[0m"
    Bold    = "$ESC[1m"
}

function Get-MachineName {
    if (Test-Path "$HOME\.name") { return (Get-Content "$HOME\.name" -Raw).Trim() }
    return $env:COMPUTERNAME.ToLower()
}

function Get-GitBranch {
    if (-not (Test-Path .git)) {
        $root = git rev-parse --show-toplevel 2>$null
        if (-not $root) { return '' }
    }
    $ref = git symbolic-ref -q --short HEAD 2>$null
    if (-not $ref) { $ref = git rev-parse --short HEAD 2>$null }
    if (-not $ref) { return '' }
    return $ref
}

function Get-VenvPrompt {
    if (-not $env:VIRTUAL_ENV) { return '' }
    $name = Split-Path $env:VIRTUAL_ENV -Leaf
    if ($name -eq '.venv') { $name = Split-Path (Split-Path $env:VIRTUAL_ENV -Parent) -Leaf }
    return "$($Color.Yellow)[venv:$($Color.Orange)$name$($Color.Yellow)]$($Color.Reset) "
}

function prompt {
    $lastOk = $?
    $realLASTEXITCODE = $global:LASTEXITCODE

    $statusChar = if ($lastOk) { "$($Color.Blue)#$($Color.Reset)" } else { "$($Color.Red)!$($Color.Reset)" }

    $user = $env:USERNAME
    $machine = Get-MachineName
    $path = $executionContext.SessionState.Path.CurrentLocation.Path
    $branch = Get-GitBranch
    $gitBranch = if ($branch) { " $($Color.Cyan)git:$($Color.Reset)($($Color.Red)$branch$($Color.Reset))" } else { '' }
    $venv = Get-VenvPrompt

    $arrow = "$($Color.Bold)>$($Color.Reset)"

    $global:LASTEXITCODE = $realLASTEXITCODE

    # Tell Windows Terminal the current working directory (OSC 9;9)
    $Host.UI.Write("$ESC]9;9;`"$path`"$ESC\")

    # Set terminal tab/pane title (OSC 2)
    $dirName = Split-Path $path -Leaf
    $titleBranch = if ($branch) { " : $branch" } else { '' }
    $Host.UI.Write("$ESC]2;PS1 | $dirName$titleBranch$([char]7)")
    "`n" +
    "$statusChar " +
    "$($Color.Teal)$user$($Color.Reset) " +
    "$($Color.Gray)at$($Color.Reset) " +
    "$($Color.Violet)$machine$($Color.Reset) " +
    "$($Color.Gray)in$($Color.Reset) " +
    "$($Color.Olive)$($Color.Bold)$path$($Color.Reset)" +
    "$gitBranch" +
    "`n" +
    "$venv" +
    "$($Color.Blue)$arrow$($Color.Reset) "
}
