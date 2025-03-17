param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath
)

# Папка с инсталятором (должна называться так же как этот файл)
$dirName = "Telegram"
$workingDir = Join-Path $RootPath $dirName
# Имя установочного файла
$installFile = "tsetup.5.11.1.exe"
# Агрументы для тихой установки. Пример: "/arg1", "-arg2", "--arg3"
$Arguments = "/DIR=`"C:\Program Files\Telegram Desktop`"", "/VERYSILENT", "/NORESTART", "/MERGETASKS=!desktopicon"

function Write-Log {
    param($message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$dirName] $message" | Out-File $LogPath -Append -Encoding UTF8
}

try {

    Write-Log "Начало установки"
    Write-Log "Параметры: $workingDir\$installFile $Arguments"
    
    $process = Start-Process "$workingDir\$installFile" -ArgumentList $Arguments -Verb RunAs -PassThru -Wait
    
    if ($process.ExitCode -eq 0) {
        Write-Log "Установка завершена успешно. Код: $($process.ExitCode)"
    } 
    else {
        throw "Ошибка установки. Код: $($process.ExitCode)"
    }
}
catch {
    Write-Log "Критическая ошибка: $_"
    throw  # Пробрасываем исключение дальше для основного скрипта
}

# Добавляем ярлык на общий рабочий стол
$desktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$desktopPath\Telegram.lnk")
$shortcut.TargetPath = "C:\Program Files\Telegram Desktop\Telegram.exe"
$shortcut.Save()