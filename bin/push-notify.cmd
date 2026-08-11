@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0push-notify.ps1" %*
