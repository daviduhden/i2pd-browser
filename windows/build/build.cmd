@ECHO OFF
REM Copyright (c) 2013-2019, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM See full license text in LICENSE file at top of project tree

setlocal enableextensions enabledelayedexpansion

set "CURL=%~dp0curl.exe"
set "SEVENZIP=7z"
set "SED=%~dp0sed.exe"

call :GET_ARGS %*
call :GET_LOCALE
call :GET_PROXY
call :GET_ARCH

set "ESR_PRODUCT=firefox-esr-latest"

echo Building I2Pd Browser Portable
echo ���ઠ I2Pd Browser Portable
echo Browser locale: %locale%, architecture: %xOS%
echo ��� ��㧥�: %locale%, ���⥪���: %xOS%
echo.
echo Downloading Firefox ESR installer
echo ����㧪� ��⠭��騪� Firefox ESR

if /i "%xOS%"=="win32" (
  set "dl_os=win32"
) else if /i "%xOS%"=="win64" (
  set "dl_os=win64"
) else if /i "%xOS%"=="winarm" (
  set "dl_os=win64-aarch64"
) else (
  echo ERROR: Unknown architecture "%xOS%"
  echo ������: �������⭠� ���⥪��� "%xOS%"
  pause & exit /b 1
)

REM Use Mozilla redirector to always get latest ESR
REM �ᯮ���� ।�४�� Mozilla ��� ����祭�� ��᫥���� ESR
set "FF_URL=https://download.mozilla.org/?product=%ESR_PRODUCT%&os=%dl_os%&lang=%locale%"
"%CURL%" -L -f -# -o firefox.exe "%FF_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

echo.
echo Unpacking the installer and deleting unnecessary files
echo ��ᯠ����� ��⠭��騪� � 㤠����� ���㦭�� 䠩���
"%SEVENZIP%" x -y -o..\Firefox\App firefox.exe >nul
del /Q firefox.exe
ren ..\Firefox\App\core Firefox
del /Q ..\Firefox\App\setup.exe
del /Q ..\Firefox\App\Firefox\browser\crashreporter-override.ini
rmdir /S /Q ..\Firefox\App\Firefox\browser\features
rmdir /S /Q ..\Firefox\App\Firefox\gmp-clearkey
rmdir /S /Q ..\Firefox\App\Firefox\uninstall
del /Q "..\Firefox\App\Firefox\Accessible*.*"
REM Do NOT delete application.ini; we need it to read the exact version and to disable updates
REM �� 㤠��� application.ini; �� �㦥� ��� �⥭�� ���ᨨ � �⪫�祭�� ����������
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
REM ������ ���� ����� �� application.ini
set "FF_VER="
for /f "usebackq tokens=2 delims==" %%v in (`findstr /b /i "Version=" "..\Firefox\App\Firefox\application.ini"`) do set "FF_VER=%%v"
if not defined FF_VER (
  echo ERROR: Couldn't read Firefox version from application.ini
  echo ������: �� 㤠���� ������ ����� Firefox �� application.ini
  pause & exit /b
)
set "XPI_BASE=https://releases.mozilla.org/pub/firefox/releases/%FF_VER%/%dl_os%/xpi"

echo.
echo Patching browser internal files to reduce external requests
echo ���稭� ����७��� 䠩��� ��㧥� ��� �⪫�祭�� ���譨� ����ᮢ
"%SEVENZIP%" -bso0 -y x ..\Firefox\App\Firefox\omni.ja -o..\Firefox\App\tmp >nul 2>&1
"%SED%" -i "s/https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1/http\:\/\/127\.0\.0\.1/" ..\Firefox\App\tmp\moz-src\toolkit\components\search\SearchUtils.sys.mjs
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo Patched 1/2
  echo ���� 1/2
)
"%SED%" -i "s/\"https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1\",$/\"\",/" ..\Firefox\App\tmp\modules\AppConstants.sys.mjs
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo Patched 2/2
  echo ���� 2/2
)

ren ..\Firefox\App\Firefox\omni.ja omni.ja.bak
"%SEVENZIP%" a -mx0 -tzip ..\Firefox\App\Firefox\omni.ja -r ..\Firefox\App\tmp\* >nul
rmdir /S /Q ..\Firefox\App\tmp
del ..\Firefox\App\Firefox\omni.ja.bak
echo OK!

echo.
echo Downloading language packs
echo ����㧪� �몮��� ����⮢

REM Always add RU to allow switching from EN
REM �ᥣ�� �������� RU ��� ���������� ��४��祭�� � EN
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\langpack-ru@firefox.mozilla.org.xpi ^
  "%XPI_BASE%/ru.xpi"
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

