@echo off
setlocal
set "REDDIT_SCRIPT=%~dp0reddit"
where py >nul 2>nul
if %ERRORLEVEL%==0 (
    py -3 "%REDDIT_SCRIPT%" %*
) else (
    python "%REDDIT_SCRIPT%" %*
)
exit /b %ERRORLEVEL%
