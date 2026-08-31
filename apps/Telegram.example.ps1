param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt')
)

# Папка с установщиком.
$dirName = 'Telegram'
$workingDir = Join-Path $RootPath $dirName

# Маска позволяет заменять установщик новой версией без изменения сценария.
$fileMask = 'tsetup*.exe'

$arguments = @('/DIR="C:\Program Files\Telegram Desktop"', '/VERYSILENT', '/NORESTART', '/MERGETASKS=!desktopicon')

function Write-Log {
    param($message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$dirName] $message" | Out-File $LogPath -Append -Encoding UTF8
}

try {

    Write-Log "Начало установки"

    $installer = Get-ChildItem -LiteralPath $workingDir -Filter $fileMask -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $installer) {
        Write-Log "Не найден установочный файл по маске '$fileMask' в папке $workingDir"
        throw "Не найден установочный файл для $dirName"
    }

    Write-Log "Параметры: $($installer.FullName) $($arguments -join ' ')"
    
    $process = Start-Process -FilePath $installer.FullName -ArgumentList $arguments -WorkingDirectory $workingDir -PassThru -Wait
    
    if ($process.ExitCode -eq 0) {
        Write-Log "Установка завершена успешно. Код: $($process.ExitCode)"
    } 
    else {
        throw "Ошибка установки. Код: $($process.ExitCode)"
    }
}
catch {
    Write-Log "Критическая ошибка: $_"
    throw
}

# Добавляем ярлык на общий рабочий стол
$desktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$desktopPath\Telegram.lnk")
$shortcut.TargetPath = "C:\Program Files\Telegram Desktop\Telegram.exe"
$shortcut.Save()
