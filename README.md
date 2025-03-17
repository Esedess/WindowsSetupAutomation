# 🛠 Автоматический установщик программ для Windows

Добро пожаловать! Этот инструмент поможет вам быстро установить популярные программы, активировать Windows/Office и настроить систему. Всё это — с минимальными усилиями и максимальной автоматизацией.

![Main script GUI](https://raw.githubusercontent.com/Esedess/WindowsSetupAutomation/44c9e85dc974d1d0442f490c639a14dcdf9e3d90/WindowsSetupAutomation.jpg)

---

## 📦 Основные возможности

- Установка популярных программ (Chrome, 7-Zip, Office и др.)
- Активация Windows и Office
- Настройка UAC и брандмауэра
- Автозапуск через 20 секунд с индикацией прогресса
- Логирование всех действий для удобного отслеживания

---

## 🚀 Быстрый старт

1. **Скачайте и распакуйте архив**  
   Загрузите архив с инструментом и распакуйте его в удобное место.
2. **Запустите `StartGUI.cmd`**  
   Щелкните правой кнопкой мыши → выберите "Запуск от имени администратора".
3. **Выберите программы и опции**  
   В открывшемся окне отметьте нужное.
4. **Начните установку**  
   Нажмите "Установить выбранное" или просто подождите 20 секунд — скрипт запустится автоматически.

> 💡 **Совет**: Если не хотите ждать автостарта, запускайте установку вручную!

---

## ⚙️ Добавление новых программ

Хотите установить что-то своё? Вот пошаговая инструкция:

### Шаг 1: Подготовка файлов
1. Создайте папку в директории `apps` с названием программы.  
   Пример: `apps/Notepad++`
2. Поместите установочный файл в эту папку.  
   Поддерживаемые форматы: `.exe`, `.msi`, `.bat`.

### Шаг 2: Создание скрипта
1. Создайте файл `НазваниеПрограммы.ps1` в папке программы.  
   Пример: `apps/Notepad++/Notepad++.ps1`
2. Скопируйте и настройте этот шаблон:
```bash
   param(
       [string]$RootPath = $PSScriptRoot,
       [string]$LogPath
   )

   $dirName = "Notepad++"          # Имя программы
   $installFile = "npp.8.6.7.exe"  # Точное имя установочного файла
   $Arguments = "/S"               # Параметры тихой установки

   function Write-Log {
       param($message)
       "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$dirName] $message" | Out-File $LogPath -Append -Encoding UTF8
   }

   try {
       Write-Log "Запуск установки"
       $process = Start-Process "$RootPath\$installFile" -ArgumentList $Arguments -Verb RunAs -PassThru -Wait
       if ($process.ExitCode -eq 0) {
           Write-Log "Успешно! Код: $($process.ExitCode)"
       } else {
           throw "Ошибка. Код: $($process.ExitCode)"
       }
   }
   catch {
       Write-Log "Сбой: $_"
       throw
   }
```
2. Укажите правильные значения для $installFile и $Arguments.

### Шаг 3: Обновление конфига
Откройте файл `installer_config.json` и добавьте программу в список:

```json
"Programs": [
    ...,
    "Notepad++"
]
```

🔍 Подсказка: Параметры тихой установки можно найти в разделе "Параметры установки" ниже.


---


## Настройка автозапуска скрипта после установки Windows

Чтобы ваш скрипт автоматически запускался после установки Windows, можно воспользоваться программой [ntlite](https://www.ntlite.com/download/) и добавить в ваш iso комманду запуска после первого входа. Это позволит запускать скрипт `main.ps1` с флешки или iso после завершения установки системы.

Для автоматизации процесса рекомендуется отключить UAC через ntlite и включить его после окончания установки.

#### Вариант команды который я использую

```bash
timeout 180 && powershell -nologo -noninteractive -windowStyle hidden -noprofile -executionpolicy bypass -Command "$scriptDrive = Get-Volume -FileSystemLabel 'YOUR_LABEL'; $drive = $scriptDrive.DriveLetter; powershell  -nologo -noninteractive -windowStyle hidden -noprofile -executionpolicy bypass -file \"$drive`:\YOUR_PATH\main.ps1""
```

- Заменить **YOUR_LABEL** на вашу метку флешки или CD
- Заменить **YOUR_PATH** на ваш путь к `main.ps1`

Возможно есть и другие варианты автозапуска.

---


## 🔄 Обновление программ

Чтобы обновить программу:
1. Замените установочный файл в папке программы.  
   Пример: `apps/7-Zip/7z2409-x64.exe` → `7z2500-x64.exe`.

2. При необходимости обновите скрипт:  
   - Измените `$installFile` на новое имя файла.  
   - Проверьте `$Arguments`, если параметры установки изменились.  
   Пример: `$Arguments = "/S /D=C:\Program Files\7-Zip"`.

---

## 🛠 Параметры установки

Не знаете, какие аргументы использовать? Вот подсказки:

| Тип файла | Примеры аргументов      | Где найти информацию          |
|-----------|-------------------------|-------------------------------|
| `.exe`    | `/SILENT`, `/VERYSILENT`| [silentinstallhq.com](https://silentinstallhq.com), [silentinstall.org](https://silentinstall.org) |
| `.msi`    | `/qn`, `/norestart`     | Введите `msiexec /?` в командной строке |
| `.bat`    | Не требуются            | —                             |

---

## ❗ Важно

- **Права администратора**: Всегда запускайте скрипт с правами администратора.
- **Логи**: Логи хранятся на рабочем столе в файле `InstallLog.txt`.  
  Путь: `C:\Users\ВАШ_ПОЛЬЗОВАТЕЛЬ\Desktop\InstallLog.txt`.
- **Ошибки**: Если что-то пошло не так, проверьте код выхода в логах.

---

## 🆘 Поддержка

Столкнулись с проблемой?  
- Изучите логи в `InstallLog.txt`.  
- Погуглите ошибки PowerShell — это часто помогает.  
- Если совсем не получается, пишите мне, разберёмся вместе!

---

## 🌐 Полезные ссылки

- [Silent Install HQ](https://silentinstall.org) — параметры тихой установки.
- [PowerShell Docs](https://docs.microsoft.com/powershell) — документация по PowerShell.
- [GitHub Issues]([https://github.com](https://github.com/Esedess/WindowsSetupAutomation/issues)) — сообщайте об ошибках или предлагайте улучшения.
