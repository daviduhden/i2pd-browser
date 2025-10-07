@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM Авторские права (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM Этот файл — часть проекта Purple i2pd и распространяется по BSD3
REM See full license text in LICENSE file at top of project tree
REM Полный текст лицензии см. в файле LICENSE в корне проекта

setlocal enableextensions enabledelayedexpansion

REM ------------------------------------------------
REM Detect locale (user UI language) -> ru or en-US
REM Определить язык интерфейса пользователя -> ru или en-US
REM ------------------------------------------------
set "locale=en-US"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Control Panel\International" /v LocaleName ^| find "LocaleName"') do set "_loc=%%B"
if defined _loc (
  set "_loc=!_loc:~0,2!"
  if /i "!_loc!"=="ru" set "locale=ru"
)

REM Flag to show Russian (only when locale=ru)
REM Флаг показа русского (только при locale=ru)
set "SHOW_RU=0"
if /i "%locale%"=="ru" set "SHOW_RU=1"

REM Switch to UTF-8 only when printing Russian (avoid mojibake)
REM Включать UTF-8 только при печати русского (чтобы избежать кракозябр)
if "%SHOW_RU%"=="1" chcp 65001 >nul

REM ------------------------------------------------
REM Ensure WinGet and required tools are installed/available
REM Убедиться, что WinGet и необходимые инструменты установлены/доступны
REM ------------------------------------------------
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
echo Browser locale: %locale%, architecture: %xOS%
if "%SHOW_RU%"=="1" echo Язык браузера: %locale%, архитектура: %xOS%

echo.
echo Downloading Firefox ESR installer
if "%SHOW_RU%"=="1" echo Загрузка установщика Firefox ESR

REM Only win32/win64 are supported
REM Поддерживаются только win32/win64
if /i "%xOS%"=="win32" (
  set "dl_os=win32"
) else if /i "%xOS%"=="win64" (
  set "dl_os=win64"
) else (
  echo ERROR: Unsupported architecture "%xOS%". Only win32/win64 are supported.
  if "%SHOW_RU%"=="1" echo ОШИБКА: Неподдерживаемая архитектура "%xOS%". Поддерживаются только win32/win64.
  pause & exit /b 1
)

REM Use Mozilla redirector to always get the latest ESR
REM Использовать редиректор Mozilla для получения последней ESR
set "FF_URL=https://download.mozilla.org/?product=%ESR_PRODUCT%&os=%dl_os%&lang=%locale%"
"%CURL%" -L -f -# -o firefox.exe "%FF_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR: Firefox download failed (%ErrorLevel%).
  if "%SHOW_RU%"=="1" echo ОШИБКА: Не удалось загрузить Firefox (%ErrorLevel%).
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
  echo ERROR: 7-Zip failed to extract Firefox (rc=%_7Z_RC%).
  if "%SHOW_RU%"=="1" echo ОШИБКА: 7-Zip не смог распаковать Firefox (код=%_7Z_RC%).
  pause & exit /b 1
)

REM Some ESR builds unpack to \core, some directly to \Firefox. Normalize to \Firefox.
REM В некоторых ESR – папка \core, в других сразу \Firefox. Привести к \Firefox.
if exist "..\Firefox\App\core\NUL" (
  ren "..\Firefox\App\core" "Firefox" >nul 2>&1
) else (
  if not exist "..\Firefox\App\Firefox\NUL" (
    echo ERROR: Neither "core" nor "Firefox" folder exists after extraction.
    if "%SHOW_RU%"=="1" echo ОШИБКА: После распаковки нет папки "core" или "Firefox".
    pause & exit /b 1
  )
)

