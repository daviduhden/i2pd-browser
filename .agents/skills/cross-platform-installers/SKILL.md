---
name: cross-platform-installers
description: Change the Linux and Windows installers and management commands. Use when editing install.bash, install.ps1, .cmd shims, PowerShell ports, CLI options, exit codes, or i2pd-browser.conf handling.
---

# Cross-platform installers

## When to use

Use this skill for the installer/manager entry points and their
launchers, especially when a change must behave the same on Bash and
PowerShell. Use `i2p-router-integration` for backend logic and
`firefox-esr-bundling` for the Firefox build itself.

## Project facts

- `install.bash` and `install.ps1` accept:
  `install`, `configure`, `start`, `stop`, `restart`, `status`,
  `console`, and `detect`. `install` is the default command.
- Options: `--i2p-router=NAME`, `--language=LANG`,
  `--router-source=SRC`, `--non-interactive`, `--no-browser`,
  `--no-start`, `--install-deps`, `--no-install-deps`, and
  `-h`/`--help`. Both `--opt=value` and `--opt value` forms exist where
  the parser implements them.
- Exit codes are intentional: `2` for CLI or language misuse, `1` for
  backend/configuration/build/start/stop failures, and `0` for help,
  warnings, already-running start, and not-running stop.
- `i2pd-browser.conf` stores exactly `I2P_ROUTER`,
  `I2P_ROUTER_SOURCE`, and `I2PD_BROWSER_LANGUAGE`. It is ignored by
  Git. Writes preserve unknown lines. Bash uses a temporary file and
  rename; PowerShell uses a temporary file and atomic replace.
- The Bash config reader tolerates whitespace around `=` and trims
  trailing whitespace. The PowerShell reader now does the same.
- `install` and `configure` prepare and verify the requested backend
  before persisting the new selection, so a failed dependency step does
  not silently switch the stored backend.
- `.cmd` files are CRLF, prefer `pwsh.exe` when available, fall back to
  `powershell.exe`, use `-NoProfile -ExecutionPolicy Bypass` for that
  invocation only, forward `%*`, and return `%ERRORLEVEL%`.
- The Bash installer uses `screen` on Linux. The PowerShell backends use
  hidden processes and PID files on Windows. `--install-deps` is the
  only path that installs packages; it may use `sudo` or `winget`.
- The i2pd Windows backend adds a best-effort Defender exclusion for
  `i2pd.exe` and its directories. It is not a security control and must
  never become a fatal requirement.

## Procedure

1. Read both entry points and the shared libraries they source. Check
   `git diff` and existing config files before changing behavior.
2. Change the Bash and PowerShell parsers together. Keep command names,
   option names, defaults, and exit codes aligned. Do not add an option
   to one platform without a deliberate, documented behavior on the
   other.
3. Preserve unknown lines in `i2pd-browser.conf` and keep the write
   atomic. Validate backend, source, and locale before writing.
4. Keep `--install-deps` opt-in. Do not add implicit elevation, package
   repository changes, or background service changes.
5. Keep `.cmd` files CRLF. Do not remove `-NoProfile`, the per-call
   execution-policy bypass, the `pwsh` preference, or exit-code
   propagation.
6. Keep PowerShell paths absolute or quoted. The Windows launcher uses
   an absolute profile path; do not revert to a relative `data` path.
7. Update `README.md` and the relevant skill when CLI behavior or
   platform support changes.
8. If a change affects user-visible messages, update all four catalogs
   and the i18n tests (see `localization-maintenance`).

## Validation

Static checks for the Bash side:

```sh
bash -n install.bash lib/router.bash lib/i18n.bash lib/backends/*.bash
shellcheck install.bash lib/router.bash lib/i18n.bash lib/backends/*.bash
shfmt -d install.bash lib/router.bash lib/i18n.bash lib/backends/*.bash
bash tests/test-i18n.bash
```

On a host with PowerShell, parse and test the ports:

```powershell
$files = @(
    'install.ps1',
    'lib/router.ps1',
    'lib/i18n.ps1',
    'lib/backends/i2pd.ps1',
    'lib/backends/i2p-java.ps1',
    'build/build.ps1',
    'build/scripts/start-i2pd-browser.ps1',
    'tests/test-i18n.ps1'
)
foreach ($file in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $file), [ref]$tokens, [ref]$errors)
    if ($errors) { $errors | ForEach-Object Message; exit 1 }
}
pwsh -NoProfile -File tests/test-i18n.ps1
```

Check `.cmd` line endings and the shim contract:

```sh
file install.cmd build/build.cmd i2pd/i2pd.cmd i2p-java/i2p-java.cmd
git check-attr text eol -- install.cmd
```

Do not run `install`, `configure`, `start`, `stop`, `restart`, or
`--install-deps` on a real installation just to test documentation or a
parser change. Use `--help`, `status`, and `detect` for read-only
inspection.

## Common problems

- **PowerShell argument forwarding.** Functions read `$args` from their
  own scope. Call `Main @args`; a bare `Main` drops script arguments.
- **Non-interactive detection.** Bash checks `-t 0`; PowerShell uses
  .NET `UserInteractive`. Redirected stdin is not equivalent on both
  platforms.
- **Case sensitivity.** Bash matches options case-sensitively;
  PowerShell's `switch -Regex` is case-insensitive by default.
- **Atomic config writes.** `WriteAllLines` alone truncates in place.
  Keep the temporary file and atomic replace.
- **Relative paths.** `-profile data` is relative to the caller's
  working directory unless made absolute.
- **`winget` chains.** Capture each command's exit code; returning only
  the last one can hide a failed Java installation.
- **Vendored I2P (Java).** The official installer is interactive and
  unverified; do not turn it into an unattended path without adding
  integrity verification.
- **Line endings.** A CRLF `.properties` value can carry `\r` into a
  message. Keep the LF attributes and the loader's defensive strip.

## References

- `install.bash`, `install.ps1` - installer and manager.
- `install.cmd`, `build/build.cmd`, `i2pd/i2pd.cmd`,
  `i2p-java/i2p-java.cmd` - Windows shims.
- `lib/router.bash`, `lib/router.ps1` - shared lifecycle and config.
- `lib/i18n.bash`, `lib/i18n.ps1` - message loading.
- `.gitattributes` - CRLF/LF rules.
- `README.md` - command reference and platform notes.
- Related skills: `i2p-router-integration`, `localization-maintenance`,
  `browser-build-validation`.
