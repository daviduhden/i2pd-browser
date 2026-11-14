# I2P (Java) backend

This directory contains everything specific to the I2P (Java) router
backend.

    config/   Vendored, versioned configuration (static files only).
    data/     Effective configuration and runtime state. Seeded from
              config/ by the installer or launcher when a file is
              missing, then ignored by Git. Seeding never overwrites existing
              files. Explicit validated proxy overrides update effective
              endpoint settings; other seed changes require deliberate
              maintenance of the existing data/ configuration.

The `i2p-java.bash` launcher starts the system I2P installation directly
with `-Di2p.dir.config=data`, so the router never touches the user's
global `~/.i2p` configuration.

## Differences from the i2pd backend

* i2pd keeps its configuration and its runtime state together in the
  `i2pd/` directory (legacy behaviour). The I2P (Java) backend keeps
  the vendored configuration in `config/` and the effective
  configuration plus runtime state in `data/`.
* The default upstream ports already match: the HTTP proxy listens on
  127.0.0.1:4444 and SOCKS on 127.0.0.1:4447 in both backends, which
  is what the Firefox profile expects.
* The router console listens on 127.0.0.1:7657 for I2P (Java) and on
  127.0.0.1:7070 for i2pd.
* The I2P (Java) SAM bridge is not started because the browser does
  not use it; i2pd currently enables it.

All vendored files are limited to what I2Pd Browser must control
explicitly. Values that merely repeat upstream defaults are omitted.

## Verified managed installation

Before downloading a managed installer, set `I2P_INSTALLER_SHA512` to a trusted
128-character SHA-512 digest for that exact installer. Obtain the digest
independently; a hash of an unverified download does not establish trust.
See [download verification](../docs/security-and-maintenance.md) for upstream
signature verification and its trust requirements. Automatic PGP verification
is not implemented. The console installer requires an interactive terminal;
`--non-interactive` cannot provision a new managed Java installation.

Explicit proxy overrides are validated before effective files are changed.
Related endpoint changes are prepared as a coherent set, with restoration on
ordinary write failures. Existing effective files remain user state: unsafe or
ambiguous listener configuration is rejected, not silently reset. A power failure
may still require recovery from preserved configuration or backup evidence.
