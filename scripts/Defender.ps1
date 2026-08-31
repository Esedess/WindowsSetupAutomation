param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt')
)

$ErrorActionPreference = 'Stop'
$workingDir = Join-Path $RootPath 'windows-defender-remover'
$removerPath = Join-Path $workingDir 'removeantivirus.bat'

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [Defender Remover] $Message" | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $removerPath -PathType Leaf)) { throw "Не найден Defender Remover: $removerPath" }
    Write-Log 'Запуск удаления Microsoft Defender без автоматической перезагрузки'
    $commandLine = "/d /c call `"$removerPath`""
    $process = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList $commandLine -WorkingDirectory $workingDir -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Сценарий удаления Defender завершился с кодом $($process.ExitCode)" }
    Write-Log 'Удаление Microsoft Defender завершено успешно'
} catch {
    Write-Log "Ошибка: $($_.Exception.Message)"
    throw
}
