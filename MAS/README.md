# Microsoft Activation Scripts

Этот раздел изначально рассчитан на [Microsoft Activation Scripts](https://github.com/massgravel/Microsoft-Activation-Scripts).

Скачайте MAS, откройте папку `MAS` внутри архива и скопируйте её содержимое сюда, не удаляя:

```text
MAS_WINDOWS.ps1
MAS_OFFICE.ps1
```

Минимально необходимый файл:

```text
MAS/Separate-Files-Version/Activators/TSforge_Activation.cmd
```

Обёртки вызывают его с `/Z-Windows` и `/Z-Office`. `All-In-One-Version-KL/MAS_AIO.cmd` можно оставить для ручного запуска и диагностики.

Файлы MAS не дублируются в этом репозитории, чтобы их можно было брать актуальными непосредственно у авторов.
