# I2Pd Browser

This is a script-based builder of the I2Pd Browser for Linux and
Windows, supporting x86_64, i686 and arm64 (aarch64) architectures.
Any contribution is highly appreciated.

On Linux, Mozilla no longer publishes 32-bit (i686) Firefox ESR builds
in the current branch, so the default product cannot be resolved there.
Use `ESR_PRODUCT=firefox-esr-latest` to build for 32-bit Linux (32-bit
Windows is still published in the current branch).

The I2Pd Browser is a pre-configured version of Firefox ESR for use on
the I2P network. It works against a generic "I2P router" abstraction,
so it can use either of the two supported router implementations, from
a system installation or from a managed (vendored) copy.

## Supported I2P routers

| Backend    | Implementation | Default HTTP proxy | Default SOCKS | Console               |
|------------|----------------|--------------------|---------------|-----------------------|
| `i2pd`     | C++            | 127.0.0.1:4444     | 127.0.0.1:4447| http://127.0.0.1:7070/|
| `i2p-java` | Java (I2P)     | 127.0.0.1:4444     | 127.0.0.1:4447| http://127.0.0.1:7657/|

The HTTP and SOCKS ports are intentionally normalized so the Firefox
configuration does not depend on the selected router. The router
console deliberately keeps each implementation's native port.

`i2pd` remains the default backend for compatibility with existing
installations.

## Features

- **Choice of I2P router**: `i2pd` (C++) or I2P (Java), selected once
  during installation and stored for later commands.
- **Auto-detecting system architecture**: The builder configures
  Firefox for the detected architecture.
- **Pre-configuring Firefox**: Firefox is pre-configured for use with
  I2P, including the required proxy settings.
- **Aggressive hardening profile**: Non-essential browser capabilities
  are disabled by default to minimize attack surface on Firefox ESR.
- **NoScript extension**: The builder downloads and installs the
  NoScript extension for added security.
- **Checksum verification**: Ensures the integrity of the downloaded
  Firefox package.
- **Vendored router configuration**: A maintained configuration is
  shipped for each backend.
- **Self-modifying .desktop file**: Supports relocation and
  registration as a desktop application.

## Dependencies

Common dependencies:

- **curl**: Used for downloading Firefox.
- **tar**: For extracting compressed files.
- **screen**: Required for managing detached router sessions.

Backend specific dependencies:

- **i2pd (C++)**: the `i2pd` package. No Java runtime is required.
- **I2P (Java)**: a Java runtime and the I2P router package (or an I2P
  installation in `/usr/share/i2p`). `i2pd` is not required.

Installation examples:

```sh
# i2pd
sudo apt install i2pd screen curl tar

# I2P (Java)
sudo apt install i2p default-jre-headless screen curl tar
```

The installer can also install the missing packages for the selected
backend with `--install-deps` (using the system package manager).

On Windows the same operations are provided by the PowerShell scripts
(`install.ps1`, `i2pd/i2pd.ps1`, `i2p-java/i2p-java.ps1`), run through
the matching `.cmd` launchers (`install.cmd`, `i2pd\i2pd.cmd`,
`i2p-java\i2p-java.cmd`); they use `winget` for dependencies.

With `--install-deps` the installer installs the missing router packages
for the selected backend: `winget` on Windows, and on Linux Homebrew
(`brew`) when available, otherwise the distribution package manager
(`apt`, `dnf`, `pacman` or `zypper`). This is opt-in.

Instead of using a system package, the installer can download a managed
copy of the latest stable router release into `vendor/` with
`--router-source=vendored` (see below).

## Installation

1. Clone or download this repository:

	```sh
	git clone https://github.com/daviduhden/i2pd-browser.git
	```

2. Run the installer from the repository root:

	```sh
	cd i2pd-browser
	./install.bash
	```

	It asks which I2P router to use and where to get it from:

	```
	Select I2P router:

	  1) i2pd (C++)
	  2) I2P (Java)

	Choice [1]:
	Select I2P router source:

	  1) system packages (already installed)
	  2) vendored (download the latest stable release)

	Choice [1]:
	```

	The source question is only asked on the first interactive install;
	the answer is stored in `i2pd-browser.conf`.

