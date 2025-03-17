param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath
)

# Папка с инсталятором (должна называться так же как этот файл)
$dirName = "7-Zip"
$workingDir = Join-Path $RootPath $dirName
# Имя установочного файла
$installFile = "7z2409-x64.exe"
# Агрументы для тихой установки. Пример: "/arg1", "-arg2", "--arg3"
$Arguments = "/S"


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



# ------------------------------------------------

# # Папка с инсталятором (должна называться так же как этот файл)
# $workingDir = Join-Path $RootPath "7-Zip"
# # Имя установочного файла
# $installFile = "7z2409-x64.exe"
# # Агрументы для тихой установки. Пример: "/arg1", "-arg2", "--arg3"
# $Arguments = "/S"

# Start-Process "$workingDir\$installFile" -ArgumentList $Arguments -Verb RunAs -Wait

# -------------------------------------------------

