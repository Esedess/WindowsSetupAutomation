param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath
)

# Папка с инсталятором (должна называться так же как этот файл)
$dirName = "Notepad++"
$workingDir = Join-Path $RootPath $dirName
# Имя установочного файла
$installFile = "npp.8.7.8.Installer.x64.exe"
# Агрументы для тихой установки. Пример: "/arg1", "-arg2", "--arg3"
$Arguments = "/S", "/noUpdater"

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