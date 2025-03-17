param([string]$ScriptRoot = $PSScriptRoot)

# Требуем запуск от администратора
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $PSScriptRoot
    Start-Process powershell.exe -ArgumentList "-nologo -noninteractive -windowStyle hidden -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ScriptRoot `"$scriptPath`"" -Verb RunAs
    exit
}

$version = "0.8.9"

# Устанавливаем рабочую директорию
Set-Location $ScriptRoot

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Пути
$configPath = Join-Path $ScriptRoot "installer_config.json"
$appsPath = Join-Path $ScriptRoot "apps"
$scriptsPath = Join-Path $ScriptRoot "scripts"
$logPath = "$env:USERPROFILE\Desktop\InstallLog.txt"

# Логирование
function Write-Log {
    param($Message, $Source = (Get-PSCallStack)[1].Command)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$Source] $Message" | Out-File $logPath -Append -Encoding UTF8
}

# Чтение конфигурации
try {
	if (-not (Test-Path $configPath)) {
		throw
	}
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} catch {
    [System.Windows.Forms.MessageBox]::Show("Конфигурационный файл не найден или поврежден! Используются настройки по умолчанию.", "Предупреждение", "OK", "Warning")
    $config = [PSCustomObject]@{
        Programs = @(
			"Adobe Acrobat Reader DC",
			"AnyDesk",
			"Chrome",
			"Firefox",
			"Office2019",
			"Opera",
			"PDF-XChange",
			"Telegram",
			"VLC",
			"WhatsApp",
			"WinRAR",
			"XnView",
			"YandexGOST"
		)
        Activation = [PSCustomObject]@{
            Windows = $true
            Office = $true
        }
        KES = $true
        MaxUAC = $true
        DisableFirewall = $true
    }
    Write-Log "Конфигурация не загружена, используются настройки по умолчанию" -Source "ConfigLoad"
}

# Функция установки программ
function Install-Programs {
    param($Scripts, $ProgressData)
    foreach ($script in $Scripts) {
        $ProgressData.Form.Controls["statusLabel"].Text = "Устанавливается: $($script.BaseName) ($($ProgressData.CurrentStep.Value + 1) из $($ProgressData.TotalSteps))"
        $ProgressData.Form.Refresh()
        try {
            $fullPath = $script.FullName
            Start-Process powershell.exe "-nologo -noninteractive -windowStyle hidden -NoProfile -ExecutionPolicy Bypass -File `"$fullPath`" -RootPath `"$appsPath`" -LogPath `"$logPath`"" -Wait
            Write-Log "Успешно установлено: $($script.BaseName)" -Source "Install-Programs"
        } catch {
            Write-Log "Ошибка установки $($script.BaseName): $_" -Source "Install-Programs"
        }
        $ProgressData.CurrentStep.Value++
        $ProgressData.ProgressBar.Value = [math]::Round(($ProgressData.CurrentStep.Value / $ProgressData.TotalSteps) * 100)
    }
}

# Функция активации
function Invoke-Activation {
    param($ActivateWindows, $ActivateOffice, $ProgressData)
    if ($ActivateWindows) {
        $ProgressData.Form.Controls["statusLabel"].Text = "Активация Windows..."
        $ProgressData.Form.Refresh()
        try {
            $scriptPath = Join-Path $ScriptRoot "MAS\MAS_WINDOWS.ps1"
            & $scriptPath -RootPath $ScriptRoot -LogPath $logPath
            Write-Log "Активация Windows выполнена" -Source "Invoke-Activation"
        } catch {
            Write-Log "Ошибка активации Windows: $_" -Source "Invoke-Activation"
        }
        $ProgressData.CurrentStep.Value++
        $ProgressData.ProgressBar.Value = [math]::Round(($ProgressData.CurrentStep.Value / $ProgressData.TotalSteps) * 100)
    }
    if ($ActivateOffice) {
        $ProgressData.Form.Controls["statusLabel"].Text = "Активация Office..."
        $ProgressData.Form.Refresh()
        try {
            $scriptPath = Join-Path $ScriptRoot "MAS\MAS_OFFICE.ps1"
            & $scriptPath -RootPath $ScriptRoot -LogPath $logPath
            Write-Log "Активация Office выполнена" -Source "Invoke-Activation"
        } catch {
            Write-Log "Ошибка активации Office: $_" -Source "Invoke-Activation"
        }
        $ProgressData.CurrentStep.Value++
        $ProgressData.ProgressBar.Value = [math]::Round(($ProgressData.CurrentStep.Value / $ProgressData.TotalSteps) * 100)
    }
}

# Функция установки KES
function Install-KES {
    param($ProgressData)
    $ProgressData.Form.Controls["statusLabel"].Text = "Установка KES..."
    $ProgressData.Form.Refresh()
    try {
        $kesScript = Join-Path $ScriptRoot "KES\kes.ps1"
        Start-Process powershell.exe "-nologo -noninteractive -windowStyle hidden -NoProfile -ExecutionPolicy Bypass -File `"$kesScript`" -RootPath `"$ScriptRoot`" -LogPath `"$logPath`"" -Wait
        Write-Log "KES установлен успешно" -Source "Install-KES"
    } catch {
        Write-Log "Ошибка установки KES: $_" -Source "Install-KES"
    }
    $ProgressData.CurrentStep.Value++
    $ProgressData.ProgressBar.Value = [math]::Round(($ProgressData.CurrentStep.Value / $ProgressData.TotalSteps) * 100)
}

# Функция дополнительных скриптов
function Install-Scripts {
    param($MaxUAC, $Firewall, $ProgressData)
    if ($MaxUAC) {
        $ProgressData.Form.Controls["statusLabel"].Text = "Установка UAC на максимум..."
        $ProgressData.Form.Refresh()
        try {
            $maxUACScript = Join-Path $scriptsPath "UAC.ps1"
            Start-Process powershell.exe "-nologo -noninteractive -windowStyle hidden -NoProfile -ExecutionPolicy Bypass -File `"$maxUACScript`" -LogPath `"$logPath`"" -Verb RunAs -Wait
            Write-Log "UAC установлен на максимум" -Source "Install-Scripts"
        } catch {
            Write-Log "Ошибка установки UAC: $_" -Source "Install-Scripts"
        }
        $ProgressData.CurrentStep.Value++
        $ProgressData.ProgressBar.Value = [math]::Round(($ProgressData.CurrentStep.Value / $ProgressData.TotalSteps) * 100)
    }
    if ($Firewall) {
        $ProgressData.Form.Controls["statusLabel"].Text = "Отключение Firewall..."
        $ProgressData.Form.Refresh()
        try {
            $FirewallScript = Join-Path $scriptsPath "Firewall.ps1"
            Start-Process powershell.exe "-nologo -noninteractive -windowStyle hidden -NoProfile -ExecutionPolicy Bypass -File `"$FirewallScript`" -LogPath `"$logPath`"" -Verb RunAs -Wait
            Write-Log "Firewall отключен" -Source "Install-Scripts"
        } catch {
            Write-Log "Ошибка отключения Firewall: $_" -Source "Install-Scripts"
        }
        $ProgressData.CurrentStep.Value++
        $ProgressData.ProgressBar.Value = [math]::Round(($ProgressData.CurrentStep.Value / $ProgressData.TotalSteps) * 100)
    }
}

