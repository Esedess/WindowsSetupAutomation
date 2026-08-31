param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt')
)

$ErrorActionPreference = 'Stop'
$workingDirectory = Join-Path $RootPath 'ExampleApp'
$fileMask = 'setup*.exe'
$arguments = @('/S')

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [ExampleApp] $Message" |
        Out-File -LiteralPath $LogPath -Append -Encoding UTF8
}

try {
    $installer = Get-ChildItem -LiteralPath $workingDirectory -Filter $fileMask -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $installer) { throw "Не найден $fileMask в $workingDirectory" }

    Write-Log "Запуск: $($installer.Name)"
    $process = Start-Process -FilePath $installer.FullName -ArgumentList $arguments `
        -WorkingDirectory $workingDirectory -PassThru -Wait
    if ($process.ExitCode -notin @(0, 1641, 3010)) {
        throw "Установщик завершился с кодом $($process.ExitCode)"
    }
    Write-Log "Успешно. Код: $($process.ExitCode)"
} catch {
    Write-Log "Ошибка: $($_.Exception.Message)"
    throw
}