REM Remove unneeded files safely
REM Удалить лишние файлы безопасно
if exist "..\Firefox\App\setup.exe" del /Q "..\Firefox\App\setup.exe" >nul 2>&1
if exist "..\Firefox\App\Firefox\browser\crashreporter-override.ini" del /Q "..\Firefox\App\Firefox\browser\crashreporter-override.ini" >nul 2>&1
if exist "..\Firefox\App\Firefox\browser\features\NUL" rmdir /S /Q "..\Firefox\App\Firefox\browser\features" >nul 2>&1
if exist "..\Firefox\App\Firefox\gmp-clearkey\NUL" rmdir /S /Q "..\Firefox\App\Firefox\gmp-clearkey" >nul 2>&1
if exist "..\Firefox\App\Firefox\uninstall\NUL" rmdir /S /Q "..\Firefox\App\Firefox\uninstall" >nul 2>&1
if exist "..\Firefox\App\Firefox\Accessible*.*" del /Q "..\Firefox\App\Firefox\Accessible*.*" >nul 2>&1
if exist "..\Firefox\App\Firefox\crashreporter.*" del /Q "..\Firefox\App\Firefox\crashreporter.*" >nul 2>&1
if exist "..\Firefox\App\Firefox\*.sig" del /Q "..\Firefox\App\Firefox\*.sig" >nul 2>&1
if exist "..\Firefox\App\Firefox\maintenanceservice*.*" del /Q "..\Firefox\App\Firefox\maintenanceservice*.*" >nul 2>&1
if exist "..\Firefox\App\Firefox\minidump-analyzer.exe" del /Q "..\Firefox\App\Firefox\minidump-analyzer.exe" >nul 2>&1
if exist "..\Firefox\App\Firefox\precomplete" del /Q "..\Firefox\App\Firefox\precomplete" >nul 2>&1
if exist "..\Firefox\App\Firefox\removed-files" del /Q "..\Firefox\App\Firefox\removed-files" >nul 2>&1
if exist "..\Firefox\App\Firefox\ucrtbase.dll" del /Q "..\Firefox\App\Firefox\ucrtbase.dll" >nul 2>&1
if exist "..\Firefox\App\Firefox\update*.*" del /Q "..\Firefox\App\Firefox\update*.*" >nul 2>&1
if not exist "..\Firefox\App\Firefox\browser\extensions\NUL" mkdir "..\Firefox\App\Firefox\browser\extensions" >nul 2>&1
echo OK!

REM Read exact version from application.ini
REM Прочитать точную версию из application.ini
set "FF_VER="
if not exist "..\Firefox\App\Firefox\application.ini" (
  echo ERROR: application.ini not found.
  if "%SHOW_RU%"=="1" echo ОШИБКА: application.ini не найден.
  pause & exit /b 1
)
for /f "usebackq tokens=2 delims==" %%v in (`findstr /b /i "Version=" "..\Firefox\App\Firefox\application.ini"`) do set "FF_VER=%%v"
if not defined FF_VER (
  echo ERROR: Couldn't read Firefox version from application.ini
  if "%SHOW_RU%"=="1" echo ОШИБКА: Не удалось прочитать версию Firefox из application.ini
  pause & exit /b 1
)
set "XPI_BASE=https://releases.mozilla.org/pub/firefox/releases/%FF_VER%/%dl_os%/xpi"

echo.
echo Patching browser internal files to reduce external requests
if "%SHOW_RU%"=="1" echo Патчинг внутренних файлов браузера для отключения внешних запросов

set "_TMPDIR=..\Firefox\App\tmp"
if exist "!_TMPDIR!\NUL" rmdir /S /Q "!_TMPDIR!" >nul 2>&1
if exist "..\Firefox\App\Firefox\omni.ja" (
  "%SEVENZIP%" -bso0 -y x "..\Firefox\App\Firefox\omni.ja" -o"!_TMPDIR!" >nul 2>&1
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
      if exist "..\Firefox\App\Firefox\omni.ja" ren "..\Firefox\App\Firefox\omni.ja" "omni.ja.bak" >nul 2>&1
      "%SEVENZIP%" a -mx0 -tzip "..\Firefox\App\Firefox\omni.ja" -r "!_TMPDIR!\*" >nul 2>&1
      rmdir /S /Q "!_TMPDIR!" >nul 2>&1
      del /Q "..\Firefox\App\Firefox\omni.ja.bak" >nul 2>&1
    )
  )
) else (
  echo WARN: omni.ja not found (skipping patches)
  if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: omni.ja не найден (патчи пропущены)
)
echo OK!

echo.
echo Downloading language packs
if "%SHOW_RU%"=="1" echo Загрузка языковых пакетов

REM Download RU langpack only if system locale is RU
REM Скачивать RU-пакет только если язык системы RU
if /i "%locale%"=="ru" (
  "%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\langpack-ru@firefox.mozilla.org.xpi" ^
    "%XPI_BASE%/ru.xpi" %PROXY_ARGS%
  if errorlevel 1 (echo ERROR:%ErrorLevel% & if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel% & pause & exit /b 1) else echo OK!
  "%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\langpack-en-US@firefox.mozilla.org.xpi" ^
    "%XPI_BASE%/en-US.xpi" %PROXY_ARGS%
  if errorlevel 1 (echo ERROR:%ErrorLevel% & if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel% & pause & exit /b 1) else echo OK!
)

REM Dictionaries (RU only if locale=ru; en-US generally useful)
REM Словари (RU только при locale=ru; en-US полезен всегда)
if /i "%locale%"=="ru" (
  "%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\ru@dictionaries.addons.mozilla.org.xpi" ^
    https://addons.mozilla.org/firefox/downloads/latest/russian-spellchecking-dic-3703/latest.xpi %PROXY_ARGS%
  if errorlevel 1 (echo ERROR:%ErrorLevel% & if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel% & pause & exit /b 1) else echo OK!
)
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\en-US@dictionaries.addons.mozilla.org.xpi" ^
  https://addons.mozilla.org/firefox/downloads/latest/english-us-dictionary/latest.xpi %PROXY_ARGS%
