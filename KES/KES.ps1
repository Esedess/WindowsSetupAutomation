param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt')
)

$ErrorActionPreference = 'Stop'
$workingDir = Join-Path $RootPath 'KES\KES'
$installerPath = Join-Path $workingDir 'setup_kes.exe'
$activationCodePath = Join-Path $RootPath 'KES\ActivationCode.txt'

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [KES] $Message" | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw "Не найден установщик KES: $installerPath" }
    if (-not (Test-Path -LiteralPath $activationCodePath -PathType Leaf)) { throw "Не найден файл кода активации: $activationCodePath" }
    $activationCode = (Get-Content -LiteralPath $activationCodePath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($activationCode)) { throw 'Файл кода активации пуст.' }
    $arguments = @('/pEULA=1','/pPRIVACYPOLICY=1',"/pACTIVATIONCODE=$activationCode",'/pADDENVIRONMENT=1','/s')
    Write-Log 'Запуск тихой установки KES (код активации скрыт)'
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -WorkingDirectory $workingDir -PassThru -Wait
    if ($process.ExitCode -notin @(0,3010)) { throw "Установщик завершился с кодом $($process.ExitCode)" }
    Write-Log "Установка KES завершена успешно. Код: $($process.ExitCode)"
} catch {
    Write-Log "Ошибка: $($_.Exception.Message)"
    throw
}
