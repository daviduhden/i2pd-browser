# I2Pd Browser

This is a script-based builder of the I2Pd Browser for Linux-based systems.

The I2Pd browser is a pre-configured version of Firefox ESR for use on the I2P network. It is the fastest and easiest way to start surfing the web on the Invisible Internet.

## Features

- Auto-detecting system language
- Auto-detecting system architecture
- Pre-configuring Firefox to use with I2Pd
- Auto-downloading the NoScript extension

## Dependencies

Ensure you have the following dependencies installed on your Linux system before using the I2Pd Browser:

- **I2Pd**: Follow the [installation guide](https://i2pd.readthedocs.io/en/latest/user-guide/install/#linux)
- **curl**: Used for downloading files
- **screen**: Required for managing detached sessions
- **tar**: For extracting compressed files

## How to Use It

1. Build the pre-configured Firefox using the `./build` shell script from the `build` directory.
2. Run I2Pd by executing the `./i2pd` shell script from the `i2pd` directory.
3. Run Firefox by executing the `./start-i2pd-browser.desktop` desktop entry.

## Additional Info

- `./i2pd` from the `i2pd` folder starts a screen session with I2Pd in it.
- To stop the I2Pd router, you can use the commands `Start graceful shutdown` or `Force shutdown` from the I2Pd web console page: `http://127.0.0.1:7070/?page=commands`.

