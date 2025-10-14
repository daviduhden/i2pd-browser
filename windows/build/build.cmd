@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM See full license text in LICENSE file at top of project tree

setlocal EnableExtensions EnableDelayedExpansion

REM --- Unquote TEMP once and reuse everywhere ---
set "TEMP_UNQ=%TEMP:"=%"

REM --- Always run from this script folder (stable relative paths) ---
pushd "%~dp0"

REM --- Prefer local curl.exe; fall back to system/winget if missing ---
set "CURL=%~dp0curl.exe"
if not exist "%CURL%" set "CURL=curl"

REM --- Runtime vars (no hardcoded versions) ---
set "FFversion="
set "FF_EXE="
set "I2PD_URL="
set "I2PD_ZIP="

call :GET_ARGS %*
call :GET_LOCALE
call :GET_PROXY
call :GET_ARCH

REM --- Switch to UTF-8 only if Russian UI to avoid mojibake ---
if /i "%locale%"=="ru" chcp 65001 >nul

REM --- Ensure WinGet and required tools (only if needed) ---
call :ENSURE_WINGET >nul 2>&1
call :ENSURE_CURL   >nul 2>&1
call :ENSURE_7ZIP   >nul 2>&1
call :ENSURE_SED    >nul 2>&1

REM --- Architecture gate (block native ARM/IA64) ---
if "%ARCH_SUPPORTED%"=="0" (
  if /i "%locale%"=="ru" (
    echo ОШИБКА: Неподдерживаемая архитектура ^(ARM/IA64 не поддерживается^).
  ) else (
    echo ERROR: Unsupported architecture ^(ARM/IA64 not supported^).
  )
  if /i "%arg_skipwait%"=="yes" (popd & exit /b 1) else (pause & popd & exit /b 1)
)

if /i "%locale%"=="ru" (
  echo Сборка I2Pd Browser Portable
  echo Язык браузера: %locale%, архитектура: %ARCH_DISPLAY%
  echo.
  echo Загрузка установщика Firefox ESR
) else (
  echo Building I2Pd Browser Portable
  echo Browser locale: %locale%, architecture: %ARCH_DISPLAY%
  echo.
  echo Downloading Firefox ESR installer
)

REM --- 1) Latest Firefox ESR via redirector (save remote filename) ---
set "FF_REDIRECT=https://download.mozilla.org/?product=firefox-esr-latest&os=%xOS%&lang=%locale%"
"%CURL%" -L -f -# -OJ "%FF_REDIRECT%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if /I "%arg_skipwait%" NEQ "yes" pause
  popd & exit /b 1
)

REM Try to find the downloaded installer filename (typical: "Firefox Setup <ver>esr.exe")
for /f "delims=" %%F in ('dir /b "Firefox*Setup*esr*.exe" 2^>nul') do (
  set "FF_EXE=%%F"
  goto :FF_FOUND
)
:FF_FOUND
if not defined FF_EXE (
  REM Fallback: some servers save as "curl_response" when no Content-Disposition
  if exist "curl_response" (
    set "FF_EXE=curl_response"
  ) else (
    if /i "%locale%"=="ru" (echo ОШИБКА: установщик Firefox не найден после загрузки.) else (echo ERROR: Firefox installer not found after download.)
    if /I "%arg_skipwait%" NEQ "yes" pause
    popd & exit /b 1
  )
)

REM Derive exact ESR version from filename when possible
set "FFversion=%FF_EXE:Firefox Setup =%"
set "FFversion=%FFversion:.exe=%"
if /I "%FFversion%"=="%FF_EXE%" set "FFversion="

