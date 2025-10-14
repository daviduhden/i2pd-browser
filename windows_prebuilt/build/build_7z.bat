@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM This file is part of the Purple i2pd project and is licensed under BSD-3-Clause.
REM See the full license text in the LICENSE file at the top of the project tree

echo Creating a 7z archive with the bundle...
REM The result is a .7z archive containing the folders Firefox, i2pd, and the file StartI2PdBrowser.bat from the src folder one level up.
7z a -t7z -m0=lzma2:d192m -mx=9 -aoa -mfb=273 -md=128m -ms=on -- I2PdBrowserPortable_1.3.3.7z ..\..\windows\Firefox ..\..\windows\i2pd ..\src\StartI2PdBrowser.bat

echo Done!
pause