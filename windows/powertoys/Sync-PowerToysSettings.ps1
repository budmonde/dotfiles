<#
.SYNOPSIS
    Sync PowerToys settings by writing directly to disk.

.DESCRIPTION
    Applies declared PowerToys configuration from template files, supporting
    environment variable placeholders and a common/local override merge strategy.

    Strategy: stop PowerToys, write settings to disk, restart PowerToys.

    Config is discovered from $env:XDG_CONFIG_HOME/powertoys/ (falls back to
    ~/.config/powertoys/).

.PARAMETER DryRun
    Preview resolved JSON without applying.

.PARAMETER Export
    Capture live PowerToys disk state into the settings/ template files.

.EXAMPLE
    Sync-PowerToysSettings              # apply declared config
    Sync-PowerToysSettings -DryRun      # preview what would be applied
    Sync-PowerToysSettings -Export      # export live state to template files
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Export
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- ZoomIt registry path ---
$ZoomItRegPath = 'HKCU:\Software\Sysinternals\ZoomIt'

# --- Helper: Encode Font object to LOGFONT binary ---
function ConvertTo-LogFontBytes {
    param([System.Collections.IDictionary]$Font)
    $bytes = [byte[]]::new(92)
    [Array]::Copy([BitConverter]::GetBytes([int]$Font['lfHeight']), 0, $bytes, 0, 4)
    [Array]::Copy([BitConverter]::GetBytes([int]$Font['lfWidth']), 0, $bytes, 4, 4)
    # lfEscapement(8), lfOrientation(12) left as 0
    [Array]::Copy([BitConverter]::GetBytes([int]$Font['lfWeight']), 0, $bytes, 16, 4)
    $bytes[20] = [byte]$Font['lfItalic']
    # lfUnderline(21), lfStrikeOut(22), lfCharSet(23), lfOutPrecision(24),
    # lfClipPrecision(25), lfQuality(26), lfPitchAndFamily(27) left as 0
    $faceBytes = [System.Text.Encoding]::Unicode.GetBytes($Font['lfFaceName'])
    [Array]::Copy($faceBytes, 0, $bytes, 28, [Math]::Min($faceBytes.Length, 62))
    return $bytes
}

# --- Helper: Decode LOGFONT binary to Font object ---
function ConvertFrom-LogFontBytes {
    param([byte[]]$Bytes)
    return [ordered]@{
        lfHeight   = [BitConverter]::ToInt32($Bytes, 0)
        lfWidth    = [BitConverter]::ToInt32($Bytes, 4)
        lfWeight   = [BitConverter]::ToInt32($Bytes, 16)
        lfItalic   = [int]$Bytes[20]
        lfFaceName = [System.Text.Encoding]::Unicode.GetString($Bytes, 28, $Bytes.Length - 28).TrimEnd([char]0)
    }
}

# --- Helper: Write ZoomIt settings to registry ---
function Write-ZoomItRegistry {
    param([System.Collections.IDictionary]$Declared)

    if (-not (Test-Path $ZoomItRegPath)) {
        New-Item -Path $ZoomItRegPath -Force | Out-Null
    }

    foreach ($key in $Declared.Keys) {
        $value = $Declared[$key]
        if ($key -eq 'Font') {
            $fontBytes = ConvertTo-LogFontBytes $value
            Set-ItemProperty -Path $ZoomItRegPath -Name $key -Value $fontBytes -Type Binary
        } elseif ($value -is [string]) {
            Set-ItemProperty -Path $ZoomItRegPath -Name $key -Value $value -Type String
        } else {
            Set-ItemProperty -Path $ZoomItRegPath -Name $key -Value ([int]$value) -Type DWord
        }
    }
}

# --- Helper: Read ZoomIt settings from registry ---
function Read-ZoomItRegistry {
    if (-not (Test-Path $ZoomItRegPath)) { return $null }
    $props = Get-ItemProperty -Path $ZoomItRegPath
    $reg = [ordered]@{}
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        if ($p.Name -eq 'Font') {
            $reg['Font'] = ConvertFrom-LogFontBytes $p.Value
        } else {
            $reg[$p.Name] = $p.Value
        }
    }
    return $reg
}

# --- Paths ---
$PowerToysExe = 'C:\Program Files\PowerToys\PowerToys.exe'
$PowerToysDiskDir = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'

$ConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
$PtConfig = Join-Path $ConfigHome 'powertoys'

if (-not (Test-Path $PtConfig)) {
    Write-Error "Config directory not found: $PtConfig"
    exit 1
}

