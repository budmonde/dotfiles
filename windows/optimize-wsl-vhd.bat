@echo off
setlocal

:: Optimizing WSL image disk size: https://github.com/microsoft/WSL/issues/4699

:: Shutdown WSL
echo Shutting down WSL...
wsl --shutdown

:: Get the WSL folder (first UUID folder in %LOCALAPPDATA%\wsl)
set "wslBase=%LOCALAPPDATA%\wsl"

:: Check if WSL folder exists
if not exist "%wslBase%" (
    echo ERROR: WSL folder not found at %wslBase%.
    pause
    exit /b
)

:: Find the first subfolder (UUID)
for /d %%D in ("%wslBase%\*") do (
    set "uuidFolder=%%D"
    goto FoundUUID
)

:FoundUUID
if not defined uuidFolder (
    echo ERROR: No WSL UUID folder found.
    pause
    exit /b
)

:: Compose the full VHD path
set "vhdFullPath=%uuidFolder%\ext4.vhdx"

:: Check if the VHD exists
if not exist "%vhdFullPath%" (
    echo ERROR: VHD file not found at %vhdFullPath%.
    pause
    exit /b
)

:: Show path and ask for confirmation
echo Found VHD file at: %vhdFullPath%
set /p confirm="Run Optimize-VHD on this file? (Y/N): "

if /I NOT "%confirm%"=="Y" (
    echo Operation cancelled.
    pause
    exit /b
)

powershell -ExecutionPolicy Bypass -Command "Optimize-VHD -Path '%vhdFullPath%' -Mode Full"

echo Done.
pause
