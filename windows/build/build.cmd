@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM See full license text in LICENSE file at top of project tree

REM -------------------- Environment --------------------
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

REM ---------- Paths & temp ----------
pushd "%~dp0"
set "BASEDIR=%~dp0"
set "WORKTMP=%BASEDIR%_tmp"
if not exist "%WORKTMP%\NUL" mkdir "%WORKTMP%" >nul 2>&1

REM ---------- Tools ----------
set "CURL=%~dp0curl.exe"
if not exist "%CURL%" set "CURL=curl"
set "SEVENZIP="
set "SED="

where 7z >nul 2>&1 && set "SEVENZIP=7z"
if not defined SEVENZIP if exist "%ProgramFiles%\7-Zip\7z.exe" set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
if not defined SEVENZIP if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe"

where sed >nul 2>&1 && set "SED=sed"
if not defined SED if exist "%ProgramFiles%\Git\usr\bin\sed.exe" set "SED=%ProgramFiles%\Git\usr\bin\sed.exe"
if not defined SED if exist "%ProgramFiles(x86)%\GnuWin32\bin\sed.exe" set "SED=%ProgramFiles(x86)%\GnuWin32\bin\sed.exe"

REM ---------- Winget auto-install missing tools ----------
set "HAVE_WINGET=0"
where winget >nul 2>&1 && set "HAVE_WINGET=1"

REM Ensure CURL
set "NEED_CURL=0"
if /I "%CURL%"=="curl" (
  where curl >nul 2>&1 || set "NEED_CURL=1"
) else (
  if not exist "%CURL%" set "NEED_CURL=1"
)
if "%NEED_CURL%"=="1" (
  if "%HAVE_WINGET%"=="1" (
    echo Installing curl via winget...
    if "%SHOW_RU%"=="1" echo Установка curl через winget...
    winget install -e --id cURL.cURL --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if exist "%ProgramFiles%\cURL\bin\curl.exe" set "CURL=%ProgramFiles%\cURL\bin\curl.exe"
    where curl >nul 2>&1 && set "CURL=curl"
  ) else (
    echo WARNING: winget not found; curl is required.
    if "%SHOW_RU%"=="1" echo ПРЕДУПРЕЖДЕНИЕ: winget не найден; требуется curl.
  )
)

REM Ensure 7-Zip
if not defined SEVENZIP (
  if "%HAVE_WINGET%"=="1" (
    echo Installing 7-Zip via winget...
    if "%SHOW_RU%"=="1" echo Установка 7-Zip через winget...
    winget install -e --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    where 7z >nul 2>&1 && set "SEVENZIP=7z"
    if not defined SEVENZIP if exist "%ProgramFiles%\7-Zip\7z.exe" set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
    if not defined SEVENZIP if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe"
  ) else (
    echo WARNING: winget not found; 7-Zip is required.
    if "%SHOW_RU%"=="1" echo ПРЕДУПРЕЖДЕНИЕ: winget не найден; требуется 7-Zip.
  )
)

REM Ensure sed
if not defined SED (
  if "%HAVE_WINGET%"=="1" (
    rem *** FIX: escapar paréntesis en ECHO dentro de bloques ***
    echo Installing sed via winget ^(mbuilov.sed^)...
    if "%SHOW_RU%"=="1" echo Установка sed через winget ^(mbuilov.sed^)...
    winget install -e --id mbuilov.sed --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    where sed >nul 2>&1 && set "SED=sed"
    if not defined SED if exist "%ProgramFiles(x86)%\GnuWin32\bin\sed.exe" set "SED=%ProgramFiles(x86)%\GnuWin32\bin\sed.exe"
    if not defined SED if exist "%ProgramFiles%\Git\usr\bin\sed.exe" set "SED=%ProgramFiles%\Git\usr\bin\sed.exe"
  )
)
if not defined SED (
  if "%HAVE_WINGET%"=="1" (
    echo Installing sed via winget ^(GnuWin32.Sed^)...
    if "%SHOW_RU%"=="1" echo Установка sed через winget ^(GnuWin32.Sed^)...
    winget install -e --id GnuWin32.Sed --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    where sed >nul 2>&1 && set "SED=sed"
    if not defined SED if exist "%ProgramFiles(x86)%\GnuWin32\bin\sed.exe" set "SED=%ProgramFiles(x86)%\GnuWin32\bin\sed.exe"
    if not defined SED if exist "%ProgramFiles%\Git\usr\bin\sed.exe" set "SED=%ProgramFiles%\Git\usr\bin\sed.exe"
  ) else (
    echo WARNING: winget not found; sed not available. Patches will be skipped.
    if "%SHOW_RU%"=="1" echo ПРЕДУПРЕЖДЕНИЕ: winget не найден; sed недоступен. Патчи будут пропущены.
  )
)

