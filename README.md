# I2Pd Browser

This is a script-based builder of the I2Pd Browser for Linux-based systems. Any contribution is highly appreciated.

> It might also work on BSD-based systems but has not yet been tested.

The I2Pd browser is a pre-configured version of Firefox ESR for use on the I2P network. It is the fastest and easiest way to start surfing the web on the Invisible Internet.

## Features

- **Auto-detecting system architecture**: The script automatically detects the system architecture to configure Firefox accordingly.
- **Pre-configuring Firefox**: Firefox is pre-configured for use with I2Pd, including necessary settings adjustments.
- **Automatic downloads**:
  - **NoScript extension**: The script downloads and installs the NoScript extension for added security.
  - **Language packs**: Language packs for Firefox are automatically downloaded.
- **Checksum verification**: Ensures the integrity of the downloaded Firefox package.
- **Environment preservation**: Maintains the environment variables and arguments when executing the `start-i2pd-browser` script, ensuring consistent configuration and behavior.
- **Self-modifying .desktop file**:
  - Supports relocation of the .desktop file.
  - Can register and unregister itself as a desktop application for the current user.
  - Supports being used as a portable app.

## Dependencies

Ensure you have the following dependencies installed on your Linux system before using the I2Pd Browser:

- **I2Pd**: Follow the [installation guide](https://i2pd.readthedocs.io/en/latest/user-guide/install/#linux)
- **curl**: Used for downloading files
- **tar**: For extracting compressed files
- **screen**: Required for managing detached sessions

## How to Use It

1. Install the dependencies if they are not already installed.
    
3. Clone the `i2pd-browser` repository:

```
git clone https://github.com/daviduhden/i2pd-browser/
```
```
cd i2pd-browser
```

4. Build the pre-configured Firefox using the `build` shell script from the `build` directory:

```
cd build
```
```
./build
```

5. Run I2Pd by executing the `i2pd` shell script from `i2pd` directory:

```
cd ../i2pd
```
```
./i2pd
```

6. Run Firefox by executing the `start-i2pd-browser.desktop` desktop entry:

```
cd ../
```
```
./start-i2pd-browser.desktop
```

## Additional information

- The `i2pd` shell script from the `i2pd` directory starts a `screen` session with I2Pd in it.
- To stop the I2Pd router, you can execute the commands `Start graceful shutdown` or `Force shutdown` from the I2Pd web console page: `http://127.0.0.1:7070/?page=commands`.
- The pre-compiled i2pd binaries available for Unix-like operating systems such as Linux and *BSD do not have built-in support for UPnP by default, which makes it very inconvenient for client use. If you want UPnP to work you need to compile I2Pd yourself. For more information refer to the [official documentation](https://i2pd.readthedocs.io/en/latest/devs/building/unix/).

