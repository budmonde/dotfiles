@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0notify-on-event.ps1" %*