$SettingsDir = Join-Path $PtConfig 'settings'
$OverrideDir = Join-Path $PtConfig 'settings.d'

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

    # Read existing on-disk file if present
    if (Test-Path $DiskPath) {
        $diskContent = [System.IO.File]::ReadAllText($DiskPath, [System.Text.Encoding]::UTF8)
        $diskObj = $diskContent | ConvertFrom-Json | ConvertTo-Hashtable
    } else {
        $diskObj = [ordered]@{}
        $dir = Split-Path $DiskPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    # Deep-merge declared into existing (declared wins)
    $merged = Merge-Deep $diskObj $Declared

    # Write via temp file to avoid partial writes
    $jsonOut = $merged | ConvertTo-Json -Depth 50
    $tempPath = "$DiskPath.tmp"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tempPath, $jsonOut, $utf8NoBom)
    Move-Item -Path $tempPath -Destination $DiskPath -Force
}

# --- Helper: Stop PowerToys ---
function Stop-PowerToys {
    $procs = Get-Process -Name 'PowerToys*' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Stopping PowerToys..."
        $procs | Stop-Process -Force
        # Wait for processes to exit
        $timeout = [datetime]::Now.AddSeconds(10)
        while ((Get-Process -Name 'PowerToys*' -ErrorAction SilentlyContinue) -and [datetime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 200
        }
    }
}

# --- Helper: Start PowerToys ---
function Start-PowerToys {
    if (Test-Path $PowerToysExe) {
        Write-Host "Starting PowerToys..."
        Start-Process -FilePath $PowerToysExe
    } else {
        Write-Warning "PowerToys.exe not found at $PowerToysExe -- please start manually."
    }
}

# --- EXPORT mode ---
if ($Export) {
    if (-not (Test-Path $SettingsDir)) {
        New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
    }
    $modulesDir = Join-Path $SettingsDir 'modules'
    if (-not (Test-Path $modulesDir)) {
        New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
    }

    # Collect local override file names to warn about
    $localModules = @()
    $overrideModulesDir = Join-Path $OverrideDir 'modules'
    if (Test-Path $overrideModulesDir) {
        $localModules = Get-ChildItem $overrideModulesDir -Filter '*.json' | ForEach-Object { $_.BaseName }
    }
    $hasLocalTopLevel = Test-Path (Join-Path $OverrideDir 'settings.json')

    # Export top-level settings (on-disk format, no wrapper)
    $topLevelPath = Join-Path $PowerToysDiskDir 'settings.json'
    if (Test-Path $topLevelPath) {
        Write-Host "Exporting top-level settings..."
        $content = [System.IO.File]::ReadAllText($topLevelPath, [System.Text.Encoding]::UTF8)
        $content | Set-Content (Join-Path $SettingsDir 'settings.json') -Encoding UTF8 -NoNewline
        if ($hasLocalTopLevel) {
            Write-Warning "settings.json has local overrides in settings.d/ -- exported file may contain values that should stay in the local repo."
        }
    }

    # Export per-module settings (scan on-disk module directories)
    $moduleDirs = Get-ChildItem $PowerToysDiskDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'settings.json')
    }
    foreach ($dir in $moduleDirs) {
        $modName = $dir.Name
        $modSettingsPath = Join-Path $dir.FullName 'settings.json'
        Write-Host "  Exporting module: $modName"
        $content = [System.IO.File]::ReadAllText($modSettingsPath, [System.Text.Encoding]::UTF8)
        $content | Set-Content (Join-Path $modulesDir "$modName.json") -Encoding UTF8 -NoNewline
        if ($modName -in $localModules) {
            Write-Warning "  $modName has local overrides in settings.d/ -- exported file may contain secrets or values that should stay in the local repo."
        }
    }

    # Export ZoomIt settings from registry
    $zoomItReg = Read-ZoomItRegistry
    if ($zoomItReg) {
        Write-Host "  Exporting module: ZoomIt (registry)"
        # Strip volatile keys not worth versioning
        $skipKeys = @('EulaAccepted', 'OptionsShown', 'TrimDialogWidth', 'TrimDialogHeight',
                      'TrimDialogVolume', 'RecordingSaveLocation', 'ScreenshotSaveLocation')
        foreach ($k in $skipKeys) { $zoomItReg.Remove($k) }
        $zoomItJson = $zoomItReg | ConvertTo-Json -Depth 5
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText((Join-Path $modulesDir 'ZoomIt.json'), $zoomItJson, $utf8NoBom)
        if ('ZoomIt' -in $localModules) {
            Write-Warning "  ZoomIt has local overrides in settings.d/ -- exported file may contain values that should stay in the local repo."
        }
    }

    Write-Host "Export complete -> $SettingsDir"
    if ($localModules.Count -gt 0 -or $hasLocalTopLevel) {
        Write-Host ""
        Write-Warning "Review exported files for any secrets or local-only values before committing."
    }
    exit 0
}