3. Build the pre-configured Firefox if the installer did not do it, or
   rebuild it at any time:

	```sh
	cd build
	./build.bash
	```

4. Start the browser with the desktop entry:

	```sh
	cd ../
	./start-i2pd-browser.desktop
	```

### Non-interactive installation

The backend can be selected without prompting, for CI, scripts and
package builds:

```sh
./install.bash --i2p-router=i2pd
./install.bash --i2p-router=i2p-java

# Use a managed copy of the latest stable router release instead of a
# system installation:
./install.bash --i2p-router=i2pd --router-source=vendored
./install.bash --i2p-router=i2p-java --router-source=vendored
```

Additional options:

- `--i2p-router=NAME`: select the backend (`i2pd` or `i2p-java`).
- `--router-source=SRC`: use the system install (`system`, default) or
  a managed copy downloaded by I2Pd Browser (`vendored`).
- `--non-interactive`: never prompt; use the stored or default values.
- `--no-browser`: do not build the Firefox ESR bundle.
- `--no-start`: do not start the router after install/configure.
- `--install-deps`: install missing router packages (opt-in).
- `--no-install-deps`: do not install missing router packages (default).

## Managing the router

The installer is also the router manager:

```sh
./install.bash status     # Show the selected router and its state
./install.bash start      # Start the selected router
./install.bash stop       # Stop the router started by I2Pd Browser
./install.bash restart    # Restart the managed router
./install.bash console    # Open the backend's router console
./install.bash detect     # List the detected backends
```

The per-backend launchers are still available and behave as before:

```sh
./i2pd/i2pd.bash             # Start i2pd (C++)
./i2p-java/i2p-java.bash     # Start I2P (Java)
```

The router is never stopped if it was started outside I2Pd Browser
(for example by a system service); in that case you are told to use
the system service or the router's own tooling.

## Changing the backend

The selection is stored in `i2pd-browser.conf` in the repository root.
Change it with:

```sh
./install.bash configure --i2p-router=i2p-java
./install.bash configure --i2p-router=i2pd
```

When switching, the previously managed instance is stopped, the new
backend configuration is generated, the selection is persisted and the
new router is started and checked. Router data (keys, netDb, ...) is
never migrated between backends; they are independent.

## Windows

The same backend abstraction is available as PowerShell scripts, each
with a `.cmd` launcher that is not subject to the execution policy,
prefers PowerShell 7 (`pwsh`) when present, falls back to Windows
PowerShell, and bypasses the policy for its own invocation:

```bat
install.cmd
install.cmd --i2p-router=i2p-java
i2pd\i2pd.cmd
i2p-java\i2p-java.cmd
```

The equivalent explicit PowerShell invocations are also supported:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
powershell -ExecutionPolicy Bypass -File install.ps1 --i2p-router=i2p-java
powershell -ExecutionPolicy Bypass -File i2pd/i2pd.ps1
powershell -ExecutionPolicy Bypass -File i2p-java/i2p-java.ps1
```

On Windows the router is started as a hidden background process and a
PID file is used instead of `screen`. The Firefox bundle is built with
`build/build.ps1` and launched with
`build/scripts/start-i2pd-browser.ps1`.

Because Windows Defender has repeatedly flagged i2pd builds as malware
(false positive), the i2pd backend adds a best-effort Defender
exclusion for `i2pd.exe` and the i2pd directories whenever it prepares
its configuration. Adding an exclusion requires administrator rights;
if it is not possible, a warning is printed and nothing else changes.

## Configuration layout

```
lib/
  router.bash / router.ps1        Shared I2P router abstraction
  backends/
    i2pd.bash / i2pd.ps1          i2pd (C++) specific logic
    i2p-java.bash / i2p-java.ps1  I2P (Java) specific logic
