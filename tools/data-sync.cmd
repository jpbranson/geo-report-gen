@echo off
rem Windows entry point for tools\data-sync.ps1: runs it with the built-in Windows PowerShell,
rem allowing this one script to run whatever the script execution policy.
rem   .\tools\data-sync.cmd [rclone bisync options, e.g. --dry-run]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0data-sync.ps1" %*
exit /b %ERRORLEVEL%
