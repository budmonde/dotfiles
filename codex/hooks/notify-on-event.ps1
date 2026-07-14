param(
    [Parameter(Mandatory)]
    [ValidateSet('completion', 'permission')]
    [string]$Event
)

$rawHookInput = [Console]::In.ReadToEnd()
$hookInput = if ($rawHookInput) { $rawHookInput | ConvertFrom-Json -ErrorAction Stop } else { $null }
$cwd = if ($hookInput -and $hookInput.cwd) { $hookInput.cwd } else { (Get-Location).Path }
$directory = Split-Path -Leaf $cwd
$branch = & git -C $cwd symbolic-ref --quiet --short HEAD 2>$null

if (-not $branch) {
    $branch = & git -C $cwd rev-parse --short HEAD 2>$null
}

$title = if ($branch) { "$directory : $branch" } else { $directory }

if ($Event -eq 'permission') {
    & push-notify --sound 'Windows Exclamation' $title 'Event: Permission required'
    exit $LASTEXITCODE
}

& push-notify $title 'Event: Task completed'
exit $LASTEXITCODE
