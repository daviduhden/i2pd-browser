@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM Авторские права (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM Этот файл — часть проекта Purple i2pd и распространяется по BSD3
REM See full license text in LICENSE file at top of project tree
REM Полный текст лицензии см. в файле LICENSE в корне проекта

setlocal EnableExtensions EnableDelayedExpansion

REM Detect locale (user UI language) -> ru or en-US
REM Определить язык интерфейса пользователя -> ru или en-US

set "locale=en-US"
set "SHOW_RU=0"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Control Panel\International" /v LocaleName ^| find "LocaleName"') do set "LOCALE_NAME=%%B"
if defined LOCALE_NAME (
  set "LC2=!LOCALE_NAME:~0,2!"
  if /i "!LC2!"=="ru" (
    set "SHOW_RU=1"
    set "locale=ru"
  )
)

REM Switch to UTF-8 only when printing Russian (avoid mojibake)
REM Включать UTF-8 только при печати русского (чтобы избежать кракозябр)
if "%SHOW_RU%"=="1" chcp 65001 >nul

REM Ensure WinGet and required tools are installed/available
REM Убедиться, что WinGet и необходимые инструменты установлены/доступны

call :ENSURE_WINGET || (echo ERROR: WinGet not available. Install "App Installer" from the Microsoft Store and retry.& if "%SHOW_RU%"=="1" echo ОШИБКА: WinGet недоступен. Установите "App Installer" из Microsoft Store и повторите.& pause & exit /b 1)

echo Checking and installing prerequisites via WinGet...
if "%SHOW_RU%"=="1" echo Проверка и установка зависимостей через WinGet...

REM These variables may be filled by ENSURE_* with full paths
REM Эти переменные ENSURE_* может заполнить полными путями
set "CURL="
set "SEVENZIP="
set "SED="

call :ENSURE_CURL    || (echo ERROR: Failed to install/locate curl.& if "%SHOW_RU%"=="1" echo ОШИБКА: Не удалось установить/найти curl.& pause & exit /b 1)
call :ENSURE_7ZIP    || (echo ERROR: Failed to install/locate 7-Zip.& if "%SHOW_RU%"=="1" echo ОШИБКА: Не удалось установить/найти 7-Zip.& pause & exit /b 1)
call :ENSURE_SED     || (echo ERROR: Failed to install/locate sed.& if "%SHOW_RU%"=="1" echo ОШИБКА: Не удалось установить/найти sed.& pause & exit /b 1)

REM If ENSURE_* didn't set them, fall back to default names available in PATH
REM Если ENSURE_* их не выставили, использовать имена по умолчанию из PATH
if not defined CURL set "CURL=curl"
if not defined SEVENZIP set "SEVENZIP=7z"
if not defined SED set "SED=sed"

call :GET_ARGS %*
call :GET_PROXY
call :GET_ARCH

set "ESR_PRODUCT=firefox-esr-latest"

echo.
echo Building I2Pd Browser Portable
if "%SHOW_RU%"=="1" echo Сборка I2Pd Browser Portable
echo Browser locale: %locale%, architecture: %ARCH_DISPLAY%
if "%SHOW_RU%"=="1" echo Язык браузера: %locale%, архитектура: %ARCH_DISPLAY%
if "%xOS%"=="unsupported" (
  echo ERROR: Unsupported architecture (ARM not supported)
  if "%SHOW_RU%"=="1" echo ОШИБКА: Неподдерживаемая архитектура (ARM не поддерживается)
  if /i "%arg_skipwait%"=="yes" (
    exit /b 1
  ) else (
    pause & exit /b 1
  )
)

echo.
echo Updating Windows root certificates from CA bundle
if "%SHOW_RU%"=="1" echo Обновление корневых сертификатов Windows из пакета CA
set "CA_BUNDLE_URL=https://raw.githubusercontent.com/bagder/ca-bundle/master/ca-bundle.crt"
where certutil >nul 2>&1
if errorlevel 1 (
  echo WARNING: certutil.exe not found; skipping root certificate update.
  if "%SHOW_RU%"=="1" echo Предупреждение: certutil.exe не найден; пропускаем обновление корневых сертификатов.
) else (
  set "TMP_CA=%TEMP%\ca_bundle_%RANDOM%.crt"
  "%CURL%" -L -f -s -o "%TMP_CA%" "%CA_BUNDLE_URL%" %PROXY_ARGS%
  if errorlevel 1 (
    echo WARNING: Failed to download CA bundle; skipping root certificate update.
    if "%SHOW_RU%"=="1" echo Предупреждение: не удалось скачать пакет CA; пропускаем обновление корневых сертификатов.
    del /Q "%TMP_CA%" >nul 2>&1
  ) else (
    certutil -f -user -addstore Root "%TMP_CA%" >nul
    set "_CERTUTIL_RC=%ERRORLEVEL%"
    del /Q "%TMP_CA%" >nul 2>&1
    if not "%_CERTUTIL_RC%"=="0" (
      echo WARNING: certutil couldn't import CA bundle (rc=%_CERTUTIL_RC%). Continuing.
      if "%SHOW_RU%"=="1" echo Предупреждение: certutil не смог импортировать пакет CA (код=%_CERTUTIL_RC%). Продолжаем.
    ) else (
      echo Root certificates updated.
      if "%SHOW_RU%"=="1" echo Корневые сертификаты обновлены.
    )
    set "_CERTUTIL_RC="
  )
  set "TMP_CA="
)


echo.
echo Downloading Firefox ESR installer
if "%SHOW_RU%"=="1" echo Загрузка установщика Firefox ESR

REM Only win32/win64 builds are available (ARM is unsupported)
REM Доступны только сборки win32/win64 (ARM не поддерживается)
set "dl_os="
if /i "%xOS%"=="win32" set "dl_os=win32"
if /i "%xOS%"=="win64" set "dl_os=win64"
if not defined dl_os (
  echo ERROR: Unsupported architecture "%xOS%". Only win32/win64 are supported.
  if "%SHOW_RU%"=="1" echo ОШИБКА: Неподдерживаемая архитектура "%xOS%". Поддерживаются только win32/win64.
  pause & exit /b 1
)

REM Use Mozilla redirector to always get the latest ESR
REM Использовать редиректор Mozilla для получения последней ESR
set "FF_URL=https://download.mozilla.org/?product=%ESR_PRODUCT%&os=%dl_os%&lang=%locale%"
"%CURL%" -L -f -# -o firefox.exe "%FF_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR: Firefox download failed !ERRORLEVEL!
  if "%SHOW_RU%"=="1" echo ОШИБКА: Не удалось загрузить Firefox !ERRORLEVEL!
  pause & exit /b 1
) else (
  echo OK!
)

