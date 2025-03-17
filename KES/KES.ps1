param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath
)

$workingDir = Join-Path $RootPath "KES\KES"
$installFile = "setup_kes.exe"

$ACTIVATIONCODE = Get-Content "$workingDir\ActivationCode.txt" -Raw

$Arguments = "/pEULA=1", "/pPRIVACYPOLICY=1", "/pACTIVATIONCODE=$ACTIVATIONCODE", "/pADDENVIRONMENT=1", "/s"

function Write-Log {
    param($message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [KES] $message" | Out-File $LogPath -Append -Encoding UTF8
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