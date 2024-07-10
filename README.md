I2Pd Browser
=====
This is a script-based builder of the I2Pd Browser for Linux-based systems.

The I2Pd browser is a pre-configured version of Firefox ESR for its use on the I2P network, it is the fastest and easiest way to start surfing the web on the Invisible Internet.

What works now
-----
* Auto detecting system language
* Auto detecting system architecture
* Pre-configuring Firefox to use with I2Pd
* Auto downloading the NoScript extension

How to use it
-----
1. Build the pre-configured Firefox using the `./build` script from the `build` directory
2. Run I2Pd by executing `./i2pd` from `i2pd` folder
3. Run Firefox by executing `./start-i2pd-browser.desktop`

Additional info
-----
`./i2pd` from `i2pd` folder starts a screen session with i2pd in it.
To stop the i2pd router you can use the commands `Start graceful shutdown` or `Force shutdown` from i2pd webconsole page `http://127.0.0.1:7070/?page=commands`

Disclaimer
-----
To use this browser you need to have previously [installed](https://i2pd.readthedocs.io/en/latest/user-guide/install/#linux) I2Pd on your Linux system.