if errorlevel 1 (echo ERROR:%ErrorLevel% & if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel% & pause & exit /b 1) else echo OK!

echo.
echo Downloading NoScript extension
if "%SHOW_RU%"=="1" echo Загрузка дополнения NoScript
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi" ^
  https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi %PROXY_ARGS%
if errorlevel 1 (echo ERROR:%ErrorLevel% & if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel% & pause & exit /b 1) else echo OK!

echo.
echo Disabling auto-updates via application.ini
if "%SHOW_RU%"=="1" echo Отключение автообновлений через application.ini
"%SED%" -i "s/Enabled=1/Enabled=0/g" "..\Firefox\App\Firefox\application.ini" >nul 2>&1
if errorlevel 1 ( echo WARN: couldn't set Enabled=0 & if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: не удалось выставить Enabled=0 ) else ( echo OK! & if "%SHOW_RU%"=="1" echo ОК! )
"%SED%" -i "s/ServerURL=.*/ServerURL=-/" "..\Firefox\App\Firefox\application.ini" >nul 2>&1
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
copy /Y "firefox-portable\*" "..\Firefox\" >nul 2>&1
xcopy /E /Y "preferences\*" "..\Firefox\App\Firefox\" >nul 2>&1
echo OK!

echo.
echo Downloading I2Pd
if "%SHOW_RU%"=="1" echo Загрузка I2Pd
set "I2PD_URL="
set "TMP_HTML=%TEMP%\i2pd_latest_%RANDOM%.html"

REM --- HTML scraping of the latest release page
REM --- Парсинг HTML страницы последнего релиза
"%CURL%" -L -f -s -o "%TMP_HTML%" "https://github.com/PurpleI2P/i2pd/releases/latest" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  del /Q "%TMP_HTML%" >nul 2>&1
  pause & exit /b 1
)

for /f "usebackq delims=" %%L in ("%TMP_HTML%") do (
  set "L=%%L"
  echo !L!| findstr /i "/PurpleI2P/i2pd/releases/download/" >nul
  if not errorlevel 1 (
    echo !L!| findstr /i "_%xOS%_mingw.zip" >nul
    if not errorlevel 1 (
      echo !L!| findstr /i "i2pd_" >nul
      if not errorlevel 1 (
        REM Carefully strip up to href=" and capture the URL before next quote
        REM Аккуратно срезать до href=" и взять URL до следующей кавычки
        set "R=!L:*href^"=!"
        for /f tokens^=1^ delims^=^" %%U in ("!R!") do set "REL=%%U"
        set "I2PD_URL=https://github.com!REL!"
        goto :_I2PD_FOUND
      )
    )
  )
)
:_I2PD_FOUND
del /Q "%TMP_HTML%" >nul 2>&1

if not defined I2PD_URL (
  echo ERROR: couldn't resolve i2pd asset URL
  if "%SHOW_RU%"=="1" echo ОШИБКА: не удалось найти ссылку на релиз i2pd
  pause & exit /b 1
)

"%CURL%" -L -f -# -OJ "%I2PD_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  pause & exit /b 1
) else (
  echo OK!
)

REM Find the just-downloaded archive and extract i2pd.exe
REM Найти скачанный архив и извлечь i2pd.exe
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
  echo ERROR: 7-Zip failed to extract i2pd.exe (rc=%_7Z_RC%).
  if "%SHOW_RU%"=="1" echo ОШИБКА: 7-Zip не смог извлечь i2pd.exe (код=%_7Z_RC%).
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
REM Use system proxy if enabled
REM Использовать системный прокси, если включен
set "PROXY_ARGS="
set "REG_PROXY=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings"
for /F "Tokens=1,3" %%i in ('reg query "%REG_PROXY%"^|find "Proxy"') do set %%i=%%j
if "%ProxyEnable%"=="0x1" set "PROXY_ARGS=-x %ProxyServer%"
exit /b 0

:GET_ARCH
REM Detect architecture (ARM unsupported)
REM Определить архитектуру (ARM не поддерживается)
set "xOS=win32"
REM 64-bit WoW64 or native AMD64 -> win64
if defined PROCESSOR_ARCHITEW6432 set "xOS=win64"
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "xOS=win64"
REM ARM64 explicitly marked unsupported
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "xOS=unsupported"
exit /b 0

:GET_ARGS
REM Option: --skipwait to avoid the final pause
REM Опция: --skipwait, чтобы избежать финальной паузы
set arg_skipwait=
for %%a in (%*) do (
  if "%%a"=="--skipwait" set arg_skipwait=yes
)
exit /b 0