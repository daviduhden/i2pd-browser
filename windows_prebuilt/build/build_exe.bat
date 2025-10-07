@ECHO OFF
REM Copyright (c) 2013-2025, The PurpleI2P Project
REM ��������� ����� (c) 2013-2025, The PurpleI2P Project
REM This file is part of the Purple i2pd project and is licensed under BSD-3-Clause.
REM ���� ���� � ����� ������� Purple i2pd � ���������������� �� �������� BSD-3-Clause.
REM See the full license text in the LICENSE file at the top of the project tree.
REM ������ ����� �������� ��. � ����� LICENSE � ����� �������.

echo Creating a 7z archive with the bundle...
echo ������� 7z ����� � �������...
REM The result is a .7z archive containing the folders Firefox, i2pd, and the files StartI2PdBrowser.bat and browser.ico from the src folder one level up.
REM �� ������ �������� 7z �����, � ������� ����� ������ ����� Firefox, i2pd � ����� StartI2PdBrowser.bat � browser.ico �� ����� src ������� ����.
7z a -t7z -m0=lzma2:d192m -mx=9 -aoa -mfb=273 -md=128m -ms=on -- I2PdBrowserPortable.7z ..\..\windows\Firefox ..\..\windows\i2pd ..\src\StartI2PdBrowser.bat ..\src\browser.ico

echo Creating 7z SFX (self-extracting archive)...
echo ������� 7z SFX - ��������������������� �����...
REM Produces a self-extracting archive; then the intermediate .7z is removed.
REM �� ������ �������� ��������������������� �����, ����� ���� ������������� .7z ���������.
copy /b 7zsd_LZMA2_i2pdbrowser_1.3.3.sfx + config.txt + I2PdBrowserPortable.7z I2PdBrowserPortable_1.3.3.exe >> NUL
del I2PdBrowserPortable.7z >> NUL

echo Done!
echo ������!
pause