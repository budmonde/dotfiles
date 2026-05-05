<#
.SYNOPSIS
    Sync Command Palette (CmdPal) settings by writing directly to disk.

.DESCRIPTION
    Applies declared CmdPal configuration from template files, supporting
    environment variable placeholders and a common/local override merge strategy.

    Strategy: stop CmdPal, write settings to disk, restart CmdPal.

    Config is discovered from $env:XDG_CONFIG_HOME/cmdpal/ (falls back to
    ~/.config/cmdpal/).

.PARAMETER DryRun
    Preview resolved JSON without applying.

.PARAMETER Export
    Capture live CmdPal disk state into the settings/ template files.

.EXAMPLE
    Sync-CmdPalSettings              # apply declared config
    Sync-CmdPalSettings -DryRun      # preview what would be applied
    Sync-CmdPalSettings -Export      # export live state to template files
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Export
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Paths ---
$PackageFamily = 'Microsoft.CommandPalette_8wekyb3d8bbwe'
$CmdPalDataDir = Join-Path $env:LOCALAPPDATA "Packages\$PackageFamily\LocalState"
$CmdPalProcessNames = @('Microsoft.CmdPal.UI', 'Microsoft.CmdPal.Ext.PowerToys')
$PowerToysExe = 'C:\Program Files\PowerToys\PowerToys.exe'

$ConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
$CpConfig = Join-Path $ConfigHome 'cmdpal'

if (-not (Test-Path $CpConfig)) {
    Write-Error "Config directory not found: $CpConfig"
    exit 1
}

$SettingsDir = Join-Path $CpConfig 'settings'
$OverrideDir = Join-Path $CpConfig 'settings.d'

# Files to sync (excludes state.json and caches)
$SyncFiles = @('settings.json', 'apps.settings.json')

# --- Helper: Deep-merge two hashtables (override wins) ---
function Merge-Deep {
    param(
        [System.Collections.IDictionary]$Base,
        [System.Collections.IDictionary]$Override
    )
    $result = [ordered]@{}
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }
    foreach ($key in $Override.Keys) {
        if ($result.Contains($key) -and
            $result[$key] -is [System.Collections.IDictionary] -and
            $Override[$key] -is [System.Collections.IDictionary]) {
            $result[$key] = Merge-Deep $result[$key] $Override[$key]
        } else {
            $result[$key] = $Override[$key]
        }
    }
    return $result
}

# --- Helper: Convert PSCustomObject to ordered hashtable (recursive) ---
function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IList]) {
            $arr = @()
            foreach ($item in $InputObject) {
                $arr += , (ConvertTo-Hashtable $item)
            }
            return , $arr
        }
        if ($InputObject -is [PSCustomObject]) {
            $ht = [ordered]@{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
            }
            return $ht
        }
        return $InputObject
    }
}

# --- Helper: Resolve ${ENV_VAR} placeholders in a string ---
function Resolve-Placeholders {
    param([string]$Text)
    $pattern = '\$\{([^}]+)\}'
    $resolved = [regex]::Replace($Text, $pattern, {
        param($match)
        $varName = $match.Groups[1].Value
        $val = [Environment]::GetEnvironmentVariable($varName)
        if ($null -eq $val) { return $match.Value }
        return $val
    })
    return $resolved
}

# --- Helper: Check if any unresolved placeholders remain ---
function Test-UnresolvedPlaceholders {
    param([string]$Json)
    return $Json -match '\$\{[^}]+\}'
}

# --- Helper: Get unresolved variable names ---
function Get-UnresolvedVars {
    param([string]$Json)
    $matches_ = [regex]::Matches($Json, '\$\{([^}]+)\}')
    return ($matches_ | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique
}

# --- Helper: Write JSON to disk (merge into existing file) ---
function Write-SettingsFile {
    param(
        [System.Collections.IDictionary]$Declared,
        [string]$DiskPath
    )

    if (Test-Path $DiskPath) {
        $diskContent = [System.IO.File]::ReadAllText($DiskPath, [System.Text.Encoding]::UTF8)
        $diskObj = $diskContent | ConvertFrom-Json | ConvertTo-Hashtable
    } else {
        $diskObj = [ordered]@{}
        $dir = Split-Path $DiskPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    $merged = Merge-Deep $diskObj $Declared

    $jsonOut = $merged | ConvertTo-Json -Depth 50
    $tempPath = "$DiskPath.tmp"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tempPath, $jsonOut, $utf8NoBom)
    Move-Item -Path $tempPath -Destination $diskPath -Force
}

# --- Helper: Stop CmdPal (and PowerToys host, since CmdPal can't restart standalone) ---
function Stop-CmdPal {
    $procs = Get-Process -Name $CmdPalProcessNames -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Stopping CmdPal..."
        $procs | Stop-Process -Force
    }
    # CmdPal extension host is managed by PowerToys -- restart PT host to respawn it
    $pt = Get-Process -Name 'PowerToys' -ErrorAction SilentlyContinue
    if ($pt) {
        Write-Host "Stopping PowerToys host..."
        $pt | Stop-Process -Force
    }
    $timeout = [datetime]::Now.AddSeconds(10)
    while ((Get-Process -Name @($CmdPalProcessNames + 'PowerToys') -ErrorAction SilentlyContinue) -and [datetime]::Now -lt $timeout) {
        Start-Sleep -Milliseconds 200
    }
}