# --- APPLY mode (default) ---
if (-not (Test-Path $SettingsDir)) {
    Write-Error "Settings directory not found: $SettingsDir"
    exit 1
}

# Build the set of changes first, then stop/write/start
$changes = @()

# Resolve top-level settings
$settingsFile = Join-Path $SettingsDir 'settings.json'
if (Test-Path $settingsFile) {
    $baseJson = Get-Content $settingsFile -Raw -Encoding UTF8
    $merged = $baseJson | ConvertFrom-Json | ConvertTo-Hashtable

    $overrideFile = Join-Path $OverrideDir 'settings.json'
    if (Test-Path $overrideFile) {
        $overrideJson = Get-Content $overrideFile -Raw -Encoding UTF8
        $override = $overrideJson | ConvertFrom-Json | ConvertTo-Hashtable
        $merged = Merge-Deep $merged $override
    }

    $resolvedJson = Resolve-Placeholders ($merged | ConvertTo-Json -Depth 50 -Compress)

    if (Test-UnresolvedPlaceholders $resolvedJson) {
        $vars = Get-UnresolvedVars $resolvedJson
        Write-Warning "Unresolved placeholders in settings.json: $($vars -join ', '). Skipping."
    } else {
        $resolvedHt = $resolvedJson | ConvertFrom-Json | ConvertTo-Hashtable
        $diskPath = Join-Path $PowerToysDiskDir 'settings.json'
        $changes += @{ Label = "top-level settings"; Data = $resolvedHt; DiskPath = $diskPath }
    }
}

# Resolve per-module settings
$modulesDir = Join-Path $SettingsDir 'modules'
$zoomItChange = $null
if (Test-Path $modulesDir) {
    foreach ($file in Get-ChildItem $modulesDir -Filter '*.json') {
        $moduleName = $file.BaseName
        $baseJson = Get-Content $file.FullName -Raw -Encoding UTF8
        $merged = $baseJson | ConvertFrom-Json | ConvertTo-Hashtable

        $overrideFile = Join-Path $OverrideDir "modules\$($file.Name)"
        if (Test-Path $overrideFile) {
            $overrideJson = Get-Content $overrideFile -Raw -Encoding UTF8
            $override = $overrideJson | ConvertFrom-Json | ConvertTo-Hashtable
            $merged = Merge-Deep $merged $override
        }

        $resolvedJson = Resolve-Placeholders ($merged | ConvertTo-Json -Depth 50 -Compress)

        if (Test-UnresolvedPlaceholders $resolvedJson) {
            $vars = Get-UnresolvedVars $resolvedJson
            Write-Warning "Unresolved placeholders in $($file.Name): $($vars -join ', '). Skipping module."
        } else {
            $resolvedHt = $resolvedJson | ConvertFrom-Json | ConvertTo-Hashtable
            if ($moduleName -eq 'ZoomIt') {
                # ZoomIt uses registry, not disk
                $zoomItChange = @{ Label = "module: ZoomIt (registry)"; Data = $resolvedHt }
            } else {
                $diskPath = Join-Path $PowerToysDiskDir "$moduleName\settings.json"
                $changes += @{ Label = "module: $moduleName"; Data = $resolvedHt; DiskPath = $diskPath }
            }
        }
    }
}

if ($changes.Count -eq 0 -and -not $zoomItChange) {
    Write-Host "No settings to apply."
    exit 0
}

# DryRun: just show what would be written
if ($DryRun) {
    foreach ($change in $changes) {
        Write-Host "`n=== $($change.Label) ===" -ForegroundColor Cyan
        Write-Host "  -> $($change.DiskPath)"
        $change.Data | ConvertTo-Json -Depth 50 | Write-Host
    }
    if ($zoomItChange) {
        Write-Host "`n=== $($zoomItChange.Label) ===" -ForegroundColor Cyan
        Write-Host "  -> $ZoomItRegPath"
        $zoomItChange.Data | ConvertTo-Json -Depth 50 | Write-Host
    }
    Write-Host "`n(Dry run - nothing applied)" -ForegroundColor Yellow
    exit 0
}

# Apply: stop, write, start
Stop-PowerToys

foreach ($change in $changes) {
    Write-Host "  Writing $($change.Label)..."
    Write-SettingsFile -Declared $change.Data -DiskPath $change.DiskPath
}

if ($zoomItChange) {
    Write-Host "  Writing $($zoomItChange.Label)..."
    Write-ZoomItRegistry -Declared $zoomItChange.Data
}

Start-PowerToys
Write-Host "PowerToys settings applied."
