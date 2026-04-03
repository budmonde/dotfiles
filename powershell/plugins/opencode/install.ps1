# Refresh PATH and activate fnm so npm is available
$env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('PATH', 'User')
fnm env --shell powershell | Out-String | Invoke-Expression

npm install -g opencode-ai
