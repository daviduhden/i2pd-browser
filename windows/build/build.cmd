@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM Авторские права (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM Этот файл — часть проекта Purple i2pd и распространяется по BSD3
REM See full license text in LICENSE file at top of project tree
REM Полный текст лицензии см. в файле LICENSE в корне проекта

setlocal enableextensions enabledelayedexpansion

REM Ensure WinGet and required tools (curl, 7-Zip, sed) are installed
REM Убедиться, что WinGet и нужные инструменты (curl, 7-Zip, sed) установлены
call :ENSURE_WINGET || (echo ERROR: WinGet not available. Install "App Installer" from Microsoft Store and retry.& echo ОШИБКА: WinGet недоступен. Установите "App Installer" из Microsoft Store и повторите.& pause & exit /b 1)

echo Checking and installing prerequisites via WinGet...
echo Проверка и установка зависимостей через WinGet...

call :ENSURE_CURL    || (echo ERROR: Failed to install/locate curl.& echo ОШИБКА: Не удалось установить/найти curl.& pause & exit /b 1)
call :ENSURE_7ZIP    || (echo ERROR: Failed to install/locate 7-Zip.& echo ОШИБКА: Не удалось установить/найти 7-Zip.& pause & exit /b 1)
call :ENSURE_SED     || (echo ERROR: Failed to install/locate sed.& echo ОШИБКА: Не удалось установить/найти sed.& pause & exit /b 1)

set "CURL=curl"
set "SEVENZIP=%_SEVENZIP_EXE%"
if not defined SEVENZIP set "SEVENZIP=7z"
set "SED=%_SED_EXE%"
if not defined SED set "SED=sed"

call :GET_ARGS %*
call :GET_LOCALE
call :GET_PROXY
call :GET_ARCH

set "ESR_PRODUCT=firefox-esr-latest"

echo Building I2Pd Browser Portable
echo Сборка I2Pd Browser Portable
echo Browser locale: %locale%, architecture: %xOS%
echo Язык браузера: %locale%, архитектура: %xOS%
echo.
echo Downloading Firefox ESR installer
echo Загрузка установщика Firefox ESR

if /i "%xOS%"=="win32" (
  set "dl_os=win32"
) else if /i "%xOS%"=="win64" (
  set "dl_os=win64"
) else if /i "%xOS%"=="winarm" (
  set "dl_os=win64-aarch64"
) else (
  echo ERROR: Unknown architecture "%xOS%"
  echo ОШИБКА: Неизвестная архитектура "%xOS%"
  pause & exit /b 1
)

REM Use Mozilla redirector to always get latest ESR
REM Используйте редиректор Mozilla для получения последней ESR
set "FF_URL=https://download.mozilla.org/?product=%ESR_PRODUCT%&os=%dl_os%&lang=%locale%"
"%CURL%" -L -f -# -o firefox.exe "%FF_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

echo.
echo Unpacking the installer and deleting unnecessary files
echo Распаковка установщика и удаление ненужных файлов
"%SEVENZIP%" x -y -o..\Firefox\App firefox.exe >nul
del /Q firefox.exe
ren ..\Firefox\App\core Firefox
del /Q ..\Firefox\App\setup.exe
del /Q ..\Firefox\App\Firefox\browser\crashreporter-override.ini
rmdir /S /Q ..\Firefox\App\Firefox\browser\features
rmdir /S /Q ..\Firefox\App\Firefox\gmp-clearkey
rmdir /S /Q ..\Firefox\App\Firefox\uninstall
del /Q "..\Firefox\App\Firefox\Accessible*.*"
REM Do NOT delete application.ini; needed to read version and disable updates
REM Не удаляйте application.ini; нужен для чтения версии и отключения обновлений
REM del /Q ..\Firefox\App\Firefox\application.ini
del /Q ..\Firefox\App\Firefox\crashreporter.*
del /Q ..\Firefox\App\Firefox\*.sig
del /Q ..\Firefox\App\Firefox\maintenanceservice*.*
del /Q ..\Firefox\App\Firefox\minidump-analyzer.exe
del /Q ..\Firefox\App\Firefox\precomplete
del /Q ..\Firefox\App\Firefox\removed-files
del /Q ..\Firefox\App\Firefox\ucrtbase.dll
del /Q ..\Firefox\App\Firefox\update*.*
mkdir ..\Firefox\App\Firefox\browser\extensions >nul
echo OK!

REM Read exact version from application.ini
REM Прочитать точную версию из application.ini
set "FF_VER="
for /f "usebackq tokens=2 delims==" %%v in (`findstr /b /i "Version=" "..\Firefox\App\Firefox\application.ini"`) do set "FF_VER=%%v"
if not defined FF_VER (
  echo ERROR: Couldn't read Firefox version from application.ini
  echo ОШИБКА: Не удалось прочитать версию Firefox из application.ini
  pause & exit /b
)
set "XPI_BASE=https://releases.mozilla.org/pub/firefox/releases/%FF_VER%/%dl_os%/xpi"

echo.
echo Patching browser internal files to reduce external requests
echo Патчинг внутренних файлов браузера для отключения внешних запросов
"%SEVENZIP%" -bso0 -y x ..\Firefox\App\Firefox\omni.ja -o..\Firefox\App\tmp >nul 2>&1
"%SED%" -i "s/https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1/http\:\/\/127\.0\.0\.1/" ..\Firefox\App\tmp\moz-src\toolkit\components\search\SearchUtils.sys.mjs
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo Patched 1/2
  echo Патч 1/2
)
"%SED%" -i "s/\"https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1\",$/\"\",/" ..\Firefox\App\tmp\modules\AppConstants.sys.mjs
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo Patched 2/2
  echo Патч 2/2
)