i2pd/                            Vendored i2pd configuration + launcher
i2p-java/
  config/                        Vendored I2P (Java) configuration
  data/                          Effective config + runtime state (ignored)
  i2p-java.bash / i2p-java.ps1   Launcher
vendor/                          Managed router builds (ignored)
```

- `install.bash` and `install.ps1` are the installers and managers.
- `build/build.bash` and `build/build.ps1` build the Firefox bundle.
- Every PowerShell entry point has a sibling `.cmd` launcher
  (`install.cmd`, `build\build.cmd`, `i2pd\i2pd.cmd`,
  `i2p-java\i2p-java.cmd`, `build\scripts\start-i2pd-browser.cmd`) that
  bypasses the execution policy for its own invocation.

- `i2pd/` keeps its configuration and runtime state together, which is
  the historical behaviour of this project.
- The I2P (Java) backend keeps the vendored configuration in
  `i2p-java/config/` and the effective configuration plus runtime state
  in `i2p-java/data/`. The launcher passes `-Di2p.dir.config` to the
  router, so the user's global `~/.i2p` is never touched.
- Generated state (`i2p-java/data/`, i2pd `netDb/`, keys, logs) is
  ignored by Git and must not be committed.

All vendored files contain only the values I2Pd Browser must control
explicitly. Router state, keys, identities and caches are never
vendored.

## Ports

| Service        | i2pd              | I2P (Java)        | Used by Firefox |
|----------------|-------------------|-------------------|-----------------|
| HTTP proxy     | 127.0.0.1:4444    | 127.0.0.1:4444    | yes             |
| SOCKS proxy    | 127.0.0.1:4447    | 127.0.0.1:4447    | no              |
| Router console | 127.0.0.1:7070    | 127.0.0.1:7657    | no              |
| SAM bridge     | 127.0.0.1:7656    | not started       | no              |

All services listen on the loopback interface only. No administrative
interface or proxy is exposed to the LAN.

Firefox always uses `127.0.0.1:4444` and never falls back to a direct
connection: `network.proxy.failover_direct` is locked to `false`.

## Additional information

- To stop the router you can also use the console page of the selected
  backend (see the table above).
- The pre-compiled i2pd binaries available for Unix-like operating
  systems such as Linux and *BSD do not have built-in support for UPnP
  by default, which makes it very inconvenient for client use. If you
  want UPnP to work you need to compile I2Pd yourself. For more
  information refer to the
  [official documentation](https://i2pd.readthedocs.io/en/latest/devs/building/unix/).

## Troubleshooting

- **The router is not detected.** Check `./install.bash detect` and
  install the missing backend (`--install-deps`).
- **The browser cannot connect.** Confirm the router is running with
  `./install.bash status` and that the HTTP proxy port (4444) is
  reachable. The proxy may take a moment to start after the router
  starts.
- **The router is "misconfigured".** A runtime dependency is missing
  (for example `screen`, or `java` for the Java backend).
- **Wrong backend selected.** Change it with
  `./install.bash configure --i2p-router=<i2pd|i2p-java>`.

## Licensing

The scripts and configuration files in this repository are licensed
under the BSD 3-Clause "New" or "Revised" License; see the `LICENSE`
file.

The routers downloaded or used by these scripts keep their own terms:

- [i2pd](https://github.com/PurpleI2P/i2pd/) is licensed under the BSD
  3-Clause "New" or "Revised" License.
- [I2P (Java)](https://github.com/i2p/i2p.i2p/) is public domain except
  for the components listed in its `LICENSE.txt`; for example the
  I2PTunnel HTTP and SOCKS proxies (used by this project) are GPLv2 or
  later with an exception, I2PSnark and SusiDNS/SusiMail are GPLv2 or
  later, and several bundled third-party libraries keep their own
  licenses.

The Firefox ESR bundle and the NoScript extension downloaded by the
builder are subject to their own terms and conditions.
