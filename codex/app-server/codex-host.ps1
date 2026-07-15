param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'status', 'stop')]
    [string]$Command = 'status'
)

$Endpoint = 'ws://127.0.0.1:4500'
$Port = 4500
$StateRoot = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $HOME '.local\state' }
$StateDirectory = Join-Path $StateRoot 'codex-app-server'
$HostPidPath = Join-Path $StateDirectory 'host.pid'
$MonitorPidPath = Join-Path $StateDirectory 'monitor.pid'
$HostOutputLog = Join-Path $StateDirectory 'host.log'
$HostErrorLog = Join-Path $StateDirectory 'host-error.log'
$MonitorOutputLog = Join-Path $StateDirectory 'monitor.log'
$MonitorErrorLog = Join-Path $StateDirectory 'monitor-error.log'
$MonitorPath = Join-Path $PSScriptRoot 'notification-monitor.mjs'

function Initialize-StateDirectory {
    if (-not (Test-Path -LiteralPath $StateDirectory)) {
        New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null
    }
}

function Get-RecordedProcessId {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $value = (Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue).Trim()
    $parsed = 0
    if ([int]::TryParse($value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Set-RecordedProcessId {
    param(
        [string]$Path,
        [int]$ProcessId
    )

    Set-Content -LiteralPath $Path -Value $ProcessId -Encoding ASCII
}

function Remove-RecordedProcessId {
    param([string]$Path)

    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-ProcessExists {
    param([int]$ProcessId)

    return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Get-ProcessCommandLine {
    param([int]$ProcessId)

    try {
        return (Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop).CommandLine
    } catch {
        return $null
    }
}

function Test-HostProcess {
    param([int]$ProcessId)

    if (-not (Test-ProcessExists -ProcessId $ProcessId)) {
        return $false
    }
    $commandLine = Get-ProcessCommandLine -ProcessId $ProcessId
    return [bool](
        $commandLine -and
        $commandLine -match '(?i)(^|\s)app-server(\s|$)' -and
        $commandLine -match [regex]::Escape($Endpoint)
    )
}

function Test-MonitorProcess {
    param([int]$ProcessId)

    if (-not (Test-ProcessExists -ProcessId $ProcessId)) {
        return $false
    }
    $commandLine = Get-ProcessCommandLine -ProcessId $ProcessId
    return [bool](
        $commandLine -and
        $commandLine -match [regex]::Escape('notification-monitor.mjs') -and
        $commandLine -match [regex]::Escape($Endpoint)
    )
}

function Get-ListeningProcessId {
    try {
        $listener = Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $Port -State Listen -ErrorAction Stop |
            Select-Object -First 1
        if ($listener) {
            return [int]$listener.OwningProcess
        }
    } catch {
        return $null
    }
    return $null
}

function Test-ReadyEndpoint {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/readyz" -TimeoutSec 1 -ErrorAction Stop
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Get-NodeCommand {
    return Get-Command node.exe -ErrorAction SilentlyContinue
}

function Test-CodexEndpoint {
    $node = Get-NodeCommand
    if (-not $node -or -not (Test-Path -LiteralPath $MonitorPath)) {
        return $false
    }

    & $node.Source $MonitorPath --probe --endpoint $Endpoint 1>$null 2>$null
    return $LASTEXITCODE -eq 0
}

function Wait-CodexEndpoint {
    param([int]$TimeoutSeconds = 15)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-ReadyEndpoint) {
            return $true
        }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Start-NotificationMonitor {
    $recordedId = Get-RecordedProcessId -Path $MonitorPidPath
    if ($recordedId -and (Test-MonitorProcess -ProcessId $recordedId)) {
        Write-Host "Codex notification monitor is already running (PID $recordedId)."
        return $true
    }
    Remove-RecordedProcessId -Path $MonitorPidPath

    $node = Get-NodeCommand
    if (-not $node) {
        Write-Warning 'Node.js is unavailable; Codex notification monitoring was not started.'
        return $false
    }
    if (-not (Test-Path -LiteralPath $MonitorPath)) {
        Write-Warning "Notification monitor is missing at $MonitorPath."
        return $false
    }

    & $node.Source $MonitorPath --check 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'The installed Node.js runtime does not provide the required WebSocket API.'
        return $false
    }

    try {
        $monitorProcess = Start-Process -FilePath $node.Source `
            -ArgumentList @("`"$MonitorPath`"", '--endpoint', $Endpoint) `
            -RedirectStandardOutput $MonitorOutputLog `
            -RedirectStandardError $MonitorErrorLog `
            -WindowStyle Hidden `
            -PassThru
        Start-Sleep -Milliseconds 500
        if ($monitorProcess.HasExited) {
            Write-Warning "Codex notification monitor exited during startup. See $MonitorErrorLog."
            return $false
        }
        Set-RecordedProcessId -Path $MonitorPidPath -ProcessId $monitorProcess.Id
        Write-Host "Started Codex notification monitor (PID $($monitorProcess.Id))."
        return $true
    } catch {
        Write-Warning "Could not start Codex notification monitor: $($_.Exception.Message)"
        return $false
    }
}

function Start-ManagedHost {
    Initialize-StateDirectory
    $listenerId = Get-ListeningProcessId

    if ($listenerId) {
        if ((Test-ReadyEndpoint) -and (Test-CodexEndpoint)) {
            Set-RecordedProcessId -Path $HostPidPath -ProcessId $listenerId
            Write-Host "Codex App Server is already running (PID $listenerId)."
            if (-not (Start-NotificationMonitor)) {
                Write-Warning 'Codex App Server is available, but its notification and policy monitor is unavailable.'
                return $false
            }
            return $true
        }
        Write-Error "Port $Port is occupied by a process that is not a compatible Codex App Server."
        return $false
    }

    Remove-RecordedProcessId -Path $HostPidPath
    $codex = Get-Command codex.cmd -ErrorAction SilentlyContinue
    if (-not $codex) {
        Write-Error 'codex.cmd is unavailable; Codex App Server cannot start.'
        return $false
    }

    try {
        $launcher = Start-Process -FilePath $codex.Source `
            -ArgumentList @('-c', 'sandbox_mode=workspace-write', '-c', 'approval_policy=on-request', '-c', 'approvals_reviewer=auto_review', 'app-server', '--listen', $Endpoint) `
            -WorkingDirectory $HOME `
            -RedirectStandardOutput $HostOutputLog `
            -RedirectStandardError $HostErrorLog `
            -WindowStyle Hidden `
            -PassThru
    } catch {
        Write-Error "Could not launch Codex App Server: $($_.Exception.Message)"
        return $false
    }

    if (-not (Wait-CodexEndpoint)) {
        if (-not $launcher.HasExited) {
            Stop-Process -Id $launcher.Id -Force -ErrorAction SilentlyContinue
        }
        Write-Error "Codex App Server did not become ready. See $HostErrorLog."
        return $false
    }
    if (-not (Test-CodexEndpoint)) {
        $unexpectedListenerId = Get-ListeningProcessId
        if ($unexpectedListenerId) {
            Stop-Process -Id $unexpectedListenerId -Force -ErrorAction SilentlyContinue
        }
        Write-Error "The listener on port $Port did not complete a Codex initialization handshake."
        return $false
    }

    $hostProcessId = Get-ListeningProcessId
    if (-not $hostProcessId) {
        Write-Error 'Codex App Server became ready but its listener process could not be identified.'
        return $false
    }
    Set-RecordedProcessId -Path $HostPidPath -ProcessId $hostProcessId
    Write-Host "Started Codex App Server (PID $hostProcessId) at $Endpoint."

    if (-not (Start-NotificationMonitor)) {
        Write-Warning 'Codex App Server is available, but its notification and policy monitor is unavailable.'
        return $false
    }
    return $true
}

function Show-ManagedStatus {
    Initialize-StateDirectory
    $hostProcessId = Get-RecordedProcessId -Path $HostPidPath
    $monitorProcessId = Get-RecordedProcessId -Path $MonitorPidPath
    $hostRunning = [bool](
        $hostProcessId -and
        (Test-HostProcess -ProcessId $hostProcessId) -and
        (Test-ReadyEndpoint) -and
        (Test-CodexEndpoint)
    )
    $monitorRunning = [bool](
        $monitorProcessId -and
        (Test-MonitorProcess -ProcessId $monitorProcessId)
    )

    if ($hostRunning) {
        Write-Host "Host: running (PID $hostProcessId) at $Endpoint"
    } else {
        Write-Host 'Host: stopped or unhealthy'
    }
    if ($monitorRunning) {
        Write-Host "Monitor: running (PID $monitorProcessId)"
    } else {
        Write-Host 'Monitor: stopped'
    }
    Write-Host "State: $StateDirectory"
    Write-Host "Host logs: $HostOutputLog, $HostErrorLog"
    Write-Host "Monitor logs: $MonitorOutputLog, $MonitorErrorLog"

    return $hostRunning -and $monitorRunning
}

function Stop-RecordedProcess {
    param(
        [string]$Name,
        [string]$PidPath,
        [scriptblock]$Validator
    )

    $recordedId = Get-RecordedProcessId -Path $PidPath
    if (-not $recordedId) {
        Write-Host "$Name is not recorded as running."
        return $true
    }
    if (-not (Test-ProcessExists -ProcessId $recordedId)) {
        Remove-RecordedProcessId -Path $PidPath
        Write-Host "$Name was already stopped."
        return $true
    }

    if (-not (& $Validator $recordedId)) {
        Write-Error "Refusing to stop PID $recordedId because it no longer matches $Name."
        return $false
    }

    Stop-Process -Id $recordedId -Force -ErrorAction Stop
    Remove-RecordedProcessId -Path $PidPath
    Write-Host "Stopped $Name (PID $recordedId)."
    return $true
}

function Stop-ManagedHost {
    Initialize-StateDirectory
    $monitorStopped = Stop-RecordedProcess `
        -Name 'Codex notification monitor' `
        -PidPath $MonitorPidPath `
        -Validator { param($id) Test-MonitorProcess -ProcessId $id }
    $hostStopped = Stop-RecordedProcess `
        -Name 'Codex App Server' `
        -PidPath $HostPidPath `
        -Validator { param($id) Test-HostProcess -ProcessId $id }
    return $monitorStopped -and $hostStopped
}

$requiresLock = $Command -eq 'start' -or $Command -eq 'stop'
$mutex = $null
$lockAcquired = $false
$success = $false

try {
    if ($requiresLock) {
        $mutex = New-Object System.Threading.Mutex($false, 'Local\DotfilesCodexAppServerHost')
        try {
            $lockAcquired = $mutex.WaitOne([TimeSpan]::FromSeconds(20))
        } catch [System.Threading.AbandonedMutexException] {
            $lockAcquired = $true
        }
        if (-not $lockAcquired) {
            Write-Error 'Timed out waiting for another codex-host operation to finish.'
            exit 1
        }
    }

    switch ($Command) {
        'start' { $success = Start-ManagedHost }
        'status' { $success = Show-ManagedStatus }
        'stop' { $success = Stop-ManagedHost }
    }
} finally {
    if ($lockAcquired) {
        $mutex.ReleaseMutex()
    }
    if ($mutex) {
        $mutex.Dispose()
    }
}

if (-not $success) {
    exit 1
}
