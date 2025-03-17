param(
    [string]$RootPath = $PSScriptRoot,
    [string]$LogPath = "$env:USERPROFILE\Desktop\InstallLog.txt"
)

$workingDir = Join-Path $RootPath "MAS\Separate-Files-Version\Activators"

function Write-Log {
    param($message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [Windows Activation] $message" | Out-File $LogPath -Append -Encoding UTF8
}

try {
    Write-Log "Запуск скрипта активации Office"
    $process = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/c "TSforge_Activation.cmd /Z-Office"' -WorkingDirectory "$workingDir" -Verb RunAs -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        $StdError = $process.StandardError.ReadToEnd()
        throw "Ошибка активации. Код: $StdError"
    }
    Write-Log "Скрипт активации Office завершил работу"
}
catch {
    Write-Log "Ошибка скрипта активации Office: $StdError"
    throw
}



# param([string]$RootPath = $PSScriptRoot)

# $workingDir = Join-Path $RootPath "MAS\Separate-Files-Version\Activators"

# Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/c "TSforge_Activation.cmd /Z-Office"' -WorkingDirectory "$workingDir" -Verb RunAs -Wait