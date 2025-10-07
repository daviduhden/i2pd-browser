@ECHO OFF
REM Copyright (c) 2013-2019, The PurpleI2P Project
REM This file is part of Purple i2pd project and licensed under BSD3
REM See full license text in LICENSE file at top of project tree

title Starting I2Pd Browser / Запуск I2Pd Браузера
set $pause=ping.exe 0.0.0.0 -n
set $cd=%CD%
ver| find "6." >nul && set $pause=timeout.exe /t

set fire=firefox.exe
set port=FirefoxPortable.exe
set i2pd=i2pd.exe

REM Check if Firefox exists / Проверка наличия Firefox
if not exist Firefox (
    echo Firefox not found... Start building... / Firefox не найден... Начинаю сборку...
    pushd build
    call build.cmd --skipwait
    popd
)

REM Kill FirefoxPortable if running / Завершение FirefoxPortable, если запущен
taskList|find /i "%port%">nul&&(taskkill /im "%port%" /t>nul)&&(%$pause% 2 >nul)
REM taskList|find /i "%fire%">nul&&(taskkill /im "%fire%" >nul)
REM Check if i2pd is running / Проверка, запущен ли i2pd
taskList|find /i "%i2pd%">nul&&(goto runfox)||(goto starti2p)

:starti2p
cd i2pd
start "" "%i2pd%"

echo i2pd Browser starting / Запуск i2pd Браузера
echo Please wait / Пожалуйста, подождите
echo -------------------------------------
for /L %%B in (0,1,35) do (call :EchoWithoutCrLf "." && %$pause% 2 >nul)
echo .
echo -------------------------------------
echo Welcome to I2P Network / Добро пожаловать в сеть I2P
cd %$cd%

:runfox
cd Firefox
start "" "%port%"
cd %$cd%
exit /b 0

rem ==========================================================================
rem EchoWithoutCrLf procedure / Процедура EchoWithoutCrLf
rem
rem %1 : text to output / текст для вывода.
rem ==========================================================================
:EchoWithoutCrLf
    <nul set /p strTemp=%~1
    exit /b 0
rem ==========================================================================
