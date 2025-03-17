param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath
)

# Папка с инсталятором (должна называться так же как этот файл)
$dirName = "Chrome"
$workingDir = Join-Path $RootPath $dirName
# Имя установочного файла
$installFile = "googlechromestandaloneenterprise64.msi"
# Агрументы для тихой установки. Пример: "/arg1", "-arg2", "--arg3"
$Arguments = "/qn"

function Write-Log {
    param($message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$dirName] $message" | Out-File $LogPath -Append -Encoding UTF8
}

try {

    Write-Log "Начало установки"
    Write-Log "Параметры: $workingDir\$installFile $Arguments"
    
    $process = Start-Process MsiExec.exe -Argument "/i `"$workingDir\$installFile`" $Arguments" -Verb RunAs -PassThru -Wait
    
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