REM Add en-US only if the base build is RU (en-US build doesn't need en-US langpack)
REM ��������� en-US ⮫쪮 �᫨ ������� ᡮઠ RU (en-US �� �㦥� ��� en-US)
if /i "%locale%"=="ru" (
  "%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\langpack-en-US@firefox.mozilla.org.xpi ^
    "%XPI_BASE%/en-US.xpi"
  if errorlevel 1 (
    echo ERROR:%ErrorLevel%
    echo ������:%ErrorLevel%
    pause & exit
  ) else (
    echo OK!
  )
)

REM Dictionaries
REM ������
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\ru@dictionaries.addons.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/russian-spellchecking-dic-3703/latest.xpi
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\en-US@dictionaries.addons.mozilla.org.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/english-us-dictionary/latest.xpi
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

echo.
echo Downloading NoScript extension
echo ����㧪� ���������� NoScript
"%CURL%" -L -f -# -o ..\Firefox\App\Firefox\browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi ^
  https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

echo.
echo Disabling auto-updates via application.ini
echo �⪫�祭�� ��⮮��������� �१ application.ini
"%SED%" -i "s/Enabled=1/Enabled=0/g" "..\Firefox\App\Firefox\application.ini"
if errorlevel 1 ( echo WARN: couldn't set Enabled=0 & echo ��������: �� 㤠���� ���⠢��� Enabled=0 ) else ( echo OK! & echo ��! )
"%SED%" -i "s/ServerURL=.*/ServerURL=-/" "..\Firefox\App\Firefox\application.ini"
if errorlevel 1 ( echo WARN: couldn't blank ServerURL & echo ��������: �� 㤠���� ������ ServerURL ) else ( echo OK! & echo ��! )

echo.
echo Copying Firefox launcher and settings
echo ����஢���� 䠩��� ����஥� Firefox
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
echo ����㧪� I2Pd
set "I2PD_URL="
set "TMP_HTML=%TEMP%\i2pd_latest_%RANDOM%.html"
"%CURL%" -L -f -s -o "%TMP_HTML%" "https://github.com/PurpleI2P/i2pd/releases/latest"
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
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
  echo ������: �� 㤠���� ���� ��뫪� �� ५�� i2pd
  pause & exit
)

"%CURL%" -L -f -# -O "%I2PD_URL%"
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  echo ������:%ErrorLevel%
  pause & exit
) else (
  echo OK!
)

"%SEVENZIP%" x -y -o..\i2pd "%~nxI2PD_URL%" i2pd.exe >nul
del /Q "%~nxI2PD_URL%"
xcopy /E /I /Y i2pd ..\i2pd >nul

echo.
echo I2Pd Browser Portable is ready to start!
echo I2Pd Browser Portable ��⮢ � ������!
if not defined arg_skipwait pause
exit /b

:GET_LOCALE
REM Detect ru (Russian layout); otherwise default to en-US
REM ��।����� ru (���᪠� �᪫����); ���� �� 㬮�砭�� en-US
for /f "tokens=3" %%a in ('reg query "HKEY_USERS\.DEFAULT\Keyboard Layout\Preload"^|find "REG_SZ"') do (
  if %%a==00000419 (set locale=ru) else (set locale=en-US)
  goto :eof
)
set locale=en-US
goto :eof

:GET_PROXY
REM Pick up system proxy for curl if enabled
REM �ᯮ�짮���� ��⥬�� �ப� ��� curl, �᫨ ����祭
set "PROXY_ARGS="
set "REG_PROXY=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings"
for /F "Tokens=1,3" %%i in ('reg query "%%REG_PROXY%%"^|find "Proxy"') do set %%i=%%j
if "%ProxyEnable%"=="0x1" set "PROXY_ARGS=-x %ProxyServer%"
goto :eof

:GET_ARCH
REM Determine 32/64-bit for downloading the correct installer
REM ��।����� 32/64-��� ��� ����㧪� �㦭��� ��⠭��騪�
set xOS=win32
if defined PROCESSOR_ARCHITEW6432 (set xOS=win64) else if /i "%PROCESSOR_ARCHITECTURE%" NEQ "x86" (set xOS=win64)
goto :eof

:GET_ARGS
REM Optional: --skipwait to avoid final pause
REM ����易⥫쭮: --skipwait �⮡� �������� 䨭��쭮� ����
set arg_skipwait=
for %%a in (%*) do (
  if "%%a"=="--skipwait" set arg_skipwait=yes
)
goto :eof