echo.
echo Unpacking the installer and deleting unnecessary files
if "%SHOW_RU%"=="1" echo Распаковка установщика и удаление ненужных файлов
"%SEVENZIP%" x -y -o..\Firefox\App firefox.exe >nul 2>&1
set "_7Z_RC=%ERRORLEVEL%"
del /Q firefox.exe >nul 2>&1
if not "%_7Z_RC%"=="0" (
  echo ERROR: 7-Zip failed to extract Firefox. rc=%_7Z_RC%
  if "%SHOW_RU%"=="1" echo ОШИБКА: 7-Zip не смог распаковать Firefox. код=%_7Z_RC%
  pause & exit /b 1
)

REM Remove unneeded files safely
REM Удалить лишние файлы безопасно
if exist "..\Firefox\App\setup.exe" del /Q "..\Firefox\App\setup.exe" >nul 2>&1
if exist "..\Firefox\App\core\browser\crashreporter-override.ini" del /Q "..\Firefox\App\core\browser\crashreporter-override.ini" >nul 2>&1
if exist "..\Firefox\App\core\browser\features\NUL" rmdir /S /Q "..\Firefox\App\core\browser\features" >nul 2>&1
if exist "..\Firefox\App\core\gmp-clearkey\NUL" rmdir /S /Q "..\Firefox\App\core\gmp-clearkey" >nul 2>&1
if exist "..\Firefox\App\core\uninstall\NUL" rmdir /S /Q "..\Firefox\App\core\uninstall" >nul 2>&1
if exist "..\Firefox\App\core\Accessible*.*" del /Q "..\Firefox\App\core\Accessible*.*" >nul 2>&1
if exist "..\Firefox\App\core\crashreporter.*" del /Q "..\Firefox\App\core\crashreporter.*" >nul 2>&1
if exist "..\Firefox\App\core\*.sig" del /Q "..\Firefox\App\core\*.sig" >nul 2>&1
if exist "..\Firefox\App\core\maintenanceservice*.*" del /Q "..\Firefox\App\core\maintenanceservice*.*" >nul 2>&1
if exist "..\Firefox\App\core\minidump-analyzer.exe" del /Q "..\Firefox\App\core\minidump-analyzer.exe" >nul 2>&1
if exist "..\Firefox\App\core\precomplete" del /Q "..\Firefox\App\core\precomplete" >nul 2>&1
if exist "..\Firefox\App\core\removed-files" del /Q "..\Firefox\App\core\removed-files" >nul 2>&1
if exist "..\Firefox\App\core\ucrtbase.dll" del /Q "..\Firefox\App\core\ucrtbase.dll" >nul 2>&1
if exist "..\Firefox\App\core\update*.*" del /Q "..\Firefox\App\core\update*.*" >nul 2>&1
if not exist "..\Firefox\App\core\browser\extensions\NUL" mkdir "..\Firefox\App\core\browser\extensions" >nul 2>&1
echo OK!

