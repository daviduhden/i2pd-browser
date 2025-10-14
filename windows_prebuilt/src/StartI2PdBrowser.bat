@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM See full license text in LICENSE file at top of project tree

setlocal EnableExtensions EnableDelayedExpansion

REM Show Russian output ONLY if the system UI language is Russian
set "SHOW_RU=0"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Control Panel\International" /v LocaleName ^| find "LocaleName"') do set "LOCALE_NAME=%%B"
if defined LOCALE_NAME (
  set "LC2=!LOCALE_NAME:~0,2!"
  if /i "!LC2!"=="ru" set "SHOW_RU=1"
)

REM Switch to UTF-8 only when printing Russian (avoid mojibake)
if "%SHOW_RU%"=="1" chcp 65001 >nul

title Starting I2Pd Browser
if "%SHOW_RU%"=="1" title Starting I2Pd Browser / Запуск I2Pd Браузера

set "$pause=ping.exe 0.0.0.0 -n"
set "$cd=%CD%"
ver | find "6." >nul && set "$pause=timeout.exe /t"

set "fire=firefox.exe"
set "port=FirefoxPortable.exe"
set "i2pd=i2pd.exe"

REM Check if Firefox exists
if not exist Firefox (
    echo Firefox not found... Starting build...
    if "%SHOW_RU%"=="1" echo Firefox не найден... Начинаю сборку...
    pushd build
    call build.cmd --skipwait
    popd
)

REM Kill FirefoxPortable if running
tasklist | find /i "%port%" >nul && (taskkill /im "%port%" /t >nul) && (%$pause% 2 >nul)
REM tasklist | find /i "%fire%" >nul && (taskkill /im "%fire%" >nul)

REM Check if i2pd is running
tasklist | find /i "%i2pd%" >nul && (goto runfox) || (goto starti2p)

:starti2p
cd i2pd
start "" "%i2pd%"

echo i2pd Browser starting...
if "%SHOW_RU%"=="1" echo Запуск i2pd Браузера...
echo Please wait
if "%SHOW_RU%"=="1" echo Пожалуйста, подождите
echo -------------------------------------
for /L %%B in (0,1,35) do (call :EchoWithoutCrLf "." && %$pause% 2 >nul)
echo .
echo -------------------------------------
echo Welcome to I2P Network
if "%SHOW_RU%"=="1" echo Добро пожаловать в сеть I2P
cd "%$cd%"

:runfox
cd Firefox
start "" "%port%"
cd "%$cd%"
exit /b 0

rem ==========================================================================
rem EchoWithoutCrLf procedure
rem %1 : text to output
rem ==========================================================================
:EchoWithoutCrLf
    <nul set /p strTemp=%~1
    exit /b 0
rem ==========================================================================