# Основная форма
$form = New-Object System.Windows.Forms.Form
$form.Text = "Установка программ $version"
$form.Size = New-Object System.Drawing.Size(950, 500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Панель с чекбоксами
$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(10, 10)
$panel.Size = New-Object System.Drawing.Size(500, 350)
$panel.BorderStyle = "FixedSingle"
$panel.AutoScroll = $true
$panel.HorizontalScroll.Enabled = $false
$panel.HorizontalScroll.Visible = $false
$form.Controls.Add($panel)

# Получение скриптов установки
$installScripts = Get-ChildItem -Path $appsPath -Filter *.ps1 -File | Where-Object { Test-Path (Join-Path $appsPath $_.BaseName) }

# Создание чекбоксов
$y = 10
foreach ($script in $installScripts) {
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Text = $script.BaseName
    $checkbox.Tag = $script
    $checkbox.Location = New-Object System.Drawing.Point(10, $y)
    $checkbox.Size = New-Object System.Drawing.Size(440, 20)
    $checkbox.Checked = $config.Programs -contains $script.BaseName
    $panel.Controls.Add($checkbox)
    $y += 30
}

# Кнопка выбора/снятия
$btnToggle = New-Object System.Windows.Forms.Button
$btnToggle.Text = "Снять все"
$btnToggle.Location = New-Object System.Drawing.Point(320, 365)  # Рядом с таймером
$btnToggle.Size = New-Object System.Drawing.Size(100, 30)
$btnToggle.FlatStyle = "Flat"
$btnToggle.Add_Click({
    $allChecked = ($panel.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] -and $_.Checked }).Count -eq 0
    foreach ($control in $panel.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox]) {
            $control.Checked = $allChecked
        }
    }
    $global:ActivateWindows.Checked = $allChecked
    $global:ActivateOffice.Checked = $allChecked
    $global:InstallKES.Checked = $allChecked
    $global:MaxUACOption.Checked = $allChecked
    $global:FirewallOption.Checked = $allChecked
    $btnToggle.Text = if ($allChecked) { "Снять все" } else { "Выбрать все" }
    $timer.Stop()
    $timerLabel.Visible = $false
})
$form.Controls.Add($btnToggle)

