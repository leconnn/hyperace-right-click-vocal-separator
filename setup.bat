@echo off
rem Double-click this file to install HyperACE and add the right-click menu.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
