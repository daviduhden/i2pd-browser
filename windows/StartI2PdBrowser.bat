@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM See full license text in LICENSE file at top of project tree

REM -------------------- Environment --------------------
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

REM Always work from this script folder (stable relative paths)
pushd "%~dp0"

REM -------------------- Config -------------------------
REM seconds to wait for i2pd to appear
set "MAX_WAIT_I2PD=30"
REM 1 = also kill firefox.exe (besides FirefoxPortable.exe)
set "KILL_FIREFOX_CORE=0"

REM -------------------- Sleep helpers ------------------
REM Define 1s/2s sleep commands
where timeout >nul 2>&1 && (
  set "SLEEP1=timeout /t 1 /nobreak >nul"
  set "SLEEP2=timeout /t 2 /nobreak >nul"
) || (
  REM ping N takes ~N-1 seconds; use +1 to approximate
  set "SLEEP1=ping -n 2 127.0.0.1 >nul"
  set "SLEEP2=ping -n 3 127.0.0.1 >nul"
)

REM -------------------- Locale detection ---------------
set "SHOW_RU=0"
set "LOCALE_NAME="
for /f "tokens=2,*" %%A in ('
  reg query "HKCU\Control Panel\International" /v LocaleName 2^>nul ^| find "LocaleName"
') do set "LOCALE_NAME=%%B"
if defined LOCALE_NAME (
  set "LC2=!LOCALE_NAME:~0,2!"
  if /i "!LC2!"=="ru" set "SHOW_RU=1"
)

REM -------------------- Banner/title -------------------
title Starting I2Pd Browser
if "%SHOW_RU%"=="1" title Запуск I2Pd Браузера

REM -------------------- Paths --------------------------
set "BASE=%CD%"
set "DIR_FF=%BASE%\Firefox"
set "DIR_I2PD=%BASE%\i2pd"
set "EXE_PORTABLE=%DIR_FF%\FirefoxPortable.exe"
set "EXE_CORE=%DIR_FF%\App\Firefox\firefox.exe"
set "EXE_I2PD=%DIR_I2PD%\i2pd.exe"
set "BUILD_DIR=%BASE%\build"
set "BUILD_CMD=%BUILD_DIR%\build.cmd"

REM -------------------- Ensure Firefox -----------------
if not exist "%DIR_FF%" (
  echo Firefox not found... Starting build...
  if "%SHOW_RU%"=="1" echo Firefox не найден... Начинаю сборку...
  if not exist "%BUILD_CMD%" (
    echo ERROR: build.cmd not found at "%BUILD_CMD%"
    if "%SHOW_RU%"=="1" echo ОШИБКА: build.cmd не найден по пути "%BUILD_CMD%"
    goto abort
  )
  pushd "%BUILD_DIR%"
  call "%BUILD_CMD%" --skipwait
  set "_rc=%ERRORLEVEL%"
  popd
  if not "%_rc%"=="0" (
    echo ERROR: build failed ^(rc=%_rc%^)
    if "%SHOW_RU%"=="1" echo ОШИБКА: сборка завершилась неуспешно ^(код=%_rc%^)
    goto abort
  )
)

REM -------------------- Kill FirefoxPortable -----------
for /f "tokens=*" %%P in ('tasklist ^| find /i "FirefoxPortable.exe"') do (
  taskkill /im "FirefoxPortable.exe" /t /f >nul 2>&1
  %SLEEP2%
)
if "%KILL_FIREFOX_CORE%"=="1" (
  for /f "tokens=*" %%P in ('tasklist ^| find /i "firefox.exe"') do (
    taskkill /im "firefox.exe" /t /f >nul 2>&1
    %SLEEP2%
  )
)

REM -------------------- Check if I2Pd is running ------------------
tasklist | find /i "i2pd.exe" >nul && goto runfox

REM Start i2pd if binary exists
if not exist "%EXE_I2PD%" (
  echo ERROR: i2pd.exe not found at "%EXE_I2PD%"
  if "%SHOW_RU%"=="1" echo ОШИБКА: i2pd.exe не найден по пути "%EXE_I2PD%"
  goto abort
)

pushd "%DIR_I2PD%"
start "" /min "%EXE_I2PD%"
popd

echo I2Pd Browser starting...
if "%SHOW_RU%"=="1" echo Запуск I2Pd Браузера...
echo Please wait
if "%SHOW_RU%"=="1" echo Пожалуйста, подождите
echo -------------------------------------

REM Wait loop: stop early if process appears, else timeout
set /a T=0
:wait_loop
tasklist | find /i "i2pd.exe" >nul && goto i2pd_up
<nul set /p ="." 
%SLEEP1%
set /a T+=1
if %T% LSS %MAX_WAIT_I2PD% goto wait_loop
echo.
echo WARNING: i2pd didn^'t appear within %MAX_WAIT_I2PD%s; continuing anyway.
if "%SHOW_RU%"=="1" echo ВНИМАНИЕ: i2pd не появился за %MAX_WAIT_I2PD%с; продолжаем.
goto after_wait

:i2pd_up
REM Give a few extra seconds for warm-up
for /l %%# in (1,1,5) do (
  <nul set /p ="." 
  %SLEEP1%
)

:after_wait
echo.
echo -------------------------------------
echo Welcome to I2P Network
if "%SHOW_RU%"=="1" echo Добро пожаловать в сеть I2P

REM -------------------- Launch Firefox -----------------
:runfox
set "FF_LAUNCH="
if exist "%EXE_PORTABLE%" set "FF_LAUNCH=%EXE_PORTABLE%"
if not defined FF_LAUNCH if exist "%EXE_CORE%" set "FF_LAUNCH=%EXE_CORE%"

if not defined FF_LAUNCH (
  echo ERROR: Firefox launcher not found in "%EXE_PORTABLE%" or "%EXE_CORE%"
  if "%SHOW_RU%"=="1" echo ОШИБКА: исполняемый файл Firefox не найден.
  goto abort
)

pushd "%DIR_FF%"
start "" "%FF_LAUNCH%"
popd
goto success

REM -------------------- End paths ----------------------
:success
popd
exit /b 0

:abort
popd
exit /b 1