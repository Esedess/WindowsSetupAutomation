@echo off
setlocal

rem Ждём полной загрузки пользовательской оболочки.
:WaitExplorer
tasklist /FI "IMAGENAME eq explorer.exe" 2>nul | find /I "explorer.exe" >nul
if errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto WaitExplorer
)

rem Даём Windows закончить фоновые действия после первого входа.
timeout /t 60 /nobreak >nul

rem Находим установочную флешку по метке и запускаем оболочку.
rem Замените метку и AppsInstall, если у вас используются другие значения.
powershell.exe -NoLogo -NonInteractive -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command "$volume = Get-Volume -FileSystemLabel 'Technows 11 Pro' -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1; if ($null -eq $volume) { exit 2 }; $launcher = '{0}:\AppsInstall\StartGUI.cmd' -f $volume.DriveLetter; if (-not (Test-Path -LiteralPath $launcher)) { exit 3 }; Start-Process -FilePath $launcher -WorkingDirectory (Split-Path -Parent $launcher)"

endlocal
exit /b
