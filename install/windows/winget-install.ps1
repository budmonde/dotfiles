# Wrapper for winget install that treats "already up-to-date" as success.
# Usage: winget-install.ps1 <package-id>
# winget returns -1978335189 (APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE)
# when the package is already installed with no update available.
param([Parameter(Mandatory)][string]$PackageId)

winget install $PackageId --accept-source-agreements --accept-package-agreements
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { exit 1 }
