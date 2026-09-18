function Get-WindowsEnvironmentVariable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [EnvironmentVariableTarget]$Scope = [EnvironmentVariableTarget]::User
    )

    return [Environment]::GetEnvironmentVariable($Name, $Scope)
}

function Test-WindowsEnvironmentValue {
    param(
        [AllowNull()][AllowEmptyString()][string]$Actual,
        [Parameter(Mandatory)][string]$Expected,
        [switch]$Path
    )

    if ([string]::IsNullOrEmpty($Actual)) {
        return $false
    }
    if ($Path) {
        try {
            $actualPath = [IO.Path]::GetFullPath($Actual).TrimEnd('\', '/')
            $expectedPath = [IO.Path]::GetFullPath($Expected).TrimEnd('\', '/')
        } catch {
            return $false
        }
        return $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)
    }
    return $Actual -ceq $Expected
}

function Get-WindowsEnvironmentVariableState {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [EnvironmentVariableTarget]$Scope = [EnvironmentVariableTarget]::User,
        [switch]$Path
    )

    $actual = Get-WindowsEnvironmentVariable -Name $Name -Scope $Scope
    if ([string]::IsNullOrEmpty($actual)) {
        return 'absent'
    }
    if (Test-WindowsEnvironmentValue -Actual $actual -Expected $Value -Path:$Path) {
        return 'current'
    }
    return 'drifted'
}

function Send-WindowsEnvironmentChange {
    if (-not ('DotfilesEnvironmentBroadcast' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class DotfilesEnvironmentBroadcast
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint message,
        UIntPtr wParam,
        string lParam,
        uint flags,
        uint timeout,
        out UIntPtr result);
}
'@
    }
    $broadcastResult = [UIntPtr]::Zero
    $result = [DotfilesEnvironmentBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff,
        0x001A,
        [UIntPtr]::Zero,
        'Environment',
        0x0002,
        5000,
        [ref]$broadcastResult
    )
    if ($result -eq [IntPtr]::Zero) {
        Write-DotbotInstallerDiagnostic 'The Windows environment was persisted, but Windows did not acknowledge the environment-change broadcast'
    }
}

function Set-WindowsEnvironmentVariable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Value,
        [EnvironmentVariableTarget]$Scope = [EnvironmentVariableTarget]::User,
        [switch]$SkipBroadcast
    )

    [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
    if ($Scope -ne [EnvironmentVariableTarget]::Process) {
        [Environment]::SetEnvironmentVariable($Name, $Value, [EnvironmentVariableTarget]::Process)
    }
    Write-DotbotInstallerDiagnostic "Set $Scope environment variable $Name"
    if (-not $SkipBroadcast -and $Scope -ne [EnvironmentVariableTarget]::Process) {
        Send-WindowsEnvironmentChange
    }
}

function Invoke-WindowsEnvironmentVariable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [EnvironmentVariableTarget]$Scope = [EnvironmentVariableTarget]::User,
        [Parameter(Mandatory)][ValidateSet('status', 'apply', 'upgrade')][string]$Operation,
        [switch]$Path
    )

    $state = Get-WindowsEnvironmentVariableState -Name $Name -Value $Value -Scope $Scope -Path:$Path
    if ($Operation -eq 'status' -or $state -eq 'current') {
        return $state
    }
    Set-WindowsEnvironmentVariable -Name $Name -Value $Value -Scope $Scope
    return (Get-WindowsEnvironmentVariableState -Name $Name -Value $Value -Scope $Scope -Path:$Path)
}
