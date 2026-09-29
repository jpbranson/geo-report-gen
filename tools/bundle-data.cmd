@echo off
rem Windows entry point for tools\bundle-data.ps1: runs it with the built-in Windows PowerShell,
rem allowing this one script to run whatever the script execution policy.
rem   .\tools\bundle-data.cmd [-NoReports] [-OutDir <folder>]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bundle-data.ps1" %*
exit /b %ERRORLEVEL%