REM Read exact version from application.ini
REM Прочитать точную версию из application.ini
set "FF_VER="
if not exist "..\Firefox\App\core\application.ini" (
  echo ERROR: application.ini not found.
  if "%SHOW_RU%"=="1" echo ОШИБКА: application.ini не найден.
  pause & exit /b 1
)
for /f "usebackq tokens=2 delims==" %%v in (`findstr /b /i "Version=" "..\Firefox\App\core\application.ini"`) do set "FF_VER=%%v"
if not defined FF_VER (
  echo ERROR: Couldn't read Firefox version from application.ini
  if "%SHOW_RU%"=="1" echo ОШИБКА: Не удалось прочитать версию Firefox из application.ini
  pause & exit /b 1
)

echo.
echo Patching browser internal files to reduce external requests
if "%SHOW_RU%"=="1" echo Патчинг внутренних файлов браузера для отключения внешних запросов

set "_TMPDIR=..\Firefox\App\tmp"
if exist "!_TMPDIR!\NUL" rmdir /S /Q "!_TMPDIR!" >nul 2>&1
if exist "..\Firefox\App\core\omni.ja" (
  "%SEVENZIP%" -bso0 -y x "..\Firefox\App\core\omni.ja" -o"!_TMPDIR!" >nul 2>&1
  if errorlevel 1 (
    echo WARN: couldn't extract omni.ja
    if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: не удалось распаковать omni.ja
  ) else (
    set "SEARCHUTILS="
    for /r "!_TMPDIR!" %%F in (SearchUtils.sys.mjs) do (set "SEARCHUTILS=%%~fF" & goto :_SU_FOUND)
:_SU_FOUND
    if defined SEARCHUTILS (
      "%SED%" -i "s/https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1/http\:\/\/127\.0\.0\.1/" "!SEARCHUTILS!" >nul 2>&1
      if errorlevel 1 (
        echo WARN: patch 1 failed
        if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: патч 1 не применился
      ) else (
        echo Patched 1/2
        if "%SHOW_RU%"=="1" echo Патч 1/2
      )
    ) else (
      echo WARN: SearchUtils.sys.mjs not found
      if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: SearchUtils.sys.mjs не найден
    )

    set "APPCONST="
    for /r "!_TMPDIR!" %%F in (AppConstants.sys.mjs) do (set "APPCONST=%%~fF" & goto :_AC_FOUND)
:_AC_FOUND
    if defined APPCONST (
      "%SED%" -i "s/\"https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1\",$/\"\",/" "!APPCONST!" >nul 2>&1
      if errorlevel 1 (
        echo WARN: patch 2 failed
        if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: патч 2 не применился
      ) else (
        echo Patched 2/2
        if "%SHOW_RU%"=="1" echo Патч 2/2
      )
    ) else (
      echo WARN: AppConstants.sys.mjs not found
      if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: AppConstants.sys.mjs не найден
    )

    if exist "!_TMPDIR!\NUL" (
      if exist "..\Firefox\App\core\omni.ja" ren "..\Firefox\App\core\omni.ja" "omni.ja.bak" >nul 2>&1
      "%SEVENZIP%" a -mx0 -tzip "..\Firefox\App\core\omni.ja" -r "!_TMPDIR!\*" >nul 2>&1
      rmdir /S /Q "!_TMPDIR!" >nul 2>&1
      del /Q "..\Firefox\App\core\omni.ja.bak" >nul 2>&1
    )
  )
) else (
  echo WARN: omni.ja not found - skipping patches
  if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: omni.ja не найден - патчи пропущены
)
echo OK!

