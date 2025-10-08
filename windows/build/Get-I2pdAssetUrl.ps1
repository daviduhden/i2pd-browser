# Copyright (c) 2013-2025, The PurpleI2P Project
# Авторские права (c) 2013-2025, The PurpleI2P Project
# This file is part of Purple i2pd project and licensed under BSD3
# Этот файл — часть проекта Purple i2pd и распространяется по BSD3
# See full license text in LICENSE file at top of project tree
# Полный текст лицензии см. в файле LICENSE в корне проекта

param(
    # Required string parameter — path to a JSON file (e.g., a GitHub release JSON).
    # Обязательный строковый параметр — путь к JSON-файлу (например, JSON релиза GitHub).
    [Parameter(Mandatory = $true)]
    [string]$JsonPath,

    # Required string parameter — OS tag used to filter assets.
    # Обязательный строковый параметр — тег ОС для фильтрации ассетов.
    [Parameter(Mandatory = $true)]
    [string]$OsTag
)

# Suppress progress bars/messages so the script's output stays clean (only URLs if found).
# Отключает прогресс-индикаторы, чтобы вывод оставался чистым (только URL при наличии).
$ProgressPreference = 'SilentlyContinue'

# Read the JSON file as raw text and convert it to a PowerShell object.
# Читает JSON как текст и преобразует его в объект PowerShell.
$release = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json

# From the release's assets, select the first whose name ends with "_<OsTag>_mingw.zip".
# Из списка ассетов выбирает первый, имя которого оканчивается на "_<OsTag>_mingw.zip".
$asset = $release.assets | Where-Object { $_.name -match "_${OsTag}_mingw\.zip$" } | Select-Object -First 1

# If a matching asset exists, output its browser_download_url (direct download link).
# Если подходящий ассет найден — вывести его browser_download_url (прямая ссылка).
if ($asset) {
    $asset.browser_download_url
}