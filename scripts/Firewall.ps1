param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt')
)

$ErrorActionPreference = 'Stop'

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [Firewall] $Message" | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
}

try {
    Write-Log 'Отключение Windows Firewall для всех профилей'
    $process = Start-Process -FilePath 'netsh.exe' -ArgumentList 'advfirewall set allprofiles state off' -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "netsh завершился с кодом $($process.ExitCode)" }
    Write-Log 'Windows Firewall отключён успешно'
} catch {
    Write-Log "Ошибка: $($_.Exception.Message)"
    throw
}
