# Dotfiles Windows bootstrap - run on a fresh machine before cloning.
# Usage: irm https://raw.githubusercontent.com/budmonde/dotfiles/main/bootstrap.ps1 | iex

$ErrorActionPreference = "Stop"

# --- Execution policy --------------------------------------------------
# Fresh Windows defaults to Restricted, which blocks all .ps1 scripts.
# RemoteSigned allows local scripts while still requiring signatures on
# downloaded ones (install.ps1 is local after cloning).
if ((Get-ExecutionPolicy -Scope CurrentUser) -eq 'Restricted') {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "Set execution policy to RemoteSigned"
}

# --- WindowsApps PATH -------------------------------------------------
# Microsoft Store executables (winget, python) live here but the entry
# can be missing on fresh or corporate-imaged machines.
$windowsApps = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -split ';' -notcontains $windowsApps) {
    [Environment]::SetEnvironmentVariable('PATH', "$userPath;$windowsApps", 'User')
    $env:PATH += ";$windowsApps"
    Write-Host "Added WindowsApps to user PATH"
}

# --- Winget sources -----------------------------------------------------
# The msstore source is frequently broken on corporate machines and
# redundant with the winget community source. Remove it to avoid errors.
winget source remove msstore 2>$null

# --- Winget packages ---------------------------------------------------
# Git: /o:SSHOption=ExternalOpenSSH tells the installer to use the system
# OpenSSH (C:\Windows\System32\OpenSSH) instead of Git's bundled copy,
# so git talks to the Windows ssh-agent service where ssh-add stores keys.
Write-Host "Installing Git.Git..."
winget install --id Git.Git --accept-source-agreements --accept-package-agreements `
    --override '/VERYSILENT /NORESTART /o:SSHOption=ExternalOpenSSH'
Write-Host "Installing Python.Python.3.14..."
winget install --id Python.Python.3.14 --accept-source-agreements --accept-package-agreements

# Refresh PATH so the newly-installed binaries are visible.
$env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH', 'User')

# --- ssh-agent service -------------------------------------------------
if ((Get-Service ssh-agent).StartType -ne 'Automatic') {
    Set-Service ssh-agent -StartupType Automatic
}
Start-Service ssh-agent -ErrorAction SilentlyContinue

# --- Clone and install -------------------------------------------------
$defaultPath = "$HOME\.dotfiles"
$clonePath = Read-Host "Clone path [$defaultPath]"
if ([string]::IsNullOrWhiteSpace($clonePath)) { $clonePath = $defaultPath }

git clone https://github.com/budmonde/dotfiles.git $clonePath

# --- Switch remote to SSH ------------------------------------------------
# The clone above uses HTTPS (no auth needed for public repos). Once the
# user has added their SSH key to the agent + GitHub, we switch to SSH so
# pushes use the key.
Write-Host "`nSSH key setup required to switch remote to SSH."
Write-Host "If you haven't yet, run: ssh-keygen -t ed25519 -f ~/.ssh/git/github_ed25519"
Write-Host "Then add the public key to GitHub and run: ssh-add ~/.ssh/git/github_ed25519"
$switch = Read-Host "Switch remote to SSH now? [y/N]"
if ($switch -eq 'y') {
    git -C $clonePath remote set-url origin git@github.com:budmonde/dotfiles.git
    Write-Host "Remote switched to SSH"
}

Write-Host "`nBootstrap complete. Next steps:"
Write-Host "  1. cd $clonePath; .\install.ps1"
Write-Host "  2. Clone dotfiles-local"
