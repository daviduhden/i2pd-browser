@echo off

REM Copyright (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM See full license text in LICENSE file at top of project tree

setlocal enableextensions

set "CURL=%~dp0curl.exe"
set "SEVENZIP=7z"

call :GET_ARGS %*
call :GET_LOCALE
call :GET_PROXY
call :GET_ARCH

set "ESR_PRODUCT=firefox-esr-latest"

if "%locale%"=="ru" (
  echo Сборка I2Pd Browser Portable
  echo Язык браузера: %locale%, архитектура: %xOS%
  echo.
  echo Загрузка установщика Firefox ESR
) else (
  echo Building I2Pd Browser Portable
  echo Browser locale: %locale%, architecture: %xOS%
  echo.
  echo Downloading Firefox ESR installer
)

if /i "%xOS%"=="win32" ( set "dl_os=win" ) else ( set "dl_os=win64" )

REM Use Mozilla redirector to always get latest ESR
set "FF_URL=https://download.mozilla.org/?product=%ESR_PRODUCT%&os=%dl_os%&lang=%locale%"
"%CURL%" -L -f -# -o firefox.exe "%FF_URL" %$X%
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else ( echo OK! )

echo.
if "%locale%"=="ru" (
  echo Распаковка установщика и удаление не нужных файлов
) else (
  echo Unpacking the installer and deleting unnecessary files
)
"%SEVENZIP%" x -y -o..\Firefox\App firefox.exe >nul
del /Q firefox.exe
ren ..\Firefox\App\core Firefox
del /Q ..\Firefox\App\setup.exe
del /Q ..\Firefox\App\Firefox\browser\crashreporter-override.ini
rmdir /S /Q ..\Firefox\App\Firefox\browser\features
rmdir /S /Q ..\Firefox\App\Firefox\gmp-clearkey
rmdir /S /Q ..\Firefox\App\Firefox\uninstall
del /Q ..\Firefox\App\Firefox\Accessible*.*
del /Q ..\Firefox\App\Firefox\application.ini
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

echo.
if "%locale%"=="ru" (
  echo Патчим внутренние файлы браузера для отключения навязчивых запросов
) else (
  echo Patching browser internal files to disable external requests
)

"%SEVENZIP%" -bso0 -y x ..\Firefox\App\Firefox\omni.ja -o..\Firefox\App\tmp >nul 2>&1

sed -i "s/https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1/http\:\/\/127\.0\.0\.1/" ..\Firefox\App\tmp\modules\SearchUtils.sys.mjs
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo Patched 1/2)
sed -i "s/\"https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1\",$/\"\",/" ..\Firefox\App\tmp\modules\AppConstants.sys.mjs
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo Patched 2/2)

ren ..\Firefox\App\Firefox\omni.ja omni.ja.bak
"%SEVENZIP%" a -mx0 -tzip ..\Firefox\App\Firefox\omni.ja -r ..\Firefox\App\tmp\* >nul
rmdir /S /Q ..\Firefox\App\tmp
del ..\Firefox\App\Firefox\omni.ja.bak
echo OK!

echo.
if "%locale%"=="ru" (
  echo Загрузка языковых пакетов
) else (
  echo Downloading language packs
)
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\langpack-ru@firefox.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/russian-ru-language-pack/latest.xpi
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo OK!)
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\langpack-en-US@firefox.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/english-us-language-pack/latest.xpi
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo OK!)
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\ru@dictionaries.addons.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/russian-spellchecking-dic-3703/latest.xpi
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo OK!)
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\en-US@dictionaries.addons.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/english-us-dictionary/latest.xpi
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo OK!)

echo.
if "%locale%"=="ru" (
  echo Загрузка дополнения NoScript
) else (
  echo Downloading NoScript extension
)
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo OK!)

echo.
if "%locale%"=="ru" (
  echo Копирование файлов настроек в папку Firefox
) else (
  echo Copying Firefox launcher and settings
)
mkdir ..\Firefox\App\DefaultData\profile\ >nul
xcopy /E /Y profile\* ..\Firefox\App\DefaultData\profile\ >nul
if "%locale%"=="ru" (
  copy /Y profile-ru\* ..\Firefox\App\DefaultData\profile\ >nul
) else (
  copy /Y profile-en\* ..\Firefox\App\DefaultData\profile\ >nul
)
copy /Y firefox-portable\* ..\Firefox\ >nul
xcopy /E /Y preferences\* ..\Firefox\App\Firefox\ >nul
echo OK!

echo.
if "%locale%"=="ru" (
  echo Загрузка I2Pd
) else (
  echo Downloading I2Pd
)
for /f "delims=" %%A in ('powershell -NoProfile -Command ^
  "$a=(Invoke-RestMethod https://api.github.com/repos/PurpleI2P/i2pd/releases/latest).assets; ^
   ($a | Where-Object { $_.name -like 'i2pd_*_%xOS%_mingw.zip' } | Select-Object -ExpandProperty browser_download_url)"') do set "I2PD_URL=%%A"

if not defined I2PD_URL ( echo ERROR: couldn't resolve i2pd asset URL & pause & exit )
"%CURL%" -L -f -# -O "%I2PD_URL%"
if errorlevel 1 ( echo ERROR:%ErrorLevel% & pause & exit ) else (echo OK!)

"%SEVENZIP%" x -y -o..\i2pd "%~nxI2PD_URL%" i2pd.exe >nul
del /Q "%~nxI2PD_URL%"
xcopy /E /I /Y i2pd ..\i2pd >nul

echo.
if "%locale%"=="ru" (
  echo I2Pd Browser Portable готов к запуску!
) else (
  echo I2Pd Browser Portable is ready to start!
)
if not defined arg_skipwait pause
exit /b

:GET_LOCALE
for /f "tokens=3" %%a in ('reg query "HKEY_USERS\.DEFAULT\Keyboard Layout\Preload"^|find "REG_SZ"') do (
  if %%a==00000419 (set locale=ru) else (set locale=en-US)
  goto :eof
)
goto :eof

:GET_PROXY
set $X=&set $R=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings
for /F "Tokens=1,3" %%i in ('reg query "%$R%"^|find "Proxy"') do set %%i=%%j
if "%ProxyEnable%"=="0x1" set "$X=-x %ProxyServer%"
goto :eof

:GET_ARCH
set xOS=win32
if defined PROCESSOR_ARCHITEW6432 (set xOS=win64) else if /i "%PROCESSOR_ARCHITECTURE%" NEQ "x86" (set xOS=win64)
goto :eof

:GET_ARGS
set arg_skipwait=
for %%a in (%*) do (
  if "%%a"=="--skipwait" set arg_skipwait=yes
)
goto :eof