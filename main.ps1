param([string]$ScriptRoot = $PSScriptRoot)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList @('-NoLogo','-NonInteractive','-WindowStyle','Hidden','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-ScriptRoot',"`"$PSScriptRoot`"") -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Version = '2.0.2'
$script:RootPath = [IO.Path]::GetFullPath($ScriptRoot).TrimEnd('\')
$script:AppsPath = Join-Path $script:RootPath 'apps'
$script:ConfigPath = Join-Path $script:RootPath 'installer_config.json'
$script:LogPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'InstallLog.txt'
$script:Config = $null
$script:Timer = $null
$script:IsRunning = $false
$script:CanSaveConfig = $false
$script:ReadOnlyReason = ''

function Write-Log {
    param([string]$Message, [string]$Source = 'Main')
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$Source] $Message" | Out-File -LiteralPath $script:LogPath -Append -Encoding UTF8
}

function Show-Error([string]$Message) {
    [void][Windows.Forms.MessageBox]::Show($Message, 'Ошибка', 'OK', 'Error')
}

function Get-FullProjectPath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw 'Путь не указан.' }
    if ([IO.Path]::IsPathRooted($RelativePath)) { throw 'Разрешены только относительные пути внутри проекта.' }
    $full = [IO.Path]::GetFullPath((Join-Path $script:RootPath $RelativePath))
    if (-not ($full.Equals($script:RootPath, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($script:RootPath + '\', [StringComparison]::OrdinalIgnoreCase))) { throw 'Путь выходит за пределы проекта.' }
    return $full
}

function Test-PathWithin([string]$Candidate, [string]$Parent) {
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
    return ($candidateFull.Equals($parentFull, [StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($parentFull + '\', [StringComparison]::OrdinalIgnoreCase))
}

function Get-AllowedRoot($Entry) {
    if ([string]$Entry.Category -eq 'Application') { return $script:AppsPath }
    switch ([string]$Entry.Group) {
        'Activation' { return (Join-Path $script:RootPath 'MAS') }
        'KES' { return (Join-Path $script:RootPath 'KES') }
        default { return (Join-Path $script:RootPath 'scripts') }
    }
}

function Get-AutomaticRootPath($Entry) {
    if ([string]$Entry.Category -eq 'Application') { return $script:AppsPath }
    if ([string]$Entry.Group -eq 'Settings') { return (Join-Path $script:RootPath 'scripts') }
    return $script:RootPath
}

function Convert-ToRelativePath([string]$FullPath) {
    $rootUri = New-Object Uri(($script:RootPath.TrimEnd('\') + '\'))
    $fileUri = New-Object Uri([IO.Path]::GetFullPath($FullPath))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString()).Replace('/', '\')
}

function Normalize-Entry($Entry, [string]$Category) {
    $defaultGroup = 'Settings'
    if ($Category -eq 'Script') {
        if ([string]$Entry.Id -in @('activate-windows','activate-office')) { $defaultGroup = 'Activation' }
        elseif ([string]$Entry.Id -eq 'kes') { $defaultGroup = 'KES' }
    }
    $defaults = @{
        Id=[guid]::NewGuid().ToString(); Name='Без имени'; Category=$Category; Type='PowerShell'; Path=''; Arguments=''
        SuccessExitCodes=@(0,1641,3010); Selected=$false; Order=100; PassRootPath=$false; PassLogPath=$true; RootPath='.'; Group=$defaultGroup
    }
    foreach ($name in $defaults.Keys) {
        if (-not $Entry.PSObject.Properties[$name]) { $Entry | Add-Member $name $defaults[$name] }
    }
    return $Entry
}

function Get-ConfigWriteState {
    try {
        $root = [IO.Path]::GetPathRoot($script:ConfigPath)
        $drive = New-Object IO.DriveInfo($root)
        if ($drive.DriveType -eq [IO.DriveType]::CDRom) { return [pscustomobject]@{Writable=$false;Reason='Проект запущен с CD/DVD или ISO-образа. Настройки доступны только для чтения.'} }
        $item = Get-Item -LiteralPath $script:ConfigPath
        if (($item.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) { return [pscustomobject]@{Writable=$false;Reason='Файл installer_config.json имеет атрибут «Только чтение».'} }
        $stream = [IO.File]::Open($script:ConfigPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
        $stream.Close()
        return [pscustomobject]@{Writable=$true;Reason=''}
    } catch { return [pscustomobject]@{Writable=$false;Reason="Конфигурацию нельзя изменить: $($_.Exception.Message)"} }
}

function Load-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) { throw "Не найден $($script:ConfigPath)" }
    $config = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.PSObject.Properties['SchemaVersion'] -or [int]$config.SchemaVersion -lt 2) { throw 'Требуется конфигурация SchemaVersion 2.' }
    if (-not $config.PSObject.Properties['Settings']) { throw 'В конфигурации отсутствует Settings.' }
    $settingDefaults=@{ExecutionOrder=@('@applications');StopOnError=$false;ClearLogBeforeRun=$false}
    foreach($name in $settingDefaults.Keys){if(-not$config.Settings.PSObject.Properties[$name]){$config.Settings|Add-Member $name $settingDefaults[$name]}}
    $config.Applications = @($config.Applications | ForEach-Object { Normalize-Entry $_ 'Application' })
    $config.Scripts = @($config.Scripts | ForEach-Object { Normalize-Entry $_ 'Script' })
    return $config
}

function Get-OrderedSelectedEntries($Entries) {
    $selected=@($Entries)
    $result=New-Object Collections.Generic.List[object]
    $added=New-Object Collections.Generic.HashSet[string]
    foreach($id in @($script:Config.Settings.ExecutionOrder)){
        if($id-eq'@applications'){
            foreach($entry in @($selected|Where-Object{$_.Category-eq'Application'}|Sort-Object Order,Name)){$result.Add($entry);[void]$added.Add([string]$entry.Id)}
        }else{
            $entry=$selected|Where-Object{$_.Id-eq$id}|Select-Object -First 1
            if($null-ne$entry){$result.Add($entry);[void]$added.Add([string]$entry.Id)}
        }
    }
    foreach($entry in @($selected|Where-Object{-not$added.Contains([string]$_.Id)}|Sort-Object Order,Name)){$result.Add($entry)}
    return $result.ToArray()
}

function Save-Config {
    if (-not $script:CanSaveConfig) { throw $script:ReadOnlyReason }
    $temp = "$($script:ConfigPath).tmp"
    $script:Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $script:ConfigPath -Force
}

function Split-Arguments([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $result = New-Object Collections.Generic.List[string]
    $current = New-Object Text.StringBuilder
    $quoted = $false
    for ($i=0; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        if ($char -eq '"') { $quoted = -not $quoted; continue }
        if ([char]::IsWhiteSpace($char) -and -not $quoted) {
            if ($current.Length -gt 0) { $result.Add($current.ToString()); [void]$current.Clear() }
        } else { [void]$current.Append($char) }
    }
    if ($quoted) { throw 'В аргументах не закрыта кавычка.' }
    if ($current.Length -gt 0) { $result.Add($current.ToString()) }
    return $result.ToArray()
}

function ConvertTo-CommandLineArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    # Windows CommandLineToArgvW-compatible escaping for spaces, quotes and trailing slashes.
    return '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Resolve-EntryFile($Entry) {
    $relativePath = [string]$Entry.Path
    $allowedRoot=Get-AllowedRoot $Entry
    if ($relativePath -match '[*?]') {
        $relativeParent = Split-Path -Parent $relativePath
        $leaf = Split-Path -Leaf $relativePath
        if ($relativeParent -match '[*?]') { throw 'Маски разрешены только в имени файла, но не в имени папки.' }
        if ([string]::IsNullOrWhiteSpace($relativeParent) -or [string]::IsNullOrWhiteSpace($leaf)) { throw "Некорректная маска файла: $relativePath" }
        $parent = Get-FullProjectPath $relativeParent
        if (-not (Test-PathWithin $parent $allowedRoot)) { throw "Для раздела '$($Entry.Group)' разрешена только папка: $(Convert-ToRelativePath $allowedRoot)" }
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Папка не найдена: $parent" }
        $match = Get-ChildItem -LiteralPath $parent -Filter $leaf -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -eq $match) { throw "Файл не найден по маске: $relativePath" }
        return $match.FullName
    }
    $fullPattern = Get-FullProjectPath $relativePath
    if (-not (Test-PathWithin $fullPattern $allowedRoot)) { throw "Для раздела '$($Entry.Group)' разрешена только папка: $(Convert-ToRelativePath $allowedRoot)" }
    if (-not (Test-Path -LiteralPath $fullPattern -PathType Leaf)) { throw "Файл не найден: $($Entry.Path)" }
    return $fullPattern
}

function Test-Entry($Entry) {
    [void](Resolve-EntryFile $Entry)
    if ([string]$Entry.Type -notin @('Exe','Msi','Batch','PowerShell')) { throw "Неизвестный тип запуска: $($Entry.Type)" }
    [void](Split-Arguments ([string]$Entry.Arguments))
}

function Get-PowerShellParameterNames([string]$Path) {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "PowerShell-скрипт содержит синтаксические ошибки: $($errors[0].Message)"}
    if($null-eq$ast.ParamBlock){return @()}
    return @($ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
}

function Invoke-Entry($Entry) {
    $file = Resolve-EntryFile $Entry
    $type = [string]$Entry.Type
    $arguments = New-Object Collections.Generic.List[string]
    $executable = $file
    switch ($type) {
        'Msi' { $executable='msiexec.exe'; $arguments.Add('/i'); $arguments.Add($file) }
        'Batch' { $executable="$env:SystemRoot\System32\cmd.exe"; $arguments.Add('/d'); $arguments.Add('/c'); $arguments.Add($file) }
        'PowerShell' {
            $executable='powershell.exe'
            foreach($arg in @('-NoLogo','-NonInteractive','-WindowStyle','Hidden','-NoProfile','-ExecutionPolicy','Bypass','-File',$file)){ $arguments.Add($arg) }
            $parameterNames=Get-PowerShellParameterNames $file
            if('RootPath'-in$parameterNames){$arguments.Add('-RootPath');$arguments.Add((Get-AutomaticRootPath $Entry))}
            if('LogPath'-in$parameterNames){$arguments.Add('-LogPath');$arguments.Add($script:LogPath)}
        }
    }
    foreach($arg in (Split-Arguments ([string]$Entry.Arguments))){ $arguments.Add($arg) }
    Write-Log "Запуск: $($Entry.Name); тип=$type; файл=$file; аргументы=$($Entry.Arguments)" 'Runner'
    $argumentLine = (($arguments.ToArray() | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join ' ')
    $startParameters = @{
        FilePath = $executable
        WorkingDirectory = (Split-Path -Parent $file)
        PassThru = $true
        Wait = $true
    }
    if ($arguments.Count -gt 0) { $startParameters.ArgumentList = $argumentLine }
    $process = Start-Process @startParameters
    $successCodes = @($Entry.SuccessExitCodes | ForEach-Object { [int]$_ })
    if($process.ExitCode -notin $successCodes){ throw "Код завершения $($process.ExitCode), ожидался: $($successCodes -join ', ')" }
    Write-Log "Успешно: $($Entry.Name); код=$($process.ExitCode)" 'Runner'
    return $process.ExitCode
}

function New-Label([string]$Text,[int]$X,[int]$Y,[int]$Width=120) {
    $label=New-Object Windows.Forms.Label; $label.Text=$Text; $label.Location=New-Object Drawing.Point($X,$Y); $label.Size=New-Object Drawing.Size($Width,22); return $label
}

function New-ActionIcon([ValidateSet('Add','Edit','Delete')][string]$Kind) {
    $bitmap=New-Object Drawing.Bitmap(22,22)
    $graphics=[Drawing.Graphics]::FromImage($bitmap);$graphics.SmoothingMode='AntiAlias';$graphics.Clear([Drawing.Color]::Transparent)
    $pen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(55,65,75),2);$pen.StartCap='Round';$pen.EndCap='Round'
    switch($Kind){
        'Add' {$graphics.DrawLine($pen,11,4,11,18);$graphics.DrawLine($pen,4,11,18,11)}
        'Edit' {$graphics.DrawLine($pen,5,17,16,6);$graphics.DrawLine($pen,7,19,18,8);$graphics.DrawLine($pen,5,17,4,20);$graphics.DrawLine($pen,4,20,7,19);$graphics.DrawLine($pen,15,5,18,8)}
        'Delete' {$graphics.DrawRectangle($pen,6,7,10,12);$graphics.DrawLine($pen,4,5,18,5);$graphics.DrawLine($pen,9,3,13,3);$graphics.DrawLine($pen,9,10,9,16);$graphics.DrawLine($pen,13,10,13,16)}
    }
    $pen.Dispose();$graphics.Dispose();return $bitmap
}

function New-Entry([string]$Category,[string]$Group='Settings') {
    return [pscustomobject]@{
        Id=[guid]::NewGuid().ToString(); Name=''; Category=$Category; Type=$(if($Category -eq 'Application'){'Exe'}else{'PowerShell'})
        Path=''; Arguments=''; SuccessExitCodes=@(0,1641,3010); Selected=$false; Order=100
        PassRootPath=$false; PassLogPath=($Category -eq 'Script'); RootPath='.'; Group=$Group
    }
}

function Show-EntryEditor($Entry,[string]$Category,[bool]$IsNew) {
    $form=New-Object Windows.Forms.Form; $form.Text=$(if($IsNew){'Добавить запись'}else{'Редактировать запись'}); $form.Size=New-Object Drawing.Size(690,355); $form.StartPosition='CenterParent'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
    $nameBox=New-Object Windows.Forms.TextBox; $nameBox.Location=New-Object Drawing.Point(145,20); $nameBox.Size=New-Object Drawing.Size(510,22); $nameBox.Text=[string]$Entry.Name
    $typeBox=New-Object Windows.Forms.ComboBox; $typeBox.Location=New-Object Drawing.Point(145,58); $typeBox.Size=New-Object Drawing.Size(200,24); $typeBox.DropDownStyle='DropDownList'; [void]$typeBox.Items.AddRange(@('Exe','Msi','Batch','PowerShell')); $typeBox.SelectedItem=[string]$Entry.Type; if($typeBox.SelectedIndex-lt 0){$typeBox.SelectedIndex=0}
    $pathBox=New-Object Windows.Forms.TextBox; $pathBox.Location=New-Object Drawing.Point(145,96); $pathBox.Size=New-Object Drawing.Size(420,22); $pathBox.Text=[string]$Entry.Path
    $browse=New-Object Windows.Forms.Button; $browse.Text='Обзор...'; $browse.Location=New-Object Drawing.Point(575,94); $browse.Size=New-Object Drawing.Size(80,27)
    $argsBox=New-Object Windows.Forms.TextBox; $argsBox.Location=New-Object Drawing.Point(145,134); $argsBox.Size=New-Object Drawing.Size(510,54); $argsBox.Multiline=$true; $argsBox.Text=[string]$Entry.Arguments
    $codesBox=New-Object Windows.Forms.TextBox; $codesBox.Location=New-Object Drawing.Point(145,205); $codesBox.Size=New-Object Drawing.Size(200,22); $codesBox.Text=(@($Entry.SuccessExitCodes)-join', ')
    $orderBox=New-Object Windows.Forms.NumericUpDown; $orderBox.Location=New-Object Drawing.Point(145,243); $orderBox.Maximum=10000; $orderBox.Value=[decimal][int]$Entry.Order
    $selectedBox=New-Object Windows.Forms.CheckBox; $selectedBox.Text='Выбрано по умолчанию'; $selectedBox.Location=New-Object Drawing.Point(365,205); $selectedBox.Size=New-Object Drawing.Size(220,24); $selectedBox.Checked=[bool]$Entry.Selected
    $allowedRelative=Convert-ToRelativePath (Get-AllowedRoot $Entry)
    $hint=New-Object Windows.Forms.Label; $hint.Location=New-Object Drawing.Point(20,273); $hint.Size=New-Object Drawing.Size(430,35); $hint.ForeColor=[Drawing.Color]::DimGray; $hint.Text="Разрешённая папка: $allowedRelative. RootPath и LogPath передаются скриптам автоматически."
    $ok=New-Object Windows.Forms.Button; $ok.Text='Сохранить'; $ok.Location=New-Object Drawing.Point(470,270); $ok.Size=New-Object Drawing.Size(90,30)
    $cancel=New-Object Windows.Forms.Button; $cancel.Text='Отмена'; $cancel.Location=New-Object Drawing.Point(565,270); $cancel.Size=New-Object Drawing.Size(90,30); $cancel.DialogResult='Cancel'
    foreach($control in @((New-Label 'Название:' 20 22),(New-Label 'Тип запуска:' 20 60),(New-Label 'Путь:' 20 98),(New-Label 'Аргументы:' 20 136),(New-Label 'Коды успеха:' 20 207),(New-Label 'Порядок:' 20 245),$nameBox,$typeBox,$pathBox,$browse,$argsBox,$codesBox,$orderBox,$selectedBox,$hint,$ok,$cancel)){ $form.Controls.Add($control) }
    $browse.Add_Click({
        $allowedRoot=Get-AllowedRoot $Entry;$dialog=New-Object Windows.Forms.OpenFileDialog; $dialog.InitialDirectory=$allowedRoot; $dialog.Filter='Поддерживаемые файлы|*.exe;*.msi;*.cmd;*.bat;*.ps1|Все файлы|*.*'
        if($dialog.ShowDialog($form)-eq'OK'){
            $allowed=Test-PathWithin $dialog.FileName $allowedRoot
            if(-not $allowed){Show-Error 'Файл находится вне разрешённой папки.';return}
            $pathBox.Text=Convert-ToRelativePath $dialog.FileName
            switch([IO.Path]::GetExtension($dialog.FileName).ToLowerInvariant()){'.msi'{$typeBox.SelectedItem='Msi'}'.ps1'{$typeBox.SelectedItem='PowerShell'}'.cmd'{$typeBox.SelectedItem='Batch'}'.bat'{$typeBox.SelectedItem='Batch'}default{$typeBox.SelectedItem='Exe'}}
        }
    })
    $ok.Add_Click({
        try{
            if([string]::IsNullOrWhiteSpace($nameBox.Text)){throw 'Укажите название.'}
            $codes=@($codesBox.Text-split'[,; ]+'|Where-Object{$_}|ForEach-Object{[int]$_}); if($codes.Count-eq 0){throw 'Укажите код успешного завершения.'}
            $candidate=[pscustomobject]@{Id=[string]$Entry.Id;Name=$nameBox.Text.Trim();Category=$Category;Type=[string]$typeBox.SelectedItem;Path=$pathBox.Text.Trim();Arguments=$argsBox.Text.Trim();SuccessExitCodes=$codes;Selected=$selectedBox.Checked;Order=[int]$orderBox.Value;PassRootPath=$false;PassLogPath=$false;RootPath='.';Group=[string]$Entry.Group}
            Test-Entry $candidate; $form.Tag=$candidate; $form.DialogResult='OK'; $form.Close()
        }catch{Show-Error $_.Exception.Message}
    })
    $form.AcceptButton=$ok; $form.CancelButton=$cancel
    if($form.ShowDialog()-eq'OK'){return $form.Tag}; return $null
}

function Show-ProgressForm([int]$Maximum) {
    $form=New-Object Windows.Forms.Form; $form.Text='Выполнение'; $form.Size=New-Object Drawing.Size(560,175); $form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.ControlBox=$false; $form.TopMost=$true
    $bar=New-Object Windows.Forms.ProgressBar; $bar.Name='progressBar'; $bar.Location=New-Object Drawing.Point(20,22); $bar.Size=New-Object Drawing.Size(505,24); $bar.Maximum=[Math]::Max(1,$Maximum)
    $status=New-Object Windows.Forms.Label; $status.Name='statusLabel'; $status.Location=New-Object Drawing.Point(20,60); $status.Size=New-Object Drawing.Size(505,48)
    $form.Controls.Add($bar);$form.Controls.Add($status);$form.Show();$form.Refresh();return $form
}

function Show-TimerSettings {
    $form=New-Object Windows.Forms.Form;$form.Text='Настройки автозапуска';$form.Size=New-Object Drawing.Size(390,190);$form.StartPosition='CenterParent';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false
    $enabled=New-Object Windows.Forms.CheckBox;$enabled.Text='Автоматически запускать выбранное';$enabled.Location=New-Object Drawing.Point(20,20);$enabled.Size=New-Object Drawing.Size(320,24);$enabled.Checked=[bool]$script:Config.Settings.AutoStartEnabled
    $label=New-Label 'Задержка, секунд:' 20 62 145
    $seconds=New-Object Windows.Forms.NumericUpDown;$seconds.Location=New-Object Drawing.Point(170,60);$seconds.Minimum=1;$seconds.Maximum=86400;$seconds.Value=[Math]::Max(1,[int]$script:Config.Settings.AutoStartSeconds)
    $ok=New-Object Windows.Forms.Button;$ok.Text='Сохранить';$ok.Location=New-Object Drawing.Point(180,105);$ok.Size=New-Object Drawing.Size(85,30)
    $cancel=New-Object Windows.Forms.Button;$cancel.Text='Отмена';$cancel.Location=New-Object Drawing.Point(275,105);$cancel.Size=New-Object Drawing.Size(75,30);$cancel.DialogResult='Cancel'
    foreach($control in @($enabled,$label,$seconds,$ok,$cancel)){$form.Controls.Add($control)}
    $ok.Add_Click({$script:Config.Settings.AutoStartEnabled=$enabled.Checked;$script:Config.Settings.AutoStartSeconds=[int]$seconds.Value;Save-Config;$form.DialogResult='OK';$form.Close()})
    $form.AcceptButton=$ok;$form.CancelButton=$cancel;[void]$form.ShowDialog()
}

function Invoke-SelectedEntries($Entries,$Owner,[string]$LaunchMode='вручную') {
    $ordered=@(Get-OrderedSelectedEntries $Entries); if($ordered.Count-eq 0){Show-Error 'Ничего не выбрано.';return}
    if([bool]$script:Config.Settings.ClearLogBeforeRun){try{''|Set-Content -LiteralPath $script:LogPath -Encoding UTF8}catch{Show-Error "Не удалось очистить журнал: $($_.Exception.Message)";return}}
    Write-Log "Начало установки: $LaunchMode; операций: $($ordered.Count)" 'Queue'
    Write-Log (($ordered | ForEach-Object -Begin {$number=0} -Process { $number++; "$number. $($_.Name)" }) -join ' | ') 'Queue'
    $script:IsRunning=$true;$Owner.Hide();$progress=Show-ProgressForm $ordered.Count;$results=New-Object Collections.Generic.List[object]
    try{
        for($i=0;$i-lt$ordered.Count;$i++){
            $entry=$ordered[$i];$progress.Controls['statusLabel'].Text="Выполняется: $($entry.Name) ($($i+1) из $($ordered.Count))";$progress.Refresh()
            try{$code=Invoke-Entry $entry;$results.Add([pscustomobject]@{Name=$entry.Name;Success=$true;Detail="Код $code"})}catch{Write-Log $_.Exception.Message ([string]$entry.Name);$results.Add([pscustomobject]@{Name=$entry.Name;Success=$false;Detail=$_.Exception.Message});if([bool]$script:Config.Settings.StopOnError){break}}
            $progress.Controls['progressBar'].Value=$i+1;$progress.Refresh()
        }
    }finally{$progress.Close();$Owner.Show();$Owner.Activate();$script:IsRunning=$false}
    $failed=@($results|Where-Object{-not $_.Success})
    if($failed.Count-eq 0){[void][Windows.Forms.MessageBox]::Show("Все операции завершены успешно.`nПодробности: $($script:LogPath)",'Готово','OK','Information')}
    else{[void][Windows.Forms.MessageBox]::Show("Завершено с ошибками: $($failed.Count) из $($results.Count).`n`n$($failed.Name-join"`n")`n`nПодробности: $($script:LogPath)",'Есть ошибки','OK','Warning')}
}

function Show-MainForm {
    $form=New-Object Windows.Forms.Form
    $form.Text="Автоматическая установка $($script:Version)"
    $form.Size=New-Object Drawing.Size(900,620)
    $form.StartPosition='CenterScreen'
    $form.MinimumSize=New-Object Drawing.Size(760,520)
    $toolTip=New-Object Windows.Forms.ToolTip

    $bottom=New-Object Windows.Forms.Panel;$bottom.Dock='Fill';$bottom.Padding=New-Object Windows.Forms.Padding(10)
    $timerLabel=New-Object Windows.Forms.Label;$timerLabel.Location=New-Object Drawing.Point(15,10);$timerLabel.Size=New-Object Drawing.Size(500,22)
    $cancelTimer=New-Object Windows.Forms.Button;$cancelTimer.Text='Отменить таймер';$cancelTimer.Location=New-Object Drawing.Point(15,38);$cancelTimer.Size=New-Object Drawing.Size(130,32)
    $timerSettings=New-Object Windows.Forms.Button;$timerSettings.Text='Настройки';$timerSettings.Location=New-Object Drawing.Point(155,38);$timerSettings.Size=New-Object Drawing.Size(120,32)
    $toggleAll=New-Object Windows.Forms.Button;$toggleAll.Text='Снять все';$toggleAll.Location=New-Object Drawing.Point(285,38);$toggleAll.Size=New-Object Drawing.Size(120,32)
    $runHost=New-Object Windows.Forms.Panel;$runHost.Dock='Right';$runHost.Width=250;$runHost.Padding=New-Object Windows.Forms.Padding(8)
    $run=New-Object Windows.Forms.Button;$run.Text='Установить выбранное';$run.Dock='Fill';$run.Font=New-Object Drawing.Font($run.Font.FontFamily,10,[Drawing.FontStyle]::Bold);$runHost.Controls.Add($run)
    foreach($control in @($timerLabel,$cancelTimer,$timerSettings,$toggleAll,$runHost)){$bottom.Controls.Add($control)}

    $tabs=New-Object Windows.Forms.TabControl;$tabs.Dock='Fill'
    $appTab=New-Object Windows.Forms.TabPage;$appTab.Text='Приложения';$appTab.Padding=New-Object Windows.Forms.Padding(10)
    $scriptTab=New-Object Windows.Forms.TabPage;$scriptTab.Text='Системные действия';$scriptTab.Padding=New-Object Windows.Forms.Padding(10)
    $settingsTab=New-Object Windows.Forms.TabPage;$settingsTab.Text='Настройки';$settingsTab.Padding=New-Object Windows.Forms.Padding(10)
    [void]$tabs.TabPages.Add($appTab);[void]$tabs.TabPages.Add($scriptTab);[void]$tabs.TabPages.Add($settingsTab)
    $rootLayout=New-Object Windows.Forms.TableLayoutPanel;$rootLayout.Dock='Fill';$rootLayout.ColumnCount=1;$rootLayout.RowCount=2
    [void]$rootLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    [void]$rootLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
    [void]$rootLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',92)))
    [void]$rootLayout.Controls.Add($tabs,0,0);[void]$rootLayout.Controls.Add($bottom,0,1);$form.Controls.Add($rootLayout)

    $allLists=New-Object Collections.Generic.List[object]
    $editorButtons=New-Object Collections.Generic.List[Windows.Forms.Button]

    function Register-EditorButtons($list,[string]$Category,[string]$Group,$hostPanel) {
        $add=New-Object Windows.Forms.Button;$add.Location=New-Object Drawing.Point(5,5);$add.Size=New-Object Drawing.Size(36,32);$add.Image=New-ActionIcon 'Add';$add.AccessibleName='Добавить'
        $edit=New-Object Windows.Forms.Button;$edit.Location=New-Object Drawing.Point(46,5);$edit.Size=New-Object Drawing.Size(36,32);$edit.Image=New-ActionIcon 'Edit';$edit.AccessibleName='Редактировать'
        $remove=New-Object Windows.Forms.Button;$remove.Location=New-Object Drawing.Point(87,5);$remove.Size=New-Object Drawing.Size(36,32);$remove.Image=New-ActionIcon 'Delete';$remove.AccessibleName='Удалить запись'
        foreach($button in @($add,$edit,$remove)){$button.FlatStyle='Flat';$button.FlatAppearance.BorderSize=0}
        $metadata=[pscustomobject]@{List=$list;Category=$Category;Group=$Group};$add.Tag=$metadata;$edit.Tag=$metadata;$remove.Tag=$metadata
        $toolTip.SetToolTip($add,'Добавить');$toolTip.SetToolTip($edit,'Редактировать');$toolTip.SetToolTip($remove,'Удалить запись')
        foreach($button in @($add,$edit,$remove)){$hostPanel.Controls.Add($button);$editorButtons.Add($button);if(-not$script:CanSaveConfig){$button.Enabled=$false;$toolTip.SetToolTip($button,$script:ReadOnlyReason);$toolTip.SetToolTip($hostPanel,$script:ReadOnlyReason)}}
        $add.Add_Click({
            $meta=$this.Tag;$new=Show-EntryEditor (New-Entry $meta.Category $meta.Group) $meta.Category $true
            if($null-ne$new){if($meta.Category-eq'Application'){$script:Config.Applications+=$new}else{$script:Config.Scripts+=$new};Save-Config;Refresh-Lists}
        })
        $edit.Add_Click({
            $meta=$this.Tag;$list=$meta.List;if($list.SelectedIndex-lt 0){Show-Error 'Выберите запись.';return}
            $old=$list.SelectedItem;$updated=Show-EntryEditor $old $meta.Category $false
            if($null-ne$updated){$target=if($meta.Category-eq'Application'){$script:Config.Applications}else{$script:Config.Scripts};for($i=0;$i-lt$target.Count;$i++){if($target[$i].Id-eq$old.Id){$target[$i]=$updated;break}};Save-Config;Refresh-Lists}
        })
        $remove.Add_Click({
            $meta=$this.Tag;$list=$meta.List;if($list.SelectedIndex-lt 0){Show-Error 'Выберите запись.';return};$old=$list.SelectedItem
            if([Windows.Forms.MessageBox]::Show("Удалить запись '$($old.Name)'? Файл удалён не будет.",'Подтверждение','YesNo','Question')-ne'Yes'){return}
            if($meta.Category-eq'Application'){$script:Config.Applications=@($script:Config.Applications|Where-Object{$_.Id-ne$old.Id})}else{$script:Config.Scripts=@($script:Config.Scripts|Where-Object{$_.Id-ne$old.Id})};Save-Config;Refresh-Lists
        })
    }

    $appLayout=New-Object Windows.Forms.TableLayoutPanel;$appLayout.Dock='Fill';$appLayout.ColumnCount=1;$appLayout.RowCount=2;[void]$appLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));[void]$appLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));[void]$appLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',44)))
    $appButtons=New-Object Windows.Forms.Panel;$appButtons.Dock='Fill'
    $appList=New-Object Windows.Forms.CheckedListBox;$appList.Dock='Fill';$appList.CheckOnClick=$true;$appList.DisplayMember='Name';$appList.IntegralHeight=$false
    [void]$appLayout.Controls.Add($appList,0,0);[void]$appLayout.Controls.Add($appButtons,0,1);$appTab.Controls.Add($appLayout);$allLists.Add($appList)
    Register-EditorButtons $appList 'Application' 'Applications' $appButtons

    $groupsPanel=New-Object Windows.Forms.TableLayoutPanel;$groupsPanel.Dock='Fill';$groupsPanel.ColumnCount=1;$groupsPanel.RowCount=3;[void]$groupsPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    foreach($percent in @(32,38,30)){[void]$groupsPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',$percent)))}
    $scriptTab.Controls.Add($groupsPanel)
    $groupMap=@{}
    $definitions=@(@('Activation','Активация'),@('Settings','Настройки системы'),@('KES','Антивирус'))
    for($g=0;$g-lt$definitions.Count;$g++){
        $key=$definitions[$g][0];$caption=$definitions[$g][1]
        $box=New-Object Windows.Forms.GroupBox;$box.Text=$caption;$box.Dock='Fill';$box.Padding=New-Object Windows.Forms.Padding(8)
        $groupLayout=New-Object Windows.Forms.TableLayoutPanel;$groupLayout.Dock='Fill';$groupLayout.ColumnCount=2;$groupLayout.RowCount=1;[void]$groupLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));[void]$groupLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',130)))
        $buttons=New-Object Windows.Forms.Panel;$buttons.Dock='Fill'
        $list=New-Object Windows.Forms.CheckedListBox;$list.Dock='Fill';$list.CheckOnClick=$true;$list.DisplayMember='Name';$list.IntegralHeight=$false
        [void]$groupLayout.Controls.Add($list,0,0);[void]$groupLayout.Controls.Add($buttons,1,0);$box.Controls.Add($groupLayout);[void]$groupsPanel.Controls.Add($box,0,$g)
        $allLists.Add($list);$groupMap[$key]=$list;Register-EditorButtons $list 'Script' $key $buttons
    }

    $settingsLayout=New-Object Windows.Forms.TableLayoutPanel;$settingsLayout.Dock='Fill';$settingsLayout.ColumnCount=2;$settingsLayout.RowCount=1
    [void]$settingsLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',62)));[void]$settingsLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',38)));[void]$settingsTab.Controls.Add($settingsLayout)
    $ordersLayout=New-Object Windows.Forms.TableLayoutPanel;$ordersLayout.Dock='Fill';$ordersLayout.RowCount=2;$ordersLayout.ColumnCount=1
    [void]$ordersLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',50)));[void]$ordersLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',50)));[void]$settingsLayout.Controls.Add($ordersLayout,0,0)

    function New-OrderBox([string]$Title) {
        $box=New-Object Windows.Forms.GroupBox;$box.Text=$Title;$box.Dock='Fill'
        $layout=New-Object Windows.Forms.TableLayoutPanel;$layout.Dock='Fill';$layout.ColumnCount=2;$layout.RowCount=1;[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)));[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',48)))
        $buttons=New-Object Windows.Forms.Panel;$buttons.Dock='Fill'
        $up=New-Object Windows.Forms.Button;$up.Text='↑';$up.Font=New-Object Drawing.Font($up.Font.FontFamily,14);$up.Location=New-Object Drawing.Point(7,30);$up.Size=New-Object Drawing.Size(34,34);$toolTip.SetToolTip($up,'Переместить вверх')
        $down=New-Object Windows.Forms.Button;$down.Text='↓';$down.Font=New-Object Drawing.Font($down.Font.FontFamily,14);$down.Location=New-Object Drawing.Point(7,70);$down.Size=New-Object Drawing.Size(34,34);$toolTip.SetToolTip($down,'Переместить вниз')
        $list=New-Object Windows.Forms.ListBox;$list.Dock='Fill';$list.DisplayMember='Name';$list.IntegralHeight=$false
        [void]$buttons.Controls.Add($up);[void]$buttons.Controls.Add($down);[void]$layout.Controls.Add($list,0,0);[void]$layout.Controls.Add($buttons,1,0);[void]$box.Controls.Add($layout)
        $up.Tag=$list;$down.Tag=$list
        $up.Add_Click({$list=$this.Tag;$index=$list.SelectedIndex;if($index-gt 0){$item=$list.Items[$index];$list.Items.RemoveAt($index);$list.Items.Insert($index-1,$item);$list.SelectedIndex=$index-1}})
        $down.Add_Click({$list=$this.Tag;$index=$list.SelectedIndex;if($index-ge 0-and$index-lt$list.Items.Count-1){$item=$list.Items[$index];$list.Items.RemoveAt($index);$list.Items.Insert($index+1,$item);$list.SelectedIndex=$index+1}})
        return [pscustomobject]@{Box=$box;List=$list;Buttons=@($up,$down)}
    }
    $stageOrder=New-OrderBox 'Порядок этапов';$appOrder=New-OrderBox 'Порядок приложений'
    [void]$ordersLayout.Controls.Add($stageOrder.Box,0,0);[void]$ordersLayout.Controls.Add($appOrder.Box,0,1)

    $options=New-Object Windows.Forms.GroupBox;$options.Text='Общие настройки';$options.Dock='Fill';[void]$settingsLayout.Controls.Add($options,1,0)
    $autoStart=New-Object Windows.Forms.CheckBox;$autoStart.Text='Автоматический запуск';$autoStart.Location=New-Object Drawing.Point(18,35);$autoStart.Size=New-Object Drawing.Size(240,24)
    $delayLabel=New-Label 'Задержка, секунд:' 18 72 145
    $delay=New-Object Windows.Forms.NumericUpDown;$delay.Location=New-Object Drawing.Point(165,70);$delay.Minimum=1;$delay.Maximum=86400;$delay.Width=100
    $stopOnError=New-Object Windows.Forms.CheckBox;$stopOnError.Text='Остановиться при ошибке';$stopOnError.Location=New-Object Drawing.Point(18,112);$stopOnError.Size=New-Object Drawing.Size(250,24)
    $clearLog=New-Object Windows.Forms.CheckBox;$clearLog.Text='Очищать журнал перед запуском';$clearLog.Location=New-Object Drawing.Point(18,146);$clearLog.Size=New-Object Drawing.Size(270,24)
    $orderHint=New-Object Windows.Forms.Label;$orderHint.Text='Этап «Установка приложений» объединяет все отмеченные приложения. Их внутренний порядок задаётся в соседнем списке.';$orderHint.Location=New-Object Drawing.Point(18,190);$orderHint.Size=New-Object Drawing.Size(270,70);$orderHint.ForeColor=[Drawing.Color]::DimGray
    $saveSettings=New-Object Windows.Forms.Button;$saveSettings.Text='Сохранить настройки';$saveSettings.Location=New-Object Drawing.Point(18,285);$saveSettings.Size=New-Object Drawing.Size(190,38)
    foreach($control in @($autoStart,$delayLabel,$delay,$stopOnError,$clearLog,$orderHint,$saveSettings)){$options.Controls.Add($control)}
    if(-not$script:CanSaveConfig){foreach($control in @($autoStart,$delay,$stopOnError,$clearLog,$saveSettings)+$stageOrder.Buttons+$appOrder.Buttons){$control.Enabled=$false;$toolTip.SetToolTip($control,$script:ReadOnlyReason)};$toolTip.SetToolTip($options,$script:ReadOnlyReason)}

    function Refresh-OrderLists {
        $stageOrder.List.Items.Clear()
        $stageItems=@([pscustomobject]@{Id='@applications';Name='Установка приложений'})+@($script:Config.Scripts|ForEach-Object{[pscustomobject]@{Id=$_.Id;Name=$_.Name}})
        $stageAdded=New-Object Collections.Generic.HashSet[string]
        foreach($id in @($script:Config.Settings.ExecutionOrder)){$item=$stageItems|Where-Object{$_.Id-eq$id}|Select-Object -First 1;if($null-ne$item){[void]$stageOrder.List.Items.Add($item);[void]$stageAdded.Add([string]$item.Id)}}
        foreach($item in $stageItems|Where-Object{-not$stageAdded.Contains([string]$_.Id)}){[void]$stageOrder.List.Items.Add($item)}
        $appOrder.List.Items.Clear();foreach($entry in @($script:Config.Applications|Sort-Object Order,Name)){[void]$appOrder.List.Items.Add($entry)}
        $autoStart.Checked=[bool]$script:Config.Settings.AutoStartEnabled;$delay.Value=[Math]::Max(1,[int]$script:Config.Settings.AutoStartSeconds);$stopOnError.Checked=[bool]$script:Config.Settings.StopOnError;$clearLog.Checked=[bool]$script:Config.Settings.ClearLogBeforeRun
    }
    $saveSettings.Add_Click({
        $script:Config.Settings.ExecutionOrder=@($stageOrder.List.Items|ForEach-Object{$_.Id});for($i=0;$i-lt$appOrder.List.Items.Count;$i++){$appOrder.List.Items[$i].Order=($i+1)*10}
        $script:Config.Settings.AutoStartEnabled=$autoStart.Checked;$script:Config.Settings.AutoStartSeconds=[int]$delay.Value;$script:Config.Settings.StopOnError=$stopOnError.Checked;$script:Config.Settings.ClearLogBeforeRun=$clearLog.Checked
        try{Save-Config;[void][Windows.Forms.MessageBox]::Show('Настройки сохранены. Новый таймер применяется при следующем запуске.','Готово','OK','Information')}catch{Show-Error $_.Exception.Message}
    })

    function Refresh-Lists {
        $appList.Items.Clear();foreach($entry in @($script:Config.Applications|Sort-Object Order,Name)){$index=$appList.Items.Add($entry);$appList.SetItemChecked($index,[bool]$entry.Selected)}
        foreach($key in $groupMap.Keys){$groupMap[$key].Items.Clear()}
        foreach($entry in @($script:Config.Scripts|Sort-Object Order,Name)){$key=[string]$entry.Group;if(-not$groupMap.ContainsKey($key)){$key='Settings'};$list=$groupMap[$key];$index=$list.Items.Add($entry);$list.SetItemChecked($index,[bool]$entry.Selected)}
        Update-ToggleCaption;Refresh-OrderLists
    }
    function Get-CheckedEntries {$result=@();foreach($list in $allLists){for($i=0;$i-lt$list.Items.Count;$i++){if($list.GetItemChecked($i)){$result+=$list.Items[$i]}}};return $result}
    function Get-AllChecked {foreach($list in $allLists){for($i=0;$i-lt$list.Items.Count;$i++){if(-not$list.GetItemChecked($i)){return $false}}};return $true}
    function Update-ToggleCaption {$toggleAll.Text=if(Get-AllChecked){'Снять все'}else{'Выбрать все'}}
    $toggleAll.Add_Click({$check=-not(Get-AllChecked);foreach($list in $allLists){for($i=0;$i-lt$list.Items.Count;$i++){$list.SetItemChecked($i,$check)}};Update-ToggleCaption})
    $run.Add_Click({
        if($script:Timer){$script:Timer.Stop()}
        $automatic=$script:AutomaticTrigger
        $script:AutomaticTrigger=$false
        $timerLabel.Text=if($automatic){'Запущено автоматически по таймеру'}else{'Запущено вручную'}
        Invoke-SelectedEntries (Get-CheckedEntries) $form $(if($automatic){'автоматически по таймеру'}else{'вручную'})
    })
    $cancelTimer.Add_Click({if($script:Timer){$script:Timer.Stop()};$timerLabel.Text='Автоматический запуск отменён';$cancelTimer.Enabled=$false})
    $timerSettings.Add_Click({if($script:Timer){$script:Timer.Stop()};$tabs.SelectedTab=$settingsTab;$timerLabel.Text='Таймер остановлен: открыты настройки';$cancelTimer.Enabled=$false})
    if(-not$script:CanSaveConfig){
        $timerSettings.Enabled=$false;$toolTip.SetToolTip($timerSettings,$script:ReadOnlyReason);$toolTip.SetToolTip($bottom,$script:ReadOnlyReason);$form.Text+=" — только чтение"
        $readOnlyLabel=New-Object Windows.Forms.Label;$readOnlyLabel.Text='Настройки недоступны: носитель только для чтения';$readOnlyLabel.Location=New-Object Drawing.Point(440,42);$readOnlyLabel.Size=New-Object Drawing.Size(240,32);$readOnlyLabel.ForeColor=[Drawing.Color]::DarkRed;$readOnlyLabel.TextAlign='MiddleLeft';$bottom.Controls.Add($readOnlyLabel);$toolTip.SetToolTip($readOnlyLabel,$script:ReadOnlyReason)
    }
    $form.Add_FormClosing({if($script:IsRunning){$_.Cancel=$true}})
    Refresh-Lists
    $script:Countdown=[int]$script:Config.Settings.AutoStartSeconds
    $script:AutomaticTrigger=$false
    if([bool]$script:Config.Settings.AutoStartEnabled-and$script:Countdown-gt 0){$timerLabel.Text="Автоматическая установка через: $($script:Countdown) сек.";$script:Timer=New-Object Windows.Forms.Timer;$script:Timer.Interval=1000;$script:Timer.Add_Tick({$script:Countdown--;$timerLabel.Text="Автоматическая установка через: $($script:Countdown) сек.";if($script:Countdown-le 0){$script:Timer.Stop();$script:AutomaticTrigger=$true;$run.PerformClick()}});$script:Timer.Start()}else{$timerLabel.Text='Автоматический запуск отключён';$cancelTimer.Enabled=$false}
    [void]$form.ShowDialog()
}

try{Set-Location $script:RootPath;$script:Config=Load-Config;$writeState=Get-ConfigWriteState;$script:CanSaveConfig=$writeState.Writable;$script:ReadOnlyReason=$writeState.Reason;Show-MainForm}catch{try{Write-Log $_.Exception.ToString() 'Fatal'}catch{};Show-Error $_.Exception.Message;exit 1}
