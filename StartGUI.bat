@echo off
setlocal
powershell.exe -NoLogo -NonInteractive -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~dp0main.ps1" -ScriptRoot "%~dp0"
endlocal
