function Get-OpenCodeApplications {
    @(Get-Command opencode -All -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Path } |
        Group-Object Path |
        ForEach-Object { $_.Group[0] })
}

function Test-PublicOpenCodeInstallAllowed {
    foreach ($application in @(Get-OpenCodeApplications)) {
        $global:LASTEXITCODE = 0
        try {
            $versionOutput = (& $application.Path --version 2>$null | Out-String).Trim()
        } catch {
            Write-Host "Skipping public OpenCode install: version inspection failed for $($application.Path)."
            return $false
        }

        if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
            $displayVersion = if ($versionOutput) { $versionOutput } else { '<no version>' }
            Write-Host "Skipping public OpenCode install: preserving $($application.Path) ($displayVersion)."
            return $false
        }
    }

    return $true
}

function Install-PublicOpenCode {
    if (-not (Test-PublicOpenCodeInstallAllowed)) {
        return
    }

    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('PATH', 'User')

    $fnm = Get-Command fnm -ErrorAction SilentlyContinue
    if (-not $fnm) {
        throw 'fnm not found on PATH'
    }

    fnm env --shell powershell | Out-String | Invoke-Expression
    npm install -g opencode-ai
    if ($LASTEXITCODE -ne 0) {
        throw "npm failed to install public OpenCode (exit $LASTEXITCODE)"
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-PublicOpenCode
}