# Группа активации
$activationGroup = New-Object System.Windows.Forms.GroupBox
$activationGroup.Text = "Активация"
$activationGroup.Location = New-Object System.Drawing.Point(520, 10)  # Справа от панели
$activationGroup.Size = New-Object System.Drawing.Size(400, 80)
$form.Controls.Add($activationGroup)

$global:ActivateWindows = New-Object System.Windows.Forms.CheckBox
$global:ActivateWindows.Text = "Активировать Windows"
$global:ActivateWindows.Location = New-Object System.Drawing.Point(10, 24)
$global:ActivateWindows.Size = New-Object System.Drawing.Size(200, 20)
$global:ActivateWindows.Checked = $config.Activation.Windows
$activationGroup.Controls.Add($global:ActivateWindows)

$global:ActivateOffice = New-Object System.Windows.Forms.CheckBox
$global:ActivateOffice.Text = "Активировать Office"
$global:ActivateOffice.Location = New-Object System.Drawing.Point(10, 48)
$global:ActivateOffice.Size = New-Object System.Drawing.Size(200, 20)
$global:ActivateOffice.Checked = $config.Activation.Office
$activationGroup.Controls.Add($global:ActivateOffice)

$btnActivation = New-Object System.Windows.Forms.Button
$btnActivation.Text = "Активировать"
$btnActivation.Location = New-Object System.Drawing.Point(250, 25)
$btnActivation.Size = New-Object System.Drawing.Size(120, 30)
$btnActivation.FlatStyle = "Flat"
$btnActivation.Add_Click({
    if (-not ($global:ActivateWindows.Checked -or $global:ActivateOffice.Checked)) {
        [System.Windows.Forms.MessageBox]::Show("Не выбрано ни одного продукта для активации!", "Ошибка", "OK", "Error")
        return
    }
    $form.Hide()
    $progressForm = Show-ProgressForm
    $totalSteps = [int]$global:ActivateWindows.Checked + [int]$global:ActivateOffice.Checked
    $currentStep = 0
    $progressData = @{
        Form = $progressForm
        ProgressBar = $progressForm.Controls["progressBar"]
        CurrentStep = [ref]$currentStep
        TotalSteps = $totalSteps
    }
    Invoke-Activation -ActivateWindows $global:ActivateWindows.Checked -ActivateOffice $global:ActivateOffice.Checked -ProgressData $progressData
    $progressForm.Close()
    $form.Show()
    $form.Activate()
})
$activationGroup.Controls.Add($btnActivation)

# Группа KES
$kesGroup = New-Object System.Windows.Forms.GroupBox
$kesGroup.Text = "KES"
$kesGroup.Location = New-Object System.Drawing.Point(520, 120)  # Под "Активацией"
$kesGroup.Size = New-Object System.Drawing.Size(400, 65)
$form.Controls.Add($kesGroup)

$global:InstallKES = New-Object System.Windows.Forms.CheckBox
$global:InstallKES.Text = "Установить KES"
$global:InstallKES.Location = New-Object System.Drawing.Point(10, 25)
$global:InstallKES.Size = New-Object System.Drawing.Size(150, 20)
$global:InstallKES.Checked = $config.KES
$kesGroup.Controls.Add($global:InstallKES)

