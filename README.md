I2Pd Browser
=====
This is a script-based builder of the I2Pd Browser for Linux

What works now
-----
* Auto detecting system language
* Auto detecting architecture
* Pre-configuring Firefox to use with I2Pd
* Auto downloading NoScript extension

How to use it
-----
1. Build pre-configured Firefox using script `./build` from `build` folder
2. Run I2Pd by executing `./i2pd` from `i2pd` folder
3. Run Firefox by executing `./start-i2pd-browser.desktop`

Additional info
-----
`./i2pd` from `i2pd` folder starts a screen session with i2pd in it.
To stop the i2pd router you can use the commands `Start graceful shutdown` or `Force shutdown`
from i2pd webconsole page `http://127.0.0.1:7070/?page=commands`

Disclaimer
-----
To use this browser you need to have previously [installed](https://i2pd.readthedocs.io/en/latest/user-guide/install/#linux) I2Pd on your Linux system.