if defined FFversion (
  if /i "%locale%"=="ru" (
    echo Найдена версия Firefox ESR: %FFversion%
    echo Проверка целостности установщика по SHA512SUMS
  ) else (
    echo Detected Firefox ESR version: %FFversion%
    echo Verifying installer integrity via SHA512SUMS
  )

  REM --- 2) Verify SHA512 against ftp.mozilla.org SHA512SUMS ---
  set "TMP_SHA=%TEMP_UNQ%\ff_sha_%RANDOM%.txt"
  "%CURL%" -L -f -s -o "%TMP_SHA%" "https://ftp.mozilla.org/pub/firefox/releases/%FFversion%/SHA512SUMS" %PROXY_ARGS%
  if errorlevel 1 (
    if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: не удалось скачать SHA512SUMS; продолжаем без проверки.) else (echo WARNING: Failed to download SHA512SUMS; continuing without verification.)
  ) else (
    set "FF_REL=%xOS%/%locale%/Firefox Setup %FFversion%.exe"
    set "FF_SHA_EXP="
    for /f "tokens=1" %%H in ('findstr /C:"%FF_REL%" "%TMP_SHA%"') do set "FF_SHA_EXP=%%H"
    if not defined FF_SHA_EXP (
      if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: в SHA512SUMS нет строки для %FF_REL%.) else (echo WARNING: No matching line in SHA512SUMS for %FF_REL%.)
    ) else (
      REM Compute SHA512 and strip spaces/newlines from certutil output
      set "FF_SHA="
      for /f "usebackq delims=" %%L in (`certutil -hashfile "%FF_EXE%" SHA512 ^| findstr /R "^[0-9A-Fa-f]"`) do (
        set "LINE=%%L"
        set "LINE=!LINE: =!"
        set "FF_SHA=!FF_SHA!!LINE!"
      )
      if not defined FF_SHA (
        if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: не удалось вычислить SHA512 установщика.) else (echo WARNING: Failed to compute installer SHA512.)
      ) else (
        if /I not "!FF_SHA!"=="%FF_SHA_EXP%" (
          if /i "%locale%"=="ru" (echo ОШИБКА: несовпадение SHA512. Ожидалось: %FF_SHA_EXP%, Получено: !FF_SHA!.) else (echo ERROR: SHA512 mismatch. Expected: %FF_SHA_EXP%  Got: !FF_SHA!.)
          if /I "%arg_skipwait%" NEQ "yes" pause
          del /Q "%TMP_SHA%" >nul 2>&1
          popd & exit /b 1
        ) else (
          if /i "%locale%"=="ru" (echo Проверка пройдена.) else (echo Integrity OK.)
        )
      )
    )
  )
  del /Q "%TMP_SHA%" >nul 2>&1
) else (
  if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: не удалось определить версию из имени файла; проверка SHA будет пропущена.) else (echo WARNING: Couldn’t determine version from filename; skipping SHA check.)
)

echo.
if /i "%locale%"=="ru" (
  echo Обновление корневых сертификатов Windows из пакета CA
) else (
  echo Updating Windows root certificates from CA bundle
)
where certutil >nul 2>&1
if errorlevel 1 (
  if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: certutil.exe не найден; пропускаем.) else (echo WARNING: certutil.exe not found; skipping.)
) else (
  set "CA_BUNDLE_URL=https://curl.se/ca/cacert.pem"
  set "TMP_CA=%TEMP_UNQ%\ca_bundle_%RANDOM%.crt"
  "%CURL%" -L -f -s -o "%TMP_CA%" "%CA_BUNDLE_URL%" %PROXY_ARGS%
  if errorlevel 1 (
    if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: не удалось скачать пакет CA; пропускаем.) else (echo WARNING: Failed to download CA bundle; skipping.)
    del /Q "%TMP_CA%" >nul 2>&1
  ) else (
    certutil -f -user -addstore Root "%TMP_CA%" >nul
    set "_RC=%ERRORLEVEL%"
    del /Q "%TMP_CA%" >nul 2>&1
    if not "%_RC%"=="0" (
      if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: certutil не смог импортировать пакет CA ^(код=%_RC%^).) else (echo WARNING: certutil couldn't import CA bundle ^(rc=%_RC%^).)
    ) else (
      if /i "%locale%"=="ru" (echo Корневые сертификаты обновлены.) else (echo Root certificates updated.)
    )
    set "_RC="
  )
  set "TMP_CA="
)

echo.
if /i "%locale%"=="ru" (
  echo Распаковка установщика и удаление ненужных файлов
) else (
  echo Unpacking the installer and deleting unnecessary files
)

"%SEVENZIP%" x -y -o"..\Firefox\App" "%FF_EXE%" >nul 2>&1
set "_7Z_RC=%ERRORLEVEL%"
del /Q "%FF_EXE%" >nul 2>&1
if not "%_7Z_RC%"=="0" (
  if /i "%locale%"=="ru" (echo ОШИБКА: 7-Zip не смог распаковать Firefox. код=%_7Z_RC%.) else (echo ERROR: 7-Zip failed to extract Firefox. rc=%_7Z_RC%.)
  if /I "%arg_skipwait%" NEQ "yes" pause
  popd & exit /b 1
)

REM Keep application.ini (needed to disable updates)
ren "..\Firefox\App\core" "Firefox" 2>nul

REM If we still don't know FFversion, read it from application.ini after extraction
if not defined FFversion (
  for /f "tokens=2 delims==" %%V in ('findstr /I "^Version=" "..\Firefox\App\Firefox\application.ini"') do set "FFversion=%%V"
  if defined FFversion (
    if /i "%locale%"=="ru" (echo Определена версия из application.ini: %FFversion%) else (echo Version detected from application.ini: %FFversion%)
  ) else (
    if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: версия не определена; загрузка языковых пакетов может не сработать.) else (echo WARNING: Version still unknown; language pack downloads may fail.)
  )
)

REM Remove unneeded files safely
del /Q "..\Firefox\App\Firefox\browser\crashreporter-override.ini"
rmdir /S /Q "..\Firefox\App\Firefox\browser\features"
rmdir /S /Q "..\Firefox\App\Firefox\gmp-clearkey"
rmdir /S /Q "..\Firefox\App\Firefox\uninstall"
del /Q "..\Firefox\App\Firefox\Accessible*.*"
del /Q "..\Firefox\App\Firefox\crashreporter.*"
del /Q "..\Firefox\App\Firefox\*.sig"
del /Q "..\Firefox\App\Firefox\maintenanceservice*.*"
del /Q "..\Firefox\App\Firefox\minidump-analyzer.exe"
del /Q "..\Firefox\App\Firefox\precomplete"
del /Q "..\Firefox\App\Firefox\removed-files"
del /Q "..\Firefox\App\Firefox\ucrtbase.dll"
del /Q "..\Firefox\App\Firefox\update*.*"
if not exist "..\Firefox\App\Firefox\browser\extensions\NUL" mkdir "..\Firefox\App\Firefox\browser\extensions" >nul 2>&1
echo OK!

echo.
if /i "%locale%"=="ru" (
  echo Патчинг внутренних файлов браузера для отключения внешних запросов
) else (
  echo Patching browser internal files to disable external requests
)
call :PATCH_OMNI "..\Firefox\App\Firefox\omni.ja"
call :PATCH_OMNI "..\Firefox\App\Firefox\browser\omni.ja"
echo OK!

echo(
if /i "%locale%"=="ru" (echo Отключение автообновлений через application.ini) else (echo Disabling auto-updates via application.ini)
if exist "..\Firefox\App\Firefox\application.ini" (
  "%SED%" -i.bak "s/Enabled=1/Enabled=0/g" "..\Firefox\App\Firefox\application.ini" >nul 2>&1
  "%SED%" -i.bak "s/ServerURL=.*/ServerURL=-/" "..\Firefox\App\Firefox\application.ini" >nul 2>&1
  del /Q "..\Firefox\App\Firefox\application.ini.bak" >nul 2>&1
) else (
  if /i "%locale%"=="ru" (echo ПРЕДУПРЕЖДЕНИЕ: application.ini не найден.) else (echo WARNING: application.ini not found.)
)

echo.
if /i "%locale%"=="ru" (
  echo Загрузка языковых пакетов для ESR %FFversion%
) else (
  echo Downloading language packs for ESR %FFversion%
)
set "XPI_BASE=https://releases.mozilla.org/pub/firefox/releases/%FFversion%/%xOS%/xpi"
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\langpack-en-US@firefox.mozilla.org.xpi" ^
  "%XPI_BASE%/en-US.xpi" %PROXY_ARGS%
if errorlevel 1 ( echo ERROR:%ErrorLevel% & if /I "%arg_skipwait%" NEQ "yes" pause & popd & exit /b 1 ) else ( echo OK! )
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\langpack-ru@firefox.mozilla.org.xpi" ^
  "%XPI_BASE%/ru.xpi" %PROXY_ARGS%
if errorlevel 1 ( echo ERROR:%ErrorLevel% & if /I "%arg_skipwait%" NEQ "yes" pause & popd & exit /b 1 ) else ( echo OK! )

echo.
if /i "%locale%"=="ru" (echo Загрузка словарей) else (echo Downloading dictionaries)
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\en-US@dictionaries.addons.mozilla.org.xpi" ^
  "https://addons.mozilla.org/firefox/downloads/latest/english-us-dictionary/latest.xpi" %PROXY_ARGS%
if errorlevel 1 ( echo ERROR:%ErrorLevel% & if /I "%arg_skipwait%" NEQ "yes" pause & popd & exit /b 1 ) else ( echo OK! )
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\ru@dictionaries.addons.mozilla.org.xpi" ^
  "https://addons.mozilla.org/firefox/downloads/latest/russian-spellchecking-dic-3703/latest.xpi" %PROXY_ARGS%
if errorlevel 1 ( echo ERROR:%ErrorLevel% & if /I "%arg_skipwait%" NEQ "yes" pause & popd & exit /b 1 ) else ( echo OK! )

echo.
if /i "%locale%"=="ru" (
  echo Загрузка дополнения NoScript ^(последняя версия^)
) else (
  echo Downloading NoScript extension ^(latest^)
)
"%CURL%" -L -f -# -o "..\Firefox\App\Firefox\browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi" ^
  "https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi" %PROXY_ARGS%
if errorlevel 1 ( echo ERROR:%ErrorLevel% & if /I "%arg_skipwait%" NEQ "yes" pause & popd & exit /b 1 ) else ( echo OK! )

echo.
if /i "%locale%"=="ru" (
  echo Копирование лаунчера и настроек Firefox
) else (
  echo Copying Firefox launcher and settings
)
mkdir "..\Firefox\App\DefaultData\profile\" >nul 2>&1
xcopy /E /Y "profile\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
if /i "%locale%"=="ru" (
  if exist "profile-ru\*" xcopy /E /Y "profile-ru\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
) else (
  if exist "profile-en\*" xcopy /E /Y "profile-en\*" "..\Firefox\App\DefaultData\profile\" >nul 2>&1
)
if exist "firefox-portable\*" xcopy /E /I /Y "firefox-portable\*" "..\Firefox\" >nul 2>&1
if exist "preferences\*" xcopy /E /Y "preferences\*" "..\Firefox\App\Firefox\" >nul 2>&1
echo OK!

echo.
if /i "%locale%"=="ru" (
  echo Поиск и загрузка I2Pd через GitHub API
) else (
  echo Locating and downloading I2Pd via GitHub API
)
set "TMP_JSON=%TEMP_UNQ%\i2pd_latest_%RANDOM%.json"
"%CURL%" -L -f -s -o "%TMP_JSON%" "https://api.github.com/repos/PurpleI2P/i2pd/releases/latest" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  del /Q "%TMP_JSON%" >nul 2>&1
  if /I "%arg_skipwait%" NEQ "yes" pause
  popd & exit /b 1
)

for /f "usebackq delims=" %%U in (`
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-I2pdAssetUrl.ps1" -JsonPath "%TMP_JSON%" -OsTag "%xOS%"
`) do set "I2PD_URL=%%U"
del /Q "%TMP_JSON%" >nul 2>&1