echo.
echo Downloading language packs
if "%SHOW_RU%"=="1" echo Загрузка языковых пакетов

REM Download RU langpack only if system locale is RU
REM Скачивать RU-пакет только если язык системы RU
set "XPI_BASE=https://releases.mozilla.org/pub/firefox/releases/%FF_VER%/%dl_os%/xpi"
if /i "%locale%"=="ru" (
  "%CURL%" -L -f -# -o "..\Firefox\App\core\browser\extensions\langpack-ru@firefox.mozilla.org.xpi" ^
    "%XPI_BASE%/ru.xpi" %PROXY_ARGS%
  if errorlevel 1 (echo ERROR:!ErrorLevel! & if "%SHOW_RU%"=="1" echo ОШИБКА:!ErrorLevel! & pause & exit /b 1) else echo OK!
  "%CURL%" -L -f -# -o "..\Firefox\App\core\browser\extensions\langpack-en-US@firefox.mozilla.org.xpi" ^
    "%XPI_BASE%/en-US.xpi" %PROXY_ARGS%
  if errorlevel 1 (echo ERROR:!ErrorLevel! & if "%SHOW_RU%"=="1" echo ОШИБКА:!ErrorLevel! & pause & exit /b 1) else echo OK!
)

REM Dictionaries (RU only if locale=ru; en-US generally useful)
REM Словари (RU только при locale=ru; en-US полезен всегда)
if /i "%locale%"=="ru" (
  "%CURL%" -L -f -# -o "..\Firefox\App\core\browser\extensions\ru@dictionaries.addons.mozilla.org.xpi" ^
    https://addons.mozilla.org/firefox/downloads/latest/russian-spellchecking-dic-3703/latest.xpi %PROXY_ARGS%
  if errorlevel 1 (echo ERROR:!ErrorLevel! & if "%SHOW_RU%"=="1" echo ОШИБКА:!ErrorLevel! & pause & exit /b 1) else echo OK!
)
"%CURL%" -L -f -# -o "..\Firefox\App\core\browser\extensions\en-US@dictionaries.addons.mozilla.org.xpi" ^
  https://addons.mozilla.org/firefox/downloads/latest/english-us-dictionary/latest.xpi %PROXY_ARGS%
if errorlevel 1 (echo ERROR:!ErrorLevel! & if "%SHOW_RU%"=="1" echo ОШИБКА:!ErrorLevel! & pause & exit /b 1) else echo OK!