ren ..\Firefox\App\Firefox\omni.ja omni.ja.bak
"%SEVENZIP%" a -mx0 -tzip ..\Firefox\App\Firefox\omni.ja -r ..\Firefox\App\tmp\* >nul
rmdir /S /Q ..\Firefox\App\tmp
del ..\Firefox\App\Firefox\omni.ja.bak
echo OK!

echo.
echo Downloading language packs
echo Загрузка языковых пакетов

REM Always add RU to allow switching from EN
REM Всегда добавляйте RU для возможности переключения с EN
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\langpack-ru@firefox.mozilla.org.xpi ^
  "%XPI_BASE%/ru.xpi"
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

REM Add en-US only if base build is RU (en-US build doesn't need en-US langpack)
REM Добавлять en-US только если базовая сборка RU (en-US не нужен для en-US)
if /i "%locale%"=="ru" (
  "%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\langpack-en-US@firefox.mozilla.org.xpi ^
    "%XPI_BASE%/en-US.xpi"
  if errorlevel 1 (
    echo ERROR:%ErrorLevel%
    echo ОШИБКА:%ErrorLevel%
    pause & exit
  ) else (
    echo OK!
  )
)

REM Dictionaries / Словари
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\ru@dictionaries.addons.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/russian-spellchecking-dic-3703/latest.xpi
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\en-US@dictionaries.addons.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/english-us-dictionary/latest.xpi
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

echo.
echo Downloading NoScript extension
echo Загрузка дополнения NoScript
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

echo.
echo Disabling auto-updates via application.ini
echo Отключение автообновлений через application.ini
"%SED%" -i "s/Enabled=1/Enabled=0/g" "..\Firefox\App\Firefox\application.ini"
if errorlevel 1 ( echo WARN: couldn't set Enabled=0 & echo ВНИМАНИЕ: не удалось выставить Enabled=0 ) else ( echo OK! & echo ОК! )
"%SED%" -i "s/ServerURL=.*/ServerURL=-/" "..\Firefox\App\Firefox\application.ini"
if errorlevel 1 ( echo WARN: couldn't blank ServerURL & echo ВНИМАНИЕ: не удалось очистить ServerURL ) else ( echo OK! & echo ОК! )

echo.
echo Copying Firefox launcher and settings
echo Копирование файлов настроек Firefox
mkdir ..\Firefox\App\DefaultData\profile\ >nul
xcopy /E /Y profile\* ..\Firefox\App\DefaultData\profile\ >nul
if /i "%locale%"=="ru" (
  copy /Y profile-ru\* ..\Firefox\App\DefaultData\profile\ >nul
) else (
  copy /Y profile-en\* ..\Firefox\App\DefaultData\profile\ >nul
)
copy /Y firefox-portable\* ..\Firefox\ >nul
xcopy /E /Y preferences\* ..\Firefox\App\Firefox\ >nul
echo OK!

echo.
echo Downloading I2Pd
echo Загрузка I2Pd
set "I2PD_URL="
set "TMP_HTML=%TEMP%\i2pd_latest_%RANDOM%.html"
"%CURL%" -L -f -s -o "%TMP_HTML%" "https://github.com/PurpleI2P/i2pd/releases/latest"
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
)

for /f "usebackq delims=" %%L in ("%TMP_HTML%") do (
  set "L=%%L"
  echo !L!| findstr /i "/PurpleI2P/i2pd/releases/download/" >nul
  if not errorlevel 1 (
    echo !L!| findstr /i "_%xOS%_mingw.zip" >nul
    if not errorlevel 1 (
      echo !L!| findstr /i "i2pd_" >nul
      if not errorlevel 1 (
        set "R=!L:*href=\"=!"
        for /f "tokens=1 delims=\"" %%U in ("!R!") do set "REL=%%U"
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
  echo ОШИБКА: не удалось найти ссылку на релиз i2pd
  pause & exit
)

"%CURL%" -L -f -# -O "%I2PD_URL%"
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ОШИБКА:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

"%SEVENZIP%" x -y -o..\i2pd "%~nxI2PD_URL%" i2pd.exe >nul
del /Q "%~nxI2PD_URL%"
xcopy /E /I /Y i2pd ..\i2pd >nul

echo.
echo I2Pd Browser Portable is ready to start!
echo I2Pd Browser Portable готов к запуску!
if not defined arg_skipwait pause
exit /b

:ENSURE_WINGET
REM Verify WinGet is available (requires Windows 10 1809+ / Windows 11)
REM Проверка наличия WinGet (требуется Windows 10 1809+ / Windows 11)
where winget >nul 2>&1 && exit /b 0
exit /b 1

:ENSURE_CURL
REM Ensure curl is installed or available (Windows 10+ ships curl.exe)
REM Убедиться, что curl установлен или доступен (в Windows 10+ уже есть curl.exe)
where curl >nul 2>&1 && exit /b 0
echo Installing curl via WinGet...
echo Установка curl через WinGet...
winget install -e --id cURL.cURL --silent --accept-package-agreements --accept-source-agreements
where curl >nul 2>&1 && exit /b 0
REM Try common locations if PATH not refreshed
if exist "%SystemRoot%\System32\curl.exe" set "PATH=%SystemRoot%\System32;%PATH%" & exit /b 0
for /f "delims=" %%F in ('dir /b /s "%LocalAppData%\Microsoft\WinGet\Packages\cURL.cURL_*\\curl.exe" 2^>nul') do (
  set "PATH=%%~dpF;%PATH%"
  exit /b 0
)
exit /b 1

:ENSURE_7ZIP
REM Ensure 7-Zip CLI is installed and resolvable
REM Убедиться, что установлен 7-Zip (CLI) и доступен
where 7z >nul 2>&1 && exit /b 0
echo Installing 7-Zip via WinGet...
echo Установка 7-Zip через WinGet...
winget install -e --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements
REM Locate 7z.exe even if PATH wasn't updated
set "_SEVENZIP_EXE="
if exist "%ProgramFiles%\7-Zip\7z.exe" set "_SEVENZIP_EXE=%ProgramFiles%\7-Zip\7z.exe"
if not defined _SEVENZIP_EXE if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" set "_SEVENZIP_EXE=%ProgramFiles(x86)%\7-Zip\7z.exe"
if defined _SEVENZIP_EXE exit /b 0
where 7z >nul 2>&1 && exit /b 0
for /f "delims=" %%F in ('dir /b /s "%LocalAppData%\Microsoft\WinGet\Packages\7zip.7zip*\\7z.exe" 2^>nul') do (
  set "_SEVENZIP_EXE=%%~fF"
  exit /b 0
)
exit /b 1

:ENSURE_SED
REM Ensure GNU sed is installed and resolvable
REM Убедиться, что установлен GNU sed и доступен
where sed >nul 2>&1 && exit /b 0
echo Installing sed via WinGet...
echo Установка sed через WinGet...
REM First try mbuilov.sed (modern native build)
winget install -e --id mbuilov.sed --silent --accept-package-agreements --accept-source-agreements
where sed >nul 2>&1 && exit /b 0
REM Then try GnuWin32.Sed as a fallback
winget install -e --id GnuWin32.Sed --silent --accept-package-agreements --accept-source-agreements
where sed >nul 2>&1 && exit /b 0
REM Try common locations if PATH not refreshed
set "_SED_EXE="
if exist "%ProgramFiles(x86)%\GnuWin32\bin\sed.exe" set "_SED_EXE=%ProgramFiles(x86)%\GnuWin32\bin\sed.exe"
if not defined _SED_EXE if exist "%ProgramFiles%\Git\usr\bin\sed.exe" set "_SED_EXE=%ProgramFiles%\Git\usr\bin\sed.exe"
if defined _SED_EXE exit /b 0
for /f "delims=" %%F in ('dir /b /s "%LocalAppData%\Microsoft\WinGet\Packages\mbuilov.sed*\\sed.exe" 2^>nul') do (
  set "_SED_EXE=%%~fF"
  exit /b 0
)
exit /b 1

:GET_LOCALE
REM Detect ru (Russian layout); otherwise default to en-US
REM Определить ru (русская раскладка); иначе по умолчанию en-US
for /f "tokens=3" %%a in ('reg query "HKEY_USERS\.DEFAULT\Keyboard Layout\Preload"^|find "REG_SZ"') do (
  if %%a==00000419 (set locale=ru) else (set locale=en-US)
  goto :eof
)
set locale=en-US
goto :eof

:GET_PROXY
REM Pick up system proxy for curl if enabled
REM Использовать системный прокси для curl, если включен
set "PROXY_ARGS="
set "REG_PROXY=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings"
for /F "Tokens=1,3" %%i in ('reg query "%%REG_PROXY%%"^|find "Proxy"') do set %%i=%%j
if "%ProxyEnable%"=="0x1" set "PROXY_ARGS=-x %ProxyServer%"
goto :eof

:GET_ARCH
REM Determine 32/64-bit for downloading the correct installer
REM Определить 32/64-бит для загрузки нужного установщика
set xOS=win32
if defined PROCESSOR_ARCHITEW6432 (set xOS=win64) else if /i "%PROCESSOR_ARCHITECTURE%" NEQ "x86" (set xOS=win64)
goto :eof

:GET_ARGS
REM Optional: --skipwait to avoid final pause
REM Необязательно: --skipwait чтобы избежать финальной паузы
set arg_skipwait=
for %%a in (%*) do (
  if "%%a"=="--skipwait" set arg_skipwait=yes
)
goto :eof