$btnInstallKES = New-Object System.Windows.Forms.Button
$btnInstallKES.Text = "Установить KES"
$btnInstallKES.Location = New-Object System.Drawing.Point(250, 20)
$btnInstallKES.Size = New-Object System.Drawing.Size(120, 30)
$btnInstallKES.FlatStyle = "Flat"
$btnInstallKES.Add_Click({
    if ($global:InstallKES.Checked) {
        $form.Hide()
        $progressForm = Show-ProgressForm
        $totalSteps = 1
        $currentStep = 0
        $progressData = @{
            Form = $progressForm
            ProgressBar = $progressForm.Controls["progressBar"]
            CurrentStep = [ref]$currentStep
            TotalSteps = $totalSteps
        }
        Install-KES -ProgressData $progressData
        $progressForm.Close()
        $form.Show()
        $form.Activate()
    }
})
$kesGroup.Controls.Add($btnInstallKES)

# Группа скриптов
$scriptGroup = New-Object System.Windows.Forms.GroupBox
$scriptGroup.Text = "Дополнительные опции"
$scriptGroup.Location = New-Object System.Drawing.Point(520, 210)  # Под "KES"
$scriptGroup.Size = New-Object System.Drawing.Size(400, 80)
$form.Controls.Add($scriptGroup)

$global:MaxUACOption = New-Object System.Windows.Forms.CheckBox
$global:MaxUACOption.Text = "UAC на максимум"
$global:MaxUACOption.Location = New-Object System.Drawing.Point(10, 20)
$global:MaxUACOption.Size = New-Object System.Drawing.Size(200, 20)
$global:MaxUACOption.Checked = $config.MaxUAC
$scriptGroup.Controls.Add($global:MaxUACOption)

$global:FirewallOption = New-Object System.Windows.Forms.CheckBox
$global:FirewallOption.Text = "Выключить Firewall"
$global:FirewallOption.Location = New-Object System.Drawing.Point(10, 45)
$global:FirewallOption.Size = New-Object System.Drawing.Size(200, 20)
$global:FirewallOption.Checked = $config.DisableFirewall
$scriptGroup.Controls.Add($global:FirewallOption)

$btnScriptGroup = New-Object System.Windows.Forms.Button
$btnScriptGroup.Text = "Запустить скрипты"
$btnScriptGroup.Location = New-Object System.Drawing.Point(250, 25)
$btnScriptGroup.Size = New-Object System.Drawing.Size(120, 30)
$btnScriptGroup.FlatStyle = "Flat"
$btnScriptGroup.Add_Click({
    $form.Hide()
    $progressForm = Show-ProgressForm
    $totalSteps = [int]$global:MaxUACOption.Checked + [int]$global:FirewallOption.Checked
    $currentStep = 0
    $progressData = @{
        Form = $progressForm
        ProgressBar = $progressForm.Controls["progressBar"]
        CurrentStep = [ref]$currentStep
        TotalSteps = $totalSteps
    }
    Install-Scripts -MaxUAC $global:MaxUACOption.Checked -Firewall $global:FirewallOption.Checked -ProgressData $progressData
    $progressForm.Close()
    $form.Show()
    $form.Activate()
})
$scriptGroup.Controls.Add($btnScriptGroup)

# Таймер
$script:counter = 20
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000

$timerLabel = New-Object System.Windows.Forms.Label
$timerLabel.Location = New-Object System.Drawing.Point(10, 373)  # Под панелью
$timerLabel.Size = New-Object System.Drawing.Size(300, 20)
$timerLabel.Text = "Автоматическая установка через: $script:counter сек."
$form.Controls.Add($timerLabel)

