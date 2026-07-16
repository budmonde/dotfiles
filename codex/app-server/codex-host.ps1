param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'status', 'stop')]
    [string]$Command = 'status',
    [switch]$LibraryMode
)

$Endpoint = 'ws://127.0.0.1:4500'
$Port = 4500
$UserHome = [Environment]::GetFolderPath('UserProfile')
$StateRoot = if ($env:XDG_STATE_HOME) {
    $env:XDG_STATE_HOME
} else {
    Join-Path $UserHome '.local\state'
}
$StateDirectory = Join-Path $StateRoot 'codex-app-server'
$HostPidPath = Join-Path $StateDirectory 'host.pid'
$MonitorPidPath = Join-Path $StateDirectory 'monitor.pid'
$HostOutputLog = Join-Path $StateDirectory 'host.log'
$HostErrorLog = Join-Path $StateDirectory 'host-error.log'
$MonitorOutputLog = Join-Path $StateDirectory 'monitor.log'
$MonitorErrorLog = Join-Path $StateDirectory 'monitor-error.log'
$MonitorPath = Join-Path $PSScriptRoot 'notification-monitor.mjs'
$BaseConfigPath = Join-Path $UserHome '.codex\config.toml'
$ProfileConfigPath = Join-Path $UserHome '.codex\windows.config.toml'

function Get-AppServerArguments {
    return @(
        'app-server', '--listen', $Endpoint
    )
}

function Get-MonitorArguments {
    return @($MonitorPath, '--endpoint', $Endpoint)
}

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

function Test-AppServerCommandLine {
    param([string]$CommandLine)

    return [bool](
        $CommandLine -and
        $CommandLine -match '(?i)(^|\s)app-server(\s|$)' -and
        $CommandLine -match [regex]::Escape($Endpoint)
    )
}

function Test-AppServerProcess {
    param([int]$ProcessId)

    if (-not (Test-ProcessExists -ProcessId $ProcessId)) {
        return $false
    }
    return Test-AppServerCommandLine -CommandLine (Get-ProcessCommandLine -ProcessId $ProcessId)
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
        $listener = Get-NetTCPConnection `
            -LocalAddress '127.0.0.1' `
            -LocalPort $Port `
            -State Listen `
            -ErrorAction Stop |
            Select-Object -First 1
        if ($listener) {
            return [int]$listener.OwningProcess
        }
    } catch {
        return $null
    }
    return $null
}

function Get-NodeCommand {
    return Get-Command node.exe -ErrorAction SilentlyContinue
}

function Test-WindowsConfigReady {
    if (
        -not (Test-Path -LiteralPath $BaseConfigPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ProfileConfigPath -PathType Leaf)
    ) {
        return $false
    }
    return (Get-Content -Raw -LiteralPath $BaseConfigPath) -ceq
        (Get-Content -Raw -LiteralPath $ProfileConfigPath)
}

function Test-ReadyEndpoint {
    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri "http://127.0.0.1:$Port/readyz" `
            -TimeoutSec 1 `
            -ErrorAction Stop
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Wait-ReadyEndpoint {
    param(
        [Diagnostics.Process]$Launcher,
        [int]$TimeoutSeconds = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-ReadyEndpoint) {
            return $true
        }
        if ($Launcher -and $Launcher.HasExited) {
            return $false
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
        Write-Error 'Node.js is unavailable; notification monitoring cannot start.'
        return $false
    }
    if (-not (Test-Path -LiteralPath $MonitorPath -PathType Leaf)) {
        Write-Error "Notification monitor is missing at $MonitorPath."
        return $false
    }

    & $node.Source $MonitorPath --check 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'The installed Node.js runtime does not provide the required WebSocket API.'
        return $false
    }

    try {
        $monitorProcess = Start-Process `
            -FilePath $node.Source `
            -ArgumentList (Get-MonitorArguments) `
            -WorkingDirectory $UserHome `
            -RedirectStandardOutput $MonitorOutputLog `
            -RedirectStandardError $MonitorErrorLog `
            -WindowStyle Hidden `
            -PassThru
        Start-Sleep -Milliseconds 300
        if ($monitorProcess.HasExited) {
            Write-Error "Notification monitor exited during startup. See $MonitorErrorLog."
            return $false
        }
        Set-RecordedProcessId -Path $MonitorPidPath -ProcessId $monitorProcess.Id
        Write-Host "Started Codex notification monitor (PID $($monitorProcess.Id))."
        return $true
    } catch {
        Write-Error "Could not start Codex notification monitor: $($_.Exception.Message)"
        return $false
    }
}

function Start-ManagedHost {
    Initialize-StateDirectory
    if (-not (Test-WindowsConfigReady)) {
        Write-Error 'Codex App Server requires config.toml and windows.config.toml to match. Run the Windows local Dotbot install, then retry.'
        return $false
    }
    $listenerId = Get-ListeningProcessId

    if ($listenerId) {
        if (
            (Test-AppServerProcess -ProcessId $listenerId) -and
            (Test-ReadyEndpoint)
        ) {
            Set-RecordedProcessId -Path $HostPidPath -ProcessId $listenerId
            Write-Host "Codex App Server is already running (PID $listenerId)."
            return Start-NotificationMonitor
        }
        Write-Error "Port $Port is occupied by another process."
        return $false
    }

    Remove-RecordedProcessId -Path $HostPidPath
    $codex = Get-Command codex.cmd -ErrorAction SilentlyContinue
    if (-not $codex) {
        Write-Error 'codex.cmd is unavailable; Codex App Server cannot start.'
        return $false
    }

    try {
        $launcher = Start-Process `
            -FilePath $codex.Source `
            -ArgumentList (Get-AppServerArguments) `
            -WorkingDirectory $UserHome `
            -RedirectStandardOutput $HostOutputLog `
            -RedirectStandardError $HostErrorLog `
            -WindowStyle Hidden `
            -PassThru
    } catch {
        Write-Error "Could not launch Codex App Server: $($_.Exception.Message)"
        return $false
    }

    if (-not (Wait-ReadyEndpoint -Launcher $launcher)) {
        $failedListenerId = Get-ListeningProcessId
        if ($failedListenerId -and (Test-AppServerProcess -ProcessId $failedListenerId)) {
            Stop-Process -Id $failedListenerId -Force -ErrorAction SilentlyContinue
        } elseif (-not $launcher.HasExited) {
            Stop-Process -Id $launcher.Id -Force -ErrorAction SilentlyContinue
        }
        Write-Error "Codex App Server did not become ready. See $HostErrorLog."
        return $false
    }

    $hostProcessId = Get-ListeningProcessId
    if (-not $hostProcessId) {
        Write-Error 'Codex App Server became ready but its listener could not be identified.'
        return $false
    }
    Set-RecordedProcessId -Path $HostPidPath -ProcessId $hostProcessId
    Write-Host "Started Codex App Server (PID $hostProcessId) at $Endpoint."
    return Start-NotificationMonitor
}