# --- Helper: Start PowerToys (which relaunches CmdPal) ---
function Start-CmdPal {
    if (Test-Path $PowerToysExe) {
        Write-Host "Starting PowerToys..."
        Start-Process -FilePath $PowerToysExe
    } else {
        Write-Warning "PowerToys.exe not found at $PowerToysExe -- please start manually."
    }
}

# --- EXPORT mode ---
if ($Export) {
    if (-not (Test-Path $CmdPalDataDir)) {
        Write-Error "CmdPal data directory not found: $CmdPalDataDir`nIs Command Palette installed?"
        exit 1
    }
    if (-not (Test-Path $SettingsDir)) {
        New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
    }

    $hasLocalOverrides = Test-Path $OverrideDir

    foreach ($file in $SyncFiles) {
        $srcPath = Join-Path $CmdPalDataDir $file
        if (Test-Path $srcPath) {
            Write-Host "  Exporting: $file"
            $content = [System.IO.File]::ReadAllText($srcPath, [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText((Join-Path $SettingsDir $file), $content, [System.Text.UTF8Encoding]::new($false))
            if ($hasLocalOverrides -and (Test-Path (Join-Path $OverrideDir $file))) {
                Write-Warning "  $file has local overrides in settings.d/ -- exported file may contain values that should stay in the local repo."
            }
        }
    }

    Write-Host "Export complete -> $SettingsDir"
    exit 0
}

# --- APPLY mode (default) ---
if (-not (Test-Path $SettingsDir)) {
    Write-Error "Settings directory not found: $SettingsDir"
    exit 1
}
if (-not (Test-Path $CmdPalDataDir)) {
    Write-Error "CmdPal data directory not found: $CmdPalDataDir`nIs Command Palette installed?"
    exit 1
}

# Build changes
$changes = @()

foreach ($file in $SyncFiles) {
    $templatePath = Join-Path $SettingsDir $file
    if (-not (Test-Path $templatePath)) { continue }

    $baseJson = Get-Content $templatePath -Raw -Encoding UTF8
    $merged = $baseJson | ConvertFrom-Json | ConvertTo-Hashtable

    $overrideFile = Join-Path $OverrideDir $file
    if (Test-Path $overrideFile) {
        $overrideJson = Get-Content $overrideFile -Raw -Encoding UTF8
        $override = $overrideJson | ConvertFrom-Json | ConvertTo-Hashtable
        $merged = Merge-Deep $merged $override
    }

    $resolvedJson = Resolve-Placeholders ($merged | ConvertTo-Json -Depth 50 -Compress)

    if (Test-UnresolvedPlaceholders $resolvedJson) {
        $vars = Get-UnresolvedVars $resolvedJson
        Write-Warning "Unresolved placeholders in $file`: $($vars -join ', '). Skipping."
    } else {
        $resolvedHt = $resolvedJson | ConvertFrom-Json | ConvertTo-Hashtable
        $diskPath = Join-Path $CmdPalDataDir $file
        $changes += @{ Label = $file; Data = $resolvedHt; DiskPath = $diskPath }
    }
}

if ($changes.Count -eq 0) {
    Write-Host "No settings to apply."
    exit 0
}

if ($DryRun) {
    foreach ($change in $changes) {
        Write-Host "`n=== $($change.Label) ===" -ForegroundColor Cyan
        Write-Host "  -> $($change.DiskPath)"
        $change.Data | ConvertTo-Json -Depth 50 | Write-Host
    }
    Write-Host "`n(Dry run - nothing applied)" -ForegroundColor Yellow
    exit 0
}

# Apply: stop, write, restart
Stop-CmdPal

foreach ($change in $changes) {
    Write-Host "  Writing $($change.Label)..."
    Write-SettingsFile -Declared $change.Data -DiskPath $change.DiskPath
}

Start-CmdPal
Write-Host "CmdPal settings applied."
