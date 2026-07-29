@echo off
if not defined CODEX_HOME (
  if defined XDG_CONFIG_HOME (
    set "CODEX_HOME=%XDG_CONFIG_HOME%\codex"
  ) else (
    set "CODEX_HOME=%USERPROFILE%\.config\codex"
  )
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CODEX_HOME%\app-server\codex-host.ps1" %*