REM ---------- Args ----------
set "arg_skipwait="
for %%A in (%*) do if /i "%%A"=="--skipwait" set "arg_skipwait=yes"

REM ---------- Locale ----------
set "SHOW_RU=0"
set "locale=en-US"
set "LOCALE_NAME="
for /f "tokens=2,*" %%A in ('
  reg query "HKCU\Control Panel\International" /v LocaleName 2^>nul ^| find "LocaleName"
') do set "LOCALE_NAME=%%B"
if defined LOCALE_NAME (
  set "LC2=!LOCALE_NAME:~0,2!"
  if /i "!LC2!"=="ru" ( set "SHOW_RU=1" & set "locale=ru" )
)

REM ---------- Proxy ----------
set "PROXY_ARGS="
set "ProxyEnable="
set "ProxyServer="
for /f "skip=2 tokens=3" %%A in ('reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul') do set "ProxyEnable=%%A"
for /f "skip=2 tokens=2,*" %%A in ('reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul') do set "ProxyServer=%%B"
if /i "%ProxyEnable%"=="0x1" if defined ProxyServer set "PROXY_ARGS=-x \"%ProxyServer%\""

REM ---------- Arch ----------
set "PA=%PROCESSOR_ARCHITECTURE%"
set "PW=%PROCESSOR_ARCHITEW6432%"
if not defined PA set "PA=x86"
set "ARCH_SUPPORTED=1"
set "xOS=win32"
if /i "%PA%"=="AMD64" set "xOS=win64"
if /i "%PA%"=="X64"   set "xOS=win64"
if /i "%PA%"=="x86" if defined PW (
  if /i "%PW%"=="AMD64" set "xOS=win64"
  if /i "%PW%"=="ARM64" set "xOS=win32"
)
if /i "%PA%"=="ARM64" ( set "ARCH_SUPPORTED=0" & set "xOS=unsupported" )
if /i "%PA%"=="ARM"   ( set "ARCH_SUPPORTED=0" & set "xOS=unsupported" )
if /i "%PA%"=="IA64"  ( set "ARCH_SUPPORTED=0" & set "xOS=unsupported" )
set "ARCH_DISPLAY=%xOS% host %PA% %PW%"
if /i "%ARCH_SUPPORTED%"=="0" set "ARCH_DISPLAY=unsupported host %PA% %PW%"

if "%ARCH_SUPPORTED%"=="0" (
  echo ERROR: Unsupported architecture ^(ARM/IA64^).
  if "%SHOW_RU%"=="1" echo ОШИБКА: Неподдерживаемая архитектура ^(ARM/IA64^).
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)

REM ---------- Pre-flight checks ----------
where "%CURL%" >nul 2>&1 || where curl >nul 2>&1 || (
  echo ERROR: curl not available; cannot continue.
  if "%SHOW_RU%"=="1" echo ОШИБКА: curl недоступен; продолжение невозможно.
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)
if not defined SEVENZIP (
  echo ERROR: 7-Zip not available; cannot continue.
  if "%SHOW_RU%"=="1" echo ОШИБКА: 7-Zip недоступен; продолжение невозможно.
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)

REM ---------- Banner ----------
echo Building I2Pd Browser Portable
if "%SHOW_RU%"=="1" echo Сборка I2Pd Browser Portable
echo Browser locale: %locale%, architecture: %ARCH_DISPLAY%
if "%SHOW_RU%"=="1" echo Язык браузера: %locale%, архитектура: %ARCH_DISPLAY%
echo(
echo Resolving latest Firefox ESR version
if "%SHOW_RU%"=="1" echo Определение последней версии Firefox ESR

REM ---------- Redirect & download ----------
set "FF_REDIRECT=https://download.mozilla.org/?product=firefox-esr-latest&os=%xOS%&lang=%locale%"
set "FF_FINAL="
"%CURL%" -L -s -o NUL -w "%%{url_effective}" "%FF_REDIRECT%" %PROXY_ARGS% > "%WORKTMP%\ff_url.txt" 2>nul
for /f "usebackq delims=" %%U in ("%WORKTMP%\ff_url.txt") do set "FF_FINAL=%%U"
del /Q "%WORKTMP%\ff_url.txt" >nul 2>&1

echo Downloading Firefox ESR installer
if "%SHOW_RU%"=="1" echo Загрузка установщика Firefox ESR
set "FF_EXE=%WORKTMP%\FirefoxSetupESR.exe"
"%CURL%" -L -f -# -o "%FF_EXE%" "%FF_REDIRECT%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)

REM ---------- Extract Firefox ----------
echo(
echo Unpacking the installer and deleting unnecessary files
if "%SHOW_RU%"=="1" echo Распаковка установщика и удаление ненужных файлов
"%SEVENZIP%" x -y -o"..\Firefox\App" "%FF_EXE%" >nul 2>&1
set "_7Z_RC=%ERRORLEVEL%"
del /Q "%FF_EXE%" >nul 2>&1
if not "%_7Z_RC%"=="0" (
  echo ERROR: 7-Zip failed to extract Firefox.
  if "%SHOW_RU%"=="1" echo ОШИБКА: 7-Zip не смог распаковать Firefox.
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)
ren "..\Firefox\App\core" "Firefox" 2>nul

REM ---------- Read version from application.ini ----------
set "FFversion="
for /f "tokens=1,2 delims==" %%A in ('findstr /I /R "^DisplayVersion= ^Version=" "..\Firefox\App\Firefox\application.ini"') do (
  if /I "%%A"=="DisplayVersion" set "FFversion=%%B"
  if not defined FFversion if /I "%%A"=="Version" set "FFversion=%%B"
)
for /f "delims=" %%Z in ("!FFversion!") do set "FFversion=%%Z"
if defined FFversion (
  echo Version detected from application.ini: !FFversion!
  if "%SHOW_RU%"=="1" echo Версия определена из application.ini: !FFversion!
) else (
  echo WARNING: Version still unknown; language pack downloads may fail.
  if "%SHOW_RU%"=="1" echo ПРЕДУПРЕЖДЕНИЕ: версия не определена; загрузка языковых пакетов может не сработать.
)

REM ---------- Release folder version ----------
set "FFVER_PATH=!FFversion!"
if defined FFVER_PATH (
  set "TEST=!FFVER_PATH:esr=!"
  if /I "!TEST!"=="!FFVER_PATH!" set "FFVER_PATH=!FFVER_PATH!esr"
) else (
  if defined FF_FINAL (
    rem *** FIX: usar expansión retardada para evitar que %20 rompa el bloque ***
    set "TMP_AFTER=!FF_FINAL:*releases/=!"
    for /f "delims=/" %%V in ("!TMP_AFTER!") do set "FFVER_PATH=%%V"
  )
)

REM ---------- Clean extras ----------
del /Q "..\Firefox\App\Firefox\browser\crashreporter-override.ini" 2>nul
rmdir /S /Q "..\Firefox\App\Firefox\browser\features" 2>nul
rmdir /S /Q "..\Firefox\App\Firefox\gmp-clearkey" 2>nul
rmdir /S /Q "..\Firefox\App\Firefox\uninstall" 2>nul
del /Q "..\Firefox\App\Firefox\Accessible*.*" 2>nul
del /Q "..\Firefox\App\Firefox\crashreporter.*" 2>nul
del /Q "..\Firefox\App\Firefox\*.sig" 2>nul
del /Q "..\Firefox\App\Firefox\maintenanceservice*.*" 2>nul
del /Q "..\Firefox\App\Firefox\minidump-analyzer.exe" 2>nul
del /Q "..\Firefox\App\Firefox\precomplete" 2>nul
del /Q "..\Firefox\App\Firefox\removed-files" 2>nul
del /Q "..\Firefox\App\Firefox\ucrtbase.dll" 2>nul
del /Q "..\Firefox\App\Firefox\update*.*" 2>nul
if not exist "..\Firefox\App\Firefox\browser\extensions\NUL" mkdir "..\Firefox\App\Firefox\browser\extensions" >nul 2>&1
echo OK
if "%SHOW_RU%"=="1" echo ОК

REM ---------- Patch omni.ja ----------
if not defined SED (
  echo WARNING: sed not found; skipping omni.ja patches.
  if "%SHOW_RU%"=="1" echo ПРЕДУПРЕЖДЕНИЕ: sed не найден; патчи omni.ja будут пропущены.
) else (
  echo(
  echo Patching browser internals
  if "%SHOW_RU%"=="1" echo Патчинг внутренних файлов браузера
  for %%P in ("..\Firefox\App\Firefox\omni.ja" "..\Firefox\App\Firefox\browser\omni.ja") do (
    set "OMNI=%%~fP"
    if exist "!OMNI!" (
      set "_TMPOMNI=%WORKTMP%\omni_!RANDOM!"
      if exist "!_TMPOMNI!\NUL" rmdir /S /Q "!_TMPOMNI!" >nul 2>&1
      mkdir "!_TMPOMNI!" >nul 2>&1
      "%SEVENZIP%" -bso0 -y x "!OMNI!" -o"!_TMPOMNI!" >nul 2>&1

      set "SEARCHUTILS="
      for /r "!_TMPOMNI!" %%F in (SearchUtils.sys.mjs) do (set "SEARCHUTILS=%%~fF")
      if defined SEARCHUTILS ("%SED%" -i.bak "s/https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1/http\:\/\/127\.0\.0\.1/" "!SEARCHUTILS!" >nul 2>&1 & del /Q "!SEARCHUTILS!.bak" >nul 2>&1)

      set "APPCONST="
      for /r "!_TMPOMNI!" %%F in (AppConstants.sys.mjs) do (set "APPCONST=%%~fF")
      if defined APPCONST ("%SED%" -i.bak "s/\"https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1\",$/\"\",/" "!APPCONST!" >nul 2>&1 & del /Q "!APPCONST!.bak" >nul 2>&1)

      if exist "!OMNI!" ren "!OMNI!" "omni.ja.bak" >nul 2>&1
      "%SEVENZIP%" a -mx0 -tzip "!OMNI!" -r "!_TMPOMNI!\*" >nul 2>&1
      rmdir /S /Q "!_TMPOMNI!" >nul 2>&1
      del /Q "!OMNI!.bak" >nul 2>&1
    ) else (
      echo WARN: "%%~fP" not found - skipping.
      if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: "%%~fP" не найден — пропускаем.
    )
  )
  echo OK
  if "%SHOW_RU%"=="1" echo ОК
)

REM ---------- Disable updates ----------
echo(
echo Disabling auto-updates via application.ini
if "%SHOW_RU%"=="1" echo Отключение автообновлений через application.ini
if exist "..\Firefox\App\Firefox\application.ini" if defined SED (
  "%SED%" -i.bak "s/Enabled=1/Enabled=0/g" "..\Firefox\App\Firefox\application.ini" >nul 2>&1
  "%SED%" -i.bak "s/ServerURL=.*/ServerURL=-/" "..\Firefox\App\Firefox\application.ini" >nul 2>&1
  del /Q "..\Firefox\App\Firefox\application.ini.bak" >nul 2>&1
)

REM ---------- Language packs ----------
echo(
if not defined FFVER_PATH (
  echo WARNING: ESR folder version unknown; skipping language packs.
  if "%SHOW_RU%"=="1" echo ПРЕДУПРЕЖДЕНИЕ: версия ESR для папки неизвестна; пропускаем языковые пакеты.
) else (
  echo Downloading language packs for ESR !FFVER_PATH!
  if "%SHOW_RU%"=="1" echo Загрузка языковых пакетов для ESR !FFVER_PATH!
  set "XPI_BASE=https://releases.mozilla.org/pub/firefox/releases/!FFVER_PATH!/%xOS%/xpi"
  "%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\langpack-en-US@firefox.mozilla.org.xpi" "!XPI_BASE!/en-US.xpi" %PROXY_ARGS%
  if errorlevel 1 (
    echo ERROR:%ErrorLevel%
    if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
    if /i "%arg_skipwait%" NEQ "yes" pause & popd & goto :EOF
  ) else echo OK & if "%SHOW_RU%"=="1" echo ОК
  "%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\langpack-ru@firefox.mozilla.org.xpi" "!XPI_BASE!/ru.xpi" %PROXY_ARGS%
  if errorlevel 1 (
    echo ERROR:%ErrorLevel%
    if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
    if /i "%arg_skipwait%" NEQ "yes" pause & popd & goto :EOF
  ) else echo OK & if "%SHOW_RU%"=="1" echo ОК
)

REM ---------- Dictionaries ----------
echo(
echo Downloading dictionaries
if "%SHOW_RU%"=="1" echo Загрузка словарей
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\en-US@dictionaries.addons.mozilla.org.xpi" "https://addons.mozilla.org/firefox/downloads/latest/english-us-dictionary/latest.xpi" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  if /i "%arg_skipwait%" NEQ "yes" pause & popd & goto :EOF
) else echo OK & if "%SHOW_RU%"=="1" echo ОК
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\ru@dictionaries.addons.mozilla.org.xpi" "https://addons.mozilla.org/firefox/downloads/latest/russian-spellchecking-dic-3703/latest.xpi" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  if /i "%arg_skipwait%" NEQ "yes" pause & popd & goto :EOF
) else echo OK & if "%SHOW_RU%"=="1" echo ОК

REM ---------- NoScript ----------
echo(
echo Downloading NoScript extension (latest)
if "%SHOW_RU%"=="1" echo Загрузка дополнения NoScript ^(последняя версия^)
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi" "https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  if /i "%arg_skipwait%" NEQ "yes" pause & popd & goto :EOF
) else echo OK & if "%SHOW_RU%"=="1" echo ОК

REM ---------- Launcher & profile ----------
echo(
echo Copying Firefox launcher and settings
if "%SHOW_RU%"=="1" echo Копирование лаунчера и настроек Firefox
mkdir "..\Firefox\App\DefaultData\profile\" >nul 2>&1
xcopy /E /Y "profile\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
if /i "%locale%"=="ru" (
  if exist "profile-ru\*" xcopy /E /Y "profile-ru\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
) else (
  if exist "profile-en\*" xcopy /E /Y "profile-en\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
)
if exist "firefox-portable\*" xcopy /E /I /Y "firefox-portable\*" "..\Firefox" >nul 2>&1
if exist "preferences\*" xcopy /E /Y "preferences\*" "..\Firefox\App\Firefox\" >nul 2>&1
echo OK
if "%SHOW_RU%"=="1" echo ОК

REM ---------- I2Pd ----------
echo(
echo Locating and downloading I2Pd via GitHub API
if "%SHOW_RU%"=="1" echo Поиск и загрузка I2Pd через API GitHub
set "TMP_JSON=%WORKTMP%\i2pd_latest_!RANDOM!.json"
"%CURL%" -L -f -s -o "!TMP_JSON!" "https://api.github.com/repos/PurpleI2P/i2pd/releases/latest" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  del /Q "!TMP_JSON!" >nul 2>&1
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)
for /f "usebackq delims=" %%U in (`
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-I2pdAssetUrl.ps1" -JsonPath "!TMP_JSON!" -OsTag "%xOS%"
`) do set "I2PD_URL=%%U"
del /Q "!TMP_JSON!" >nul 2>&1
if not defined I2PD_URL (
  echo ERROR: couldn't resolve i2pd asset URL from GitHub API.
  if "%SHOW_RU%"=="1" echo ОШИБКА: не удалось получить ссылку i2pd из GitHub API.
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)
"%CURL%" -L -f -# -OJ "%I2PD_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if "%SHOW_RU%"=="1" echo ОШИБКА:%ErrorLevel%
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)
set "I2PD_ZIP="
for %%F in (i2pd*_%xOS%_mingw.zip) do set "I2PD_ZIP=%%~nxF"
if not defined I2PD_ZIP (
  echo ERROR: i2pd zip not found after download.
  if "%SHOW_RU%"=="1" echo ОШИБКА: архив i2pd не найден после загрузки.
  if /i "%arg_skipwait%" NEQ "yes" pause
  popd & goto :EOF
)
"%SEVENZIP%" x -y -o"..\i2pd" "%I2PD_ZIP%" i2pd.exe >nul 2>&1
del /Q "%I2PD_ZIP%" >nul 2>&1
robocopy ".\i2pd" "..\i2pd" /MOVE /E >nul 2>&1
rmdir /S /Q ".\i2pd" >nul 2>&1

echo(
echo I2Pd Browser Portable is ready to start!
if "%SHOW_RU%"=="1" echo I2Pd Browser Portable готов к запуску!
if not defined arg_skipwait pause
popd
goto :EOF
