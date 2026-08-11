@echo off
setlocal
set "GFR_SCRIPT=%~dp0git-filter-repo"
where py >nul 2>nul
if %ERRORLEVEL%==0 (
    py -3 "%GFR_SCRIPT%" %*
) else (
    python "%GFR_SCRIPT%" %*
)
exit /b %ERRORLEVEL%
