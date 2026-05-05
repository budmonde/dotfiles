<#
.SYNOPSIS
    Sync PowerToys settings via PowerToys.DSC.exe.

.DESCRIPTION
    Applies declared PowerToys configuration from template files, supporting
    environment variable placeholders and a common/local override merge strategy.

    Config is discovered from $env:XDG_CONFIG_HOME/powertoys/ (falls back to
    ~/.config/powertoys/).

.PARAMETER DryRun
    Preview resolved JSON without applying.

.PARAMETER Export
    Capture live PowerToys state into the settings/ template files.

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

# --- Locate PowerToys.DSC.exe ---
$DscExe = Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.DSC.exe'
if (-not (Test-Path $DscExe)) {
    $DscExe = 'C:\Program Files\PowerToys\PowerToys.DSC.exe'
}
if (-not (Test-Path $DscExe)) {
    Write-Error "PowerToys.DSC.exe not found. Is PowerToys installed?"
    exit 1
}

# --- Locate config directory ---
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

# --- Helper: Invoke DSC set (uses cmd /c for reliable argument passing) ---
function Invoke-DscSet {
    param(
        [string]$Json,
        [string]$Module
    )
    $escaped = $Json -replace '"', '\"'
    if ($Module) {
        $args_ = "set --resource settings --module `"$Module`" --input `"$escaped`""
    } else {
        $args_ = "set --resource settings --input `"$escaped`""
    }
    $output = cmd /c "`"$DscExe`" $args_" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "DSC set failed$(if ($Module) { " for module $Module" }): $output"
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

    Write-Host "Exporting top-level settings..."
    $topLevel = & $DscExe export --resource settings 2>&1
    $topLevel | Set-Content (Join-Path $SettingsDir 'settings.json') -Encoding UTF8
    if ($hasLocalTopLevel) {
        Write-Warning "settings.json has local overrides in settings.d/ -- exported file may contain values that should stay in the local repo."
    }

    $moduleList = & $DscExe modules --resource settings 2>&1
    foreach ($mod in $moduleList) {
        $mod = $mod.Trim()
        if (-not $mod) { continue }
        Write-Host "  Exporting module: $mod"
        $modJson = & $DscExe export --resource settings --module $mod 2>&1
        $modJson | Set-Content (Join-Path $modulesDir "$mod.json") -Encoding UTF8
        if ($mod -in $localModules) {
            Write-Warning "  $mod has local overrides in settings.d/ -- exported file may contain secrets or values that should stay in the local repo."
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

# Apply top-level settings
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
        if ($DryRun) {
            Write-Host "`n=== Top-level settings ===" -ForegroundColor Cyan
            $resolvedJson | ConvertFrom-Json | ConvertTo-Json -Depth 50 | Write-Host
        } else {
            Write-Host "Applying top-level settings..."
            Invoke-DscSet -Json $resolvedJson
        }
    }
}

# Apply per-module settings
$modulesDir = Join-Path $SettingsDir 'modules'
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
            if ($DryRun) {
                Write-Host "`n=== Module: $moduleName ===" -ForegroundColor Cyan
                $resolvedJson | ConvertFrom-Json | ConvertTo-Json -Depth 50 | Write-Host
            } else {
                Write-Host "  Applying module: $moduleName"
                Invoke-DscSet -Json $resolvedJson -Module $moduleName
            }
        }
    }
}

if ($DryRun) {
    Write-Host "`n(Dry run - nothing applied)" -ForegroundColor Yellow
} else {
    Write-Host "PowerToys settings applied."
}
