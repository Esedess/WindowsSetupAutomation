# Интеграция Kaspersky Endpoint Security

Сценарий `KES.ps1` ожидает следующую локальную структуру:

```text
KES/
├── KES.ps1
├── ActivationCode.txt       # необязательно, одна строка с кодом
└── KES/
    ├── setup_kes.exe
    ├── setup.ini
    └── остальные файлы распакованного установщика
```

Код можно хранить в `ActivationCode.txt` либо указать в `setup.ini`:

```ini
[Setup]
ActivationCode=XXXXX-XXXXX-XXXXX-XXXXX
```

При наличии непустого `ActivationCode.txt` сценарий передаёт код установщику через `/pACTIVATIONCODE`. Без этого файла используется конфигурация распакованного установщика. Дистрибутив и код активации в репозиторий не входят.