if not defined I2PD_URL (
  if /i "%locale%"=="ru" (echo ОШИБКА: не удалось получить ссылку i2pd из GitHub API.) else (echo ERROR: couldn't resolve i2pd asset URL from GitHub API.)
  if /I "%arg_skipwait%" NEQ "yes" pause
  popd & exit /b 1
)

"%CURL%" -L -f -# -OJ "%I2PD_URL%" %PROXY_ARGS%
if errorlevel 1 (
  echo ERROR:%ErrorLevel%
  if /I "%arg_skipwait%" NEQ "yes" pause
  popd & exit /b 1
)

for %%F in (i2pd*_%xOS%_mingw.zip) do set "I2PD_ZIP=%%~nxF"
if not defined I2PD_ZIP (
  if /i "%locale%"=="ru" (echo ОШИБКА: архив i2pd не найден после загрузки.) else (echo ERROR: i2pd zip not found after download.)
  if /I "%arg_skipwait%" NEQ "yes" pause
  popd & exit /b 1
)
"%SEVENZIP%" x -y -o"..\i2pd" "%I2PD_ZIP%" i2pd.exe >nul 2>&1
del /Q "%I2PD_ZIP%" >nul 2>&1

echo.
if /i "%locale%"=="ru" (
  echo I2Pd Browser Portable готов к запуску!
) else (
  echo I2Pd Browser Portable is ready to start!
)
if not defined arg_skipwait pause
popd
exit /b


REM ==================== FUNCTIONS ====================

:ENSURE_WINGET
where winget >nul 2>&1 && exit /b 0
exit /b 1

:ENSURE_CURL
where "%CURL%" >nul 2>&1 && exit /b 0
where curl >nul 2>&1 && (set "CURL=curl" & exit /b 0)
where winget >nul 2>&1 || exit /b 0
echo Installing curl via WinGet...
winget install -e --id cURL.cURL --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
where curl >nul 2>&1 && (set "CURL=curl" & exit /b 0)
exit /b 0

:ENSURE_7ZIP
where 7z >nul 2>&1 && (set "SEVENZIP=7z" & exit /b 0)
if exist "%ProgramFiles%\7-Zip\7z.exe" (set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe" & exit /b 0)
if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" (set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe" & exit /b 0)
where winget >nul 2>&1 || exit /b 1
echo Installing 7-Zip via WinGet...
winget install -e --id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
where 7z >nul 2>&1 && (set "SEVENZIP=7z" & exit /b 0)
if exist "%ProgramFiles%\7-Zip\7z.exe" (set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe" & exit /b 0)
if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" (set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe" & exit /b 0)
exit /b 0

:ENSURE_SED
where sed >nul 2>&1 && (set "SED=sed" & exit /b 0)
if exist "%ProgramFiles(x86)%\GnuWin32\bin\sed.exe" (set "SED=%ProgramFiles(x86)%\GnuWin32\bin\sed.exe" & exit /b 0)
if exist "%ProgramFiles%\Git\usr\bin\sed.exe" (set "SED=%ProgramFiles%\Git\usr\bin\sed.exe" & exit /b 0)
where winget >nul 2>&1 || exit /b 1
echo Installing sed via WinGet...
winget install -e --id mbuilov.sed --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
where sed >nul 2>&1 && (set "SED=sed" & exit /b 0)
winget install -e --id GnuWin32.Sed --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
where sed >nul 2>&1 && (set "SED=sed" & exit /b 0)
exit /b 0

:GET_PROXY
REM Robust: ProxyEnable (DWORD) and ProxyServer (SZ, keep as-is even if contains semicolons)
set "PROXY_ARGS="
set "ProxyEnable="
set "ProxyServer="
set "REG_PROXY=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings"
for /f "skip=2 tokens=3" %%A in ('reg query "%REG_PROXY%" /v ProxyEnable 2^>nul') do set "ProxyEnable=%%A"
for /f "skip=2 tokens=2,*" %%A in ('reg query "%REG_PROXY%" /v ProxyServer 2^>nul') do set "ProxyServer=%%B"
if /i "%ProxyEnable%"=="0x1" if defined ProxyServer set "PROXY_ARGS=-x \"%ProxyServer%\""
exit /b 0

:GET_ARCH
REM Detect architecture (mark any native ARM/IA64 as unsupported)
set "PA=%PROCESSOR_ARCHITECTURE%"
set "PW=%PROCESSOR_ARCHITEW6432%"
if not defined PA set "PA=x86"

set "ARCH_SUPPORTED=1"
set "xOS=win32"
if /i "%PA%"=="AMD64" set "xOS=win64"
if /i "%PA%"=="X64"   set "xOS=win64"

REM x86 process on 64-bit hosts (incl ARM64 emu) → prefer win64 payloads where possible
if /i "%PA%"=="x86" if defined PW (
  if /i "%PW%"=="AMD64" set "xOS=win64"
  if /i "%PW%"=="ARM64" set "xOS=win32"
)

if /i "%PA%"=="ARM64" ( set "ARCH_SUPPORTED=0" & set "xOS=unsupported" )
if /i "%PA%"=="ARM"   ( set "ARCH_SUPPORTED=0" & set "xOS=unsupported" )
if /i "%PA%"=="IA64"  ( set "ARCH_SUPPORTED=0" & set "xOS=unsupported" )

set "ARCH_DISPLAY=%xOS% host %PA% %PW%"
if /i "%ARCH_SUPPORTED%"=="0" set "ARCH_DISPLAY=unsupported host %PA% %PW%"
exit /b 0

:GET_LOCALE
for /f "tokens=3" %%a in ('reg query "HKEY_USERS\.DEFAULT\Keyboard Layout\Preload"^|find "REG_SZ"') do (
  if %%a==00000419 (set "locale=ru") else (set "locale=en-US")
  goto :eof
)
goto :eof

:GET_ARGS
set "arg_skipwait="
for %%a in (%*) do (
  if /i "%%a"=="--skipwait" set "arg_skipwait=yes"
)
goto :eof

:PATCH_OMNI
REM %1 = path to omni.ja
set "OMNI=%~1"
if not exist "%OMNI%" (
  if /i "%locale%"=="ru" (echo ВНИМАНИЕ: "%OMNI%" не найден — патчи пропущены.) else (echo WARN: "%OMNI%" not found - skipping patches.)
  exit /b 0
)
set "_TMPDIR=%TEMP_UNQ%\omni_%RANDOM%"
if exist "%_TMPDIR%\NUL" rmdir /S /Q "%_TMPDIR%" >nul 2>&1
mkdir "%_TMPDIR%" >nul 2>&1

"%SEVENZIP%" -bso0 -y x "%OMNI%" -o"%_TMPDIR%" >nul 2>&1
if errorlevel 1 (
  if /i "%locale%"=="ru" (echo ВНИМАНИЕ: не удалось распаковать "%OMNI%".) else (echo WARN: couldn't extract "%OMNI%".)
  rmdir /S /Q "%_TMPDIR%" >nul 2>&1
  exit /b 0
)

set "SEARCHUTILS="
for /r "%_TMPDIR%" %%F in (SearchUtils.sys.mjs) do (set "SEARCHUTILS=%%~fF" & goto :_SU_FOUND)
:_SU_FOUND
if defined SEARCHUTILS (
  "%SED%" -i.bak "s/https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1/http\:\/\/127\.0\.0\.1/" "%SEARCHUTILS%" >nul 2>&1
  if errorlevel 1 (
    if /i "%locale%"=="ru" (echo ВНИМАНИЕ: патч 1 не применился.) else (echo WARN: patch 1 failed.)
  ) else (
    del /Q "%SEARCHUTILS%.bak" >nul 2>&1
    if /i "%locale%"=="ru" (echo Патч 1/2.) else (echo Patched 1/2.)
  )
) else (
  if /i "%locale%"=="ru" (echo ВНИМАНИЕ: SearchUtils.sys.mjs не найден.) else (echo WARN: SearchUtils.sys.mjs not found.)
)

set "APPCONST="
for /r "%_TMPDIR%" %%F in (AppConstants.sys.mjs) do (set "APPCONST=%%~fF" & goto :_AC_FOUND)
:_AC_FOUND
if defined APPCONST (
  "%SED%" -i.bak "s/\"https\:\/\/firefox\.settings\.services\.mozilla\.com\/v1\",$/\"\",/" "%APPCONST%" >nul 2>&1
  if errorlevel 1 (
    if /i "%locale%"=="ru" (echo ВНИМАНИЕ: патч 2 не применился.) else (echo WARN: patch 2 failed.)
  ) else (
    del /Q "%APPCONST%.bak" >nul 2>&1
    if /i "%locale%"=="ru" (echo Патч 2/2.) else (echo Patched 2/2.)
  )
) else (
  if /i "%locale%"=="ru" (echo ВНИМАНИЕ: AppConstants.sys.mjs не найден.) else (echo WARN: AppConstants.sys.mjs not found.)
)

if exist "%_TMPDIR%\NUL" (
  if exist "%OMNI%" ren "%OMNI%" "omni.ja.bak" >nul 2>&1
  "%SEVENZIP%" a -mx0 -tzip "%OMNI%" -r "%_TMPDIR%\*" >nul 2>&1
  set "_rc=%ERRORLEVEL%"
  rmdir /S /Q "%_TMPDIR%" >nul 2>&1
  if "%_rc%"=="0" del /Q "%OMNI%.bak" >nul 2>&1
  set "_rc="
)
exit /b 0