echo.
echo Downloading NoScript extension
if "%SHOW_RU%"=="1" echo Загрузка дополнения NoScript
"%CURL%" -L -f -# -o "..\Firefox\App\core\browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi" ^
  https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi %PROXY_ARGS%
if errorlevel 1 (echo ERROR:!ErrorLevel! & if "%SHOW_RU%"=="1" echo ОШИБКА:!ErrorLevel! & pause & exit /b 1) else echo OK!

echo(
echo Disabling auto-updates via application.ini
if "%SHOW_RU%"=="1" echo Отключение автообновлений через application.ini
"%SED%" -i "s/Enabled=1/Enabled=0/g" "..\Firefox\App\core\application.ini" >nul 2>&1
if errorlevel 1 ( echo WARN: couldn't set Enabled=0 & if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: не удалось выставить Enabled=0 ) else ( echo OK! & if "%SHOW_RU%"=="1" echo ОК! )
"%SED%" -i "s/ServerURL=.*/ServerURL=-/" "..\Firefox\App\core\application.ini" >nul 2>&1
if errorlevel 1 ( echo WARN: couldn't blank ServerURL & if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: не удалось очистить ServerURL ) else ( echo OK! & if "%SHOW_RU%"=="1" echo ОК! )

echo.
echo Copying Firefox launcher and settings
if "%SHOW_RU%"=="1" echo Копирование файлов настроек Firefox
mkdir "..\Firefox\App\DefaultData\profile\" >nul 2>&1
xcopy /E /Y "profile\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
if /i "%locale%"=="ru" (
  if exist "profile-ru\*" copy /Y "profile-ru\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
) else (
  if exist "profile-en\*" copy /Y "profile-en\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
)
if exist "firefox-portable\*" copy /Y "firefox-portable\*" "..\Firefox\" >nul 2>&1
if exist "preferences\*" xcopy /E /Y "preferences\*" "..\Firefox\App\core\" >nul 2>&1
echo OK!

echo.
echo Locating and downloading I2Pd
if "%SHOW_RU%"=="1" echo Поиск и загрузка I2Pd
set "I2PD_URL="
set "TMP_JSON=%TEMP%\i2pd_latest_%RANDOM%.json"

REM Query GitHub API for latest release JSON
REM Запрашиваем JSON последнего релиза у GitHub API
"%CURL%" -L -f -s -o "%TMP_JSON%" "https://api.github.com/repos/PurpleI2P/i2pd/releases/latest" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:!ErrorLevel!
  if "%SHOW_RU%"=="1" echo ОШИБКА:!ErrorLevel!
  del /Q "%TMP_JSON%" >nul 2>&1
  pause & exit /b 1
)

REM Resolve asset URL via dedicated PowerShell helper
REM Разрешить URL ассета с помощью вспомогательного PowerShell-скрипта
for /f "usebackq delims=" %%U in (`
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-I2pdAssetUrl.ps1" -JsonPath "%TMP_JSON%" -OsTag "%xOS%"
`) do set "I2PD_URL=%%U"
del /Q "%TMP_JSON%" >nul 2>&1

if not defined I2PD_URL (
  echo ERROR: couldn't resolve i2pd asset URL from GitHub API
  if "%SHOW_RU%"=="1" echo ОШИБКА: не удалось получить ссылку i2pd из GitHub API
  pause & exit /b 1
)

"%CURL%" -L -f -# -OJ "%I2PD_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:!ErrorLevel!
  if "%SHOW_RU%"=="1" echo ОШИБКА:!ErrorLevel!
  pause & exit /b 1
) else (
  echo OK!
)

REM Find the just-downloaded archive and extract i2pd.exe
REM Находим скачанный архив и извлекаем i2pd.exe
set "I2PD_ZIP="
for %%F in (i2pd*_%xOS%_mingw.zip) do set "I2PD_ZIP=%%~nxF"
if not defined I2PD_ZIP (
  echo ERROR: i2pd zip not found after download
  if "%SHOW_RU%"=="1" echo ОШИБКА: архив i2pd не найден после загрузки
  pause & exit /b 1
)
"%SEVENZIP%" x -y -o"..\i2pd" "!I2PD_ZIP!" i2pd.exe >nul 2>&1
set "_7Z_RC=%ERRORLEVEL%"
del /Q "!I2PD_ZIP!" >nul 2>&1
if not "%_7Z_RC%"=="0" (
  echo ERROR: 7-Zip failed to extract i2pd.exe. rc=%_7Z_RC%
  if "%SHOW_RU%"=="1" echo ОШИБКА: 7-Zip не смог извлечь i2pd.exe. код=%_7Z_RC%
  pause & exit /b 1
)

REM Optionally overlay local i2pd configs if present
REM При наличии — скопировать локальные конфиги i2pd
if exist "i2pd\NUL" xcopy /E /I /Y "i2pd" "..\i2pd" >nul 2>&1

echo.
echo I2Pd Browser Portable is ready to start!
if "%SHOW_RU%"=="1" echo I2Pd Browser Portable готов к запуску!
if not defined arg_skipwait pause
exit /b

:ENSURE_WINGET
REM Verify WinGet (Windows 10 1809+ / Windows 11)
REM Проверить WinGet (Windows 10 1809+ / Windows 11)
where winget >nul 2>&1 && exit /b 0
exit /b 1

:ENSURE_CURL
REM curl ships with Windows 10+, but try installing if missing
REM curl входит в состав Windows 10+, но при отсутствии попробуем установить
where curl >nul 2>&1 && (set "CURL=curl" & exit /b 0)
echo Installing curl via WinGet...
if "%SHOW_RU%"=="1" echo Установка curl через WinGet...
winget install -e --id cURL.cURL --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
where curl >nul 2>&1 && (set "CURL=curl" & exit /b 0)
if exist "%SystemRoot%\System32\curl.exe" set "CURL=%SystemRoot%\System32\curl.exe" & exit /b 0
for /f "delims=" %%F in ('dir /b /s "%LocalAppData%\Microsoft\WinGet\Packages\cURL.cURL_*\\curl.exe" 2^>nul') do (
  set "CURL=%%~fF"
  exit /b 0
)
exit /b 1

:ENSURE_7ZIP
REM Ensure 7-Zip CLI is available
REM Убедиться, что доступен 7-Zip (CLI)
where 7z >nul 2>&1 && (set "SEVENZIP=7z" & exit /b 0)
echo Installing 7-Zip via WinGet...
if "%SHOW_RU%"=="1" echo Установка 7-Zip через WinGet...
winget install -e --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
set "_SEVENZIP_EXE="
if exist "%ProgramFiles%\7-Zip\7z.exe" set "_SEVENZIP_EXE=%ProgramFiles%\7-Zip\7z.exe"
if not defined _SEVENZIP_EXE if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" set "_SEVENZIP_EXE=%ProgramFiles(x86)%\7-Zip\7z.exe"
if defined _SEVENZIP_EXE (
  set "SEVENZIP=%_SEVENZIP_EXE%"
  exit /b 0
)
where 7z >nul 2>&1 && (set "SEVENZIP=7z" & exit /b 0)
for /f "delims=" %%F in ('dir /b /s "%LocalAppData%\Microsoft\WinGet\Packages\7zip.7zip*\\7z.exe" 2^>nul') do (
  set "SEVENZIP=%%~fF"
  exit /b 0
)
exit /b 1

:ENSURE_SED
REM Ensure GNU sed is available
REM Убедиться, что доступен GNU sed
where sed >nul 2>&1 && (set "SED=sed" & exit /b 0)
echo Installing sed via WinGet...
if "%SHOW_RU%"=="1" echo Установка sed через WinGet...
winget install -e --id mbuilov.sed --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
where sed >nul 2>&1 && (set "SED=sed" & exit /b 0)
winget install -e --id GnuWin32.Sed --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
where sed >nul 2>&1 && (set "SED=sed" & exit /b 0)
set "_SED_EXE="
if exist "%ProgramFiles(x86)%\GnuWin32\bin\sed.exe" set "_SED_EXE=%ProgramFiles(x86)%\GnuWin32\bin\sed.exe"
if not defined _SED_EXE if exist "%ProgramFiles%\Git\usr\bin\sed.exe" set "_SED_EXE=%ProgramFiles%\Git\usr\bin\sed.exe"
if defined _SED_EXE (
  set "SED=%_SED_EXE%"
  exit /b 0
)
for /f "delims=" %%F in ('dir /b /s "%LocalAppData%\Microsoft\WinGet\Packages\mbuilov.sed*\\sed.exe" 2^>nul') do (
  set "SED=%%~fF"
  exit /b 0
)
exit /b 1

:GET_PROXY
REM Use system proxy if enabled (robust parsing; avoids "<local>" issues)
REM Использовать системный прокси, если включен (устойчивый разбор; без проблем с "<local>")
set "PROXY_ARGS="
set "ProxyEnable="
set "ProxyServer="
set "REG_PROXY=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings"

REM Read ProxyEnable (REG_DWORD -> 0x0 or 0x1)
REM Читаем ProxyEnable (REG_DWORD -> 0x0 или 0x1)
for /f "skip=2 tokens=3" %%A in ('
  reg query "%REG_PROXY%" /v ProxyEnable 2^>nul
') do set "ProxyEnable=%%A"

REM Read ProxyServer (REG_SZ, may contain semicolons)
REM Читаем ProxyServer (REG_SZ, может содержать точки с запятыми)
for /f "skip=2 tokens=2,*" %%A in ('
  reg query "%REG_PROXY%" /v ProxyServer 2^>nul
') do set "ProxyServer=%%B"

if /i "%ProxyEnable%"=="0x1" if defined ProxyServer (
  set "PROXY_ARGS=-x %ProxyServer%"
)
exit /b 0

:GET_ARCH
REM Detect architecture (mark any ARM as unsupported)
REM Определить архитектуру (любой ARM не поддерживается)
set "HOST_ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "HOST_ARCH=%PROCESSOR_ARCHITEW6432%"
if not defined HOST_ARCH set "HOST_ARCH=x86"

set "xOS=win32"
if /i "%HOST_ARCH%"=="AMD64" set "xOS=win64"
if /i "%HOST_ARCH%"=="X64" set "xOS=win64"

set "ARCH_UNSUPPORTED="
if /i "%HOST_ARCH%"=="ARM" set "ARCH_UNSUPPORTED=1"
if /i "%HOST_ARCH%"=="ARM64" set "ARCH_UNSUPPORTED=1"
if /i "%HOST_ARCH%"=="AARCH64" set "ARCH_UNSUPPORTED=1"
if /i "%HOST_ARCH%"=="IA64" set "ARCH_UNSUPPORTED=1"

if defined ARCH_UNSUPPORTED set "xOS=unsupported"

set "ARCH_DISPLAY=%xOS%"
if /i "%HOST_ARCH%"=="AMD64" (
  if /i "%xOS%"=="win64" (
    rem display already matches; no suffix
  ) else (
    set "ARCH_DISPLAY=%xOS% (host %HOST_ARCH%)"
  )
) else (
  if /i "%HOST_ARCH%"=="X86" (
    if /i "%xOS%"=="win32" (
      rem display already matches; no suffix
    ) else (
      set "ARCH_DISPLAY=%xOS% (host %HOST_ARCH%)"
    )
  ) else (
    set "ARCH_DISPLAY=%xOS% (host %HOST_ARCH%)"
  )
)
exit /b 0

:GET_ARGS
REM Option: --skipwait to avoid the final pause
REM Опция: --skipwait, чтобы избежать финальной паузы
set "arg_skipwait="
if "%~1"=="" exit /b 0
for %%a in (%*) do (
  if "%%a"=="--skipwait" set "arg_skipwait=yes"
)
exit /b 0
