Set-Alias -Name g -Value git

# Typo fixes
function dc { Set-Location @args }

function v { & $env:EDITOR -p @args }
function vs { $env:NVIM_SESSION = 1; nvim @args; Remove-Item Env:\NVIM_SESSION }

function src { . $PROFILE }

function ev { & $env:EDITOR (Join-Path $HOME '.vim/vimrc') }
function ea { & $env:EDITOR (Join-Path $env:XDG_CONFIG_HOME 'powershell/aliases.ps1'); src }
function eg { git config --global -e }

function cdr { Set-Location (git rev-parse --show-toplevel) }

function cdp {
    param([string]$Target)
    if (-not $Target) { Write-Host "Usage: cdp <path>"; return }
    if (Test-Path $Target -PathType Container) {
        Set-Location $Target
    } elseif (Test-Path $Target -PathType Leaf) {
        Set-Location (Split-Path $Target -Parent)
    } else {
        Write-Host "Error: '$Target' is not a valid file or directory"
    }
}

# Python venv activation
function venv {
    param([string]$Name)
    $venvDir = if ($env:XDG_DATA_HOME) { Join-Path $env:XDG_DATA_HOME 'python-venvs' } `
               else { Join-Path $HOME '.local\share\python-venvs' }
    if (-not $Name) {
        Write-Host 'Available venvs:'
        if (Test-Path $venvDir) {
            Get-ChildItem -LiteralPath $venvDir -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host $_.Name }
        } else {
            Write-Host '  (none)'
        }
        return
    }
    $target = Join-Path $venvDir $Name
    $activate = Join-Path $target 'Scripts\Activate.ps1'
    if (Test-Path $activate) {
        . $activate
    } else {
        Write-Host "Venv '$Name' not found in $venvDir"
    }
}

function opencode { & opencode.exe --hostname 127.0.0.1 @args }

function Get-CodexSubcommand {
    param([string[]]$Arguments)

    $commands = @(
        'exec', 'e', 'review', 'login', 'logout', 'mcp', 'plugin', 'mcp-server',
        'app-server', 'remote-control', 'app', 'completion', 'update', 'doctor',
        'sandbox', 'debug', 'apply', 'a', 'resume', 'archive', 'delete',
        'unarchive', 'fork', 'cloud', 'exec-server', 'features', 'help'
    )
    $optionsWithValues = @(
        '-c', '--config', '--enable', '--disable', '--remote',
        '--remote-auth-token-env', '-i', '--image', '-m', '--model',
        '--local-provider', '-p', '--profile', '-s', '--sandbox', '-C', '--cd',
        '--add-dir', '-a', '--ask-for-approval'
    )
    $expectValue = $false

    foreach ($argument in $Arguments) {
        if ($expectValue) {
            $expectValue = $false
            continue
        }
        if ($argument -eq '--') {
            return ''
        }
        if ($optionsWithValues -contains $argument) {
            $expectValue = $true
            continue
        }
        if ($argument.StartsWith('-')) {
            continue
        }
        if ($commands -contains $argument) {
            return $argument
        }
        return ''
    }

    return ''
}

function Get-CodexInvocationPlan {
    param(
        [string[]]$Arguments,
        [string]$EnvironmentProfile = $env:CODEX_PROFILE
    )

    $hasExplicitProfile = $false
    $explicitProfile = $null
    $hasExplicitRemote = $false
    $hasExplicitSandbox = $false
    $expectProfileValue = $false
    $expectRemoteValue = $false
    $expectSandboxValue = $false

    foreach ($argument in $Arguments) {
        if ($expectProfileValue) {
            $explicitProfile = $argument
            $expectProfileValue = $false
            continue
        }
        if ($expectRemoteValue) {
            $expectRemoteValue = $false
            continue
        }
        if ($expectSandboxValue) {
            $expectSandboxValue = $false
            continue
        }

        if ($argument -eq '--profile' -or $argument -eq '-p') {
            $hasExplicitProfile = $true
            $expectProfileValue = $true
        } elseif ($argument -like '--profile=*') {
            $hasExplicitProfile = $true
            $explicitProfile = $argument.Substring('--profile='.Length)
        } elseif ($argument -eq '--remote') {
            $hasExplicitRemote = $true
            $expectRemoteValue = $true
        } elseif ($argument -like '--remote=*') {
            $hasExplicitRemote = $true
        } elseif ($argument -eq '--sandbox' -or $argument -eq '-s') {
            $hasExplicitSandbox = $true
            $expectSandboxValue = $true
        } elseif ($argument -like '--sandbox=*') {
            $hasExplicitSandbox = $true
        }
    }

    $subcommand = Get-CodexSubcommand -Arguments $Arguments
    $informational = [bool]($Arguments | Where-Object { $_ -in @('-h', '--help', '-V', '--version') })
    $profileEligible = -not $informational -and @('', 'exec', 'e', 'review', 'resume', 'fork') -contains $subcommand
    $remoteEligible = -not $informational -and @('', 'resume') -contains $subcommand
    $environmentHasProfile = $EnvironmentProfile -and $EnvironmentProfile -ne 'default'
    $resolvedProfile = if ($hasExplicitProfile) {
        if ($explicitProfile) { $explicitProfile } else { 'explicit' }
    } elseif ($environmentHasProfile) {
        $EnvironmentProfile
    } else {
        'default'
    }
    $useManagedRemote = [bool](
        $remoteEligible -and
        -not $hasExplicitRemote -and
        -not $hasExplicitSandbox
    )

    [pscustomobject]@{
        Subcommand = $subcommand
        Profile = $resolvedProfile
        InjectProfile = [bool]($profileEligible -and $environmentHasProfile -and -not $hasExplicitProfile)
        UseManagedRemote = $useManagedRemote
        ManagedSandbox = if (
            $useManagedRemote -and
            $resolvedProfile -eq 'windows' -and
            -not $hasExplicitSandbox
        ) { 'workspace-write' } else { $null }
        HasExplicitProfile = $hasExplicitProfile
        HasExplicitRemote = $hasExplicitRemote
        HasExplicitSandbox = $hasExplicitSandbox
    }
}

function codex {
    $plan = Get-CodexInvocationPlan -Arguments $args
    $invocationArguments = @()

    Write-Host "Codex profile: $($plan.Profile)"

    if ($plan.InjectProfile) {
        $invocationArguments += @('--profile', $env:CODEX_PROFILE)
    }

    if ($plan.UseManagedRemote) {
        $hostCommand = Get-Command codex-host -ErrorAction SilentlyContinue
        if ($hostCommand) {
            & $hostCommand start
            if ($LASTEXITCODE -eq 0) {
                if ($plan.ManagedSandbox) {
                    $invocationArguments += @('--sandbox', $plan.ManagedSandbox)
                }
                $invocationArguments += @('--remote', 'ws://127.0.0.1:4500')
            } else {
                Write-Warning 'Codex App Server startup failed; continuing in direct mode without managed notifications.'
            }
        } else {
            Write-Warning 'codex-host is unavailable; continuing in direct mode without managed notifications.'
        }
    }

    $invocationArguments += $args
    & codex.cmd @invocationArguments
}
