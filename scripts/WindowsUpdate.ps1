param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt')
)

$ErrorActionPreference = 'Stop'
$sourceDir = Join-Path $RootPath 'Windows-Update-Blocker-main'
$targetDir = Join-Path $env:ProgramData 'WindowsUpdateBlocker'
$exeName = if ([Environment]::Is64BitOperatingSystem) { 'Wub_x64.exe' } else { 'Wub.exe' }

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [Windows Update Blocker] $Message" | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
}

try {
    foreach ($name in @($exeName,'Wub.ini')) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $name) -PathType Leaf)) { throw "Не найден файл Windows Update Blocker: $name" }
    }
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) { [void](New-Item -ItemType Directory -Path $targetDir -Force) }
    Copy-Item -LiteralPath (Join-Path $sourceDir $exeName) -Destination (Join-Path $targetDir $exeName) -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'Wub.ini') -Destination (Join-Path $targetDir 'Wub.ini') -Force
    $wubPath = Join-Path $targetDir $exeName
    Write-Log 'Отключение Windows Update и защита настроек служб'
    $process = Start-Process -FilePath $wubPath -ArgumentList '/D /P' -WorkingDirectory $targetDir -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Windows Update Blocker завершился с кодом $($process.ExitCode)" }

    Write-Log "Windows Update отключён; файлы управления сохранены в $targetDir"
} catch {
    Write-Log "Ошибка: $($_.Exception.Message)"
    throw
}