# Кнопка установки
$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Установить выбранное"
$installButton.Location = New-Object System.Drawing.Point(10, 400)  # Под таймером
$installButton.Size = New-Object System.Drawing.Size(500, 50)
$installButton.FlatStyle = "Flat"
$installButton.Add_Click({
    $selected = @()
    foreach ($control in $panel.Controls) {
        if ($control -is [System.Windows.Forms.CheckBox] -and $control.Checked) {
            $selected += $control.Tag
        }
    }
    if ($selected.Count -gt 0 -or $global:ActivateWindows.Checked -or $global:ActivateOffice.Checked -or $global:InstallKES.Checked -or $global:MaxUACOption.Checked -or $global:FirewallOption.Checked) {
        $timer.Stop()
        $timerLabel.Visible = $false
        $form.Hide()
        Start-Installation -Scripts $selected
        #$form.Close()
		$form.Show()
    } else {
        [System.Windows.Forms.MessageBox]::Show("Не выбрано ни одной программы или опции!", "Ошибка", "OK", "Error")
    }
})
$form.Controls.Add($installButton)

# Обработка таймера
$timer.Add_Tick({
    $script:counter--
    $timerLabel.Text = "Автоматическая установка через: $script:counter сек."

    # Определяем стиль шрифта
    $fontStyle = if ($script:counter % 2 -eq 1) {
        [System.Drawing.FontStyle]::Bold
    } else {
        [System.Drawing.FontStyle]::Regular
    }

    # Обновляем шрифт метки
    $timerLabel.Font = New-Object System.Drawing.Font($timerLabel.Font.FontFamily, $timerLabel.Font.Size, $fontStyle)

    if ($script:counter -le 0) {
        $timer.Stop()
        $timerLabel.Visible = $false
		$installButton.PerformClick()
    }
})

function Show-ProgressForm {
    $progressForm = New-Object System.Windows.Forms.Form
    $progressForm.Text = "Прогресс установки"
    $progressForm.Size = New-Object System.Drawing.Size(450, 150)
    $progressForm.StartPosition = "CenterScreen"
    $progressForm.FormBorderStyle = "FixedDialog"
    $progressForm.TopMost = $true

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Name = "progressBar"
    $progressBar.Location = New-Object System.Drawing.Point(20, 20)
    $progressBar.Size = New-Object System.Drawing.Size(400, 20)
    $progressForm.Controls.Add($progressBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Name = "statusLabel"
    $statusLabel.Location = New-Object System.Drawing.Point(20, 50)
    $statusLabel.Size = New-Object System.Drawing.Size(400, 20)
    $progressForm.Controls.Add($statusLabel)

    $progressForm.Show()
    $progressForm.Refresh()
    return $progressForm
}

function Start-Installation {
    param ([array]$Scripts)
    
    $progressForm = Show-ProgressForm
    $totalSteps = $Scripts.Count + [int]$global:InstallKES.Checked + [int]$global:ActivateWindows.Checked + [int]$global:ActivateOffice.Checked + [int]$global:MaxUACOption.Checked + [int]$global:FirewallOption.Checked
    $currentStep = 0
    $progressData = @{
        Form = $progressForm
        ProgressBar = $progressForm.Controls["progressBar"]
        CurrentStep = [ref]$currentStep
        TotalSteps = $totalSteps
    }

    try {
        if ($global:FirewallOption.Checked) {
            Install-Scripts -MaxUAC $false -Firewall $global:FirewallOption.Checked -ProgressData $progressData
        }
        if ($Scripts.Count -gt 0) {
            Install-Programs -Scripts $Scripts -ProgressData $progressData
        }
        if ($global:ActivateWindows.Checked -or $global:ActivateOffice.Checked) {
            Invoke-Activation -ActivateWindows $global:ActivateWindows.Checked -ActivateOffice $global:ActivateOffice.Checked -ProgressData $progressData
        }
        if ($global:InstallKES.Checked) {
            Install-KES -ProgressData $progressData
        }
        if ($global:MaxUACOption.Checked) {
            Install-Scripts -MaxUAC $global:MaxUACOption.Checked -Firewall $false -ProgressData $progressData
        }
    } catch {
        Write-Log "Критическая ошибка в Start-Installation: $_" -Source "Start-Installation"
        [System.Windows.Forms.MessageBox]::Show("Произошла ошибка: $_", "Ошибка", "OK", "Error")
    } finally {
        $progressForm.Close()
        [System.Windows.Forms.MessageBox]::Show("Установка завершена!", "Готово", "OK", "Information")
    }
}

# Запуск
$timer.Start()
[void]$form.ShowDialog()