param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt')
)

$ErrorActionPreference = 'Stop'
$workingDir = Join-Path $RootPath 'MAS\Separate-Files-Version\Activators'
$activationScript = Join-Path $workingDir 'TSforge_Activation.cmd'

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [Windows Activation] $Message" | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $activationScript -PathType Leaf)) { throw "Не найден скрипт активации: $activationScript" }
    Write-Log 'Запуск скрипта активации Windows'
    $commandLine = '/d /c call "TSforge_Activation.cmd" /Z-Windows'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList $commandLine -WorkingDirectory $workingDir -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Скрипт активации завершился с кодом $($process.ExitCode)" }
    Write-Log 'Активация Windows завершена успешно'
} catch {
    Write-Log "Ошибка: $($_.Exception.Message)"
    throw
}
