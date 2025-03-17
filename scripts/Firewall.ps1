param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath
)

function Write-Log {
    param($message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [Firewall] $message" | Out-File $LogPath -Append -Encoding UTF8
}

try {

    Write-Log "Отключаем firewall"
    
    $process = Start-Process "netsh" -ArgumentList "advfirewall set allprofiles state off" -Verb RunAs -PassThru -Wait
    
    if ($process.ExitCode -eq 0) {
        Write-Log "Firewall отключен успешно. Код: $($process.ExitCode)"
    } 
    else {
        throw "Ошибка отключения firewall. Код: $($process.ExitCode)"
    }
}
catch {
    Write-Log "Критическая ошибка: $_"
    throw  # Пробрасываем исключение дальше для основного скрипта
}