function Show-ManagedStatus {
    Initialize-StateDirectory
    $listenerId = Get-ListeningProcessId
    $hostRunning = [bool](
        $listenerId -and
        (Test-AppServerProcess -ProcessId $listenerId) -and
        (Test-ReadyEndpoint)
    )
    if ($hostRunning) {
        Set-RecordedProcessId -Path $HostPidPath -ProcessId $listenerId
    }

    $monitorId = Get-RecordedProcessId -Path $MonitorPidPath
    $monitorRunning = [bool](
        $monitorId -and
        (Test-MonitorProcess -ProcessId $monitorId)
    )

    if ($hostRunning) {
        Write-Host "Host: running (PID $listenerId) at $Endpoint"
    } else {
        Write-Host 'Host: stopped or unhealthy'
    }
    if ($monitorRunning) {
        Write-Host "Monitor: running (PID $monitorId)"
    } else {
        Write-Host 'Monitor: stopped'
    }
    Write-Host "State: $StateDirectory"
    Write-Host "Host logs: $HostOutputLog, $HostErrorLog"
    Write-Host "Monitor logs: $MonitorOutputLog, $MonitorErrorLog"

    return $hostRunning -and $monitorRunning
}

function Stop-RecordedMonitor {
    $processId = Get-RecordedProcessId -Path $MonitorPidPath
    if (-not $processId) {
        Write-Host 'Codex notification monitor is not recorded as running.'
        return $true
    }
    if (-not (Test-ProcessExists -ProcessId $processId)) {
        Remove-RecordedProcessId -Path $MonitorPidPath
        Write-Host 'Codex notification monitor was already stopped.'
        return $true
    }
    if (-not (Test-MonitorProcess -ProcessId $processId)) {
        Write-Error "Refusing to stop PID $processId because it is not the notification monitor."
        return $false
    }

    Stop-Process -Id $processId -Force -ErrorAction Stop
    Remove-RecordedProcessId -Path $MonitorPidPath
    Write-Host "Stopped Codex notification monitor (PID $processId)."
    return $true
}

function Stop-ManagedAppServer {
    $processId = Get-ListeningProcessId
    if (-not $processId) {
        $recordedId = Get-RecordedProcessId -Path $HostPidPath
        if ($recordedId -and (Test-ProcessExists -ProcessId $recordedId)) {
            $processId = $recordedId
        }
    }
    if (-not $processId) {
        Remove-RecordedProcessId -Path $HostPidPath
        Write-Host 'Codex App Server was already stopped.'
        return $true
    }
    if (-not (Test-AppServerProcess -ProcessId $processId)) {
        Write-Error "Refusing to stop PID $processId because it is not the managed loopback App Server."
        return $false
    }

    Stop-Process -Id $processId -Force -ErrorAction Stop
    Remove-RecordedProcessId -Path $HostPidPath
    Write-Host "Stopped Codex App Server (PID $processId)."
    return $true
}

function Stop-ManagedHost {
    Initialize-StateDirectory
    $monitorStopped = Stop-RecordedMonitor
    $hostStopped = Stop-ManagedAppServer
    return $monitorStopped -and $hostStopped
}

if ($LibraryMode) {
    return
}

$requiresLock = $Command -in @('start', 'stop')
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
