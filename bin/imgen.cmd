@echo off
setlocal
set "IMGEN_SCRIPT=%~dp0imgen"
where py >nul 2>nul
if %ERRORLEVEL%==0 (
    py -3 "%IMGEN_SCRIPT%" %*
) else (
    python "%IMGEN_SCRIPT%" %*
)
exit /b %ERRORLEVEL%
