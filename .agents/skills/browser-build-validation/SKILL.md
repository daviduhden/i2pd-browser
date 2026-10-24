---
name: browser-build-validation
description: Validate Firefox ESR bundle changes and report honest evidence. Use after editing the build, preferences, policies, launchers, installers, or localization, and when deciding whether a build was actually tested.
---

# Browser build validation

## When to use

Use this skill after a change to the build pipeline, Firefox
configuration, profile seed, launchers, installers, or localization.
It separates static analysis, syntax checks, unit tests, a real bundle
build, and a runtime smoke test. Do not collapse those categories into
"tested".

## Validation levels

### 1. Static and syntax

No network, no generated bundle:

```sh
git diff --check
git status
bash -n install.bash build/build.bash build/scripts/*.bash \
  lib/*.bash lib/backends/*.bash tests/*.bash i2pd/*.bash \
  i2p-java/*.bash
shellcheck install.bash build/build.bash build/scripts/*.bash \
  lib/*.bash lib/backends/*.bash tests/*.bash i2pd/*.bash \
  i2p-java/*.bash
shfmt -d install.bash build/build.bash build/scripts/*.bash \
  lib/*.bash lib/backends/*.bash tests/*.bash i2pd/*.bash \
  i2p-java/*.bash
jq -e . build/preferences/distribution/policies.json
```

On a host with PowerShell, parse every `.ps1` and run the PowerShell
test:

```powershell
$files = Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object FullName
foreach ($file in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file, [ref]$tokens, [ref]$errors)
    if ($errors) { $errors | ForEach-Object Message; exit 1 }
}
pwsh -NoProfile -File tests/test-i18n.ps1
```

### 2. Unit tests

```sh
bash tests/test-i18n.bash
pwsh -NoProfile -File tests/test-i18n.ps1   # if available
```

These cover catalog key parity, locale normalization, selection
precedence, fallback, config preservation, and the presence of
`intl.locale.requested` in both builders. They do not test Firefox,
downloads, policies, router lifecycle, or launchers.

### 3. Real build

Only when the task needs a bundle and network access is allowed. The
builders download Firefox ESR and NoScript, extract or install Firefox,
stage in `.browser-build/`, and publish to `browser/`. They preserve the
existing `browser/data/` profile. Use a disposable clone or a backed-up
profile; never test on a user's only installation.

```sh
cd build
./build.bash --language=en-US
cd ..
```

Windows, from the repository root:

```bat
build\build.cmd --language=en-US
```

`build/build.ps1` accepts `--language` and `--help`; pass arguments
through `Main @args`. If `pwsh` is unavailable, do not claim the
PowerShell build was exercised.

### 4. Bundle inspection

After a successful build:

```sh
test -x browser/firefox
test -f browser/data/user.js
grep -q 'intl.locale.requested' browser/data/user.js
test "$(cat browser/.i2pd-browser-locale)" = en-US
jq -e '
  .policies.Proxy.Mode == "manual" and
  .policies.Proxy.Locked == true and
  .policies.Proxy.HTTPProxy == "127.0.0.1:4444" and
  .policies.Proxy.SSLProxy == "127.0.0.1:4444" and
  .policies.Proxy.UseProxyForDNS == true and
  .policies.Proxy.Passthrough == ""
' browser/distribution/policies.json
test -f browser/defaults/pref/autoconfig.js
test -f browser/i2pd-browser.cfg
test -f browser/browser/override.ini
test -f browser/i18n.bash
test -f browser/i18n.ps1
test -f browser/locales/en-US.properties
head -c 2 browser/browser/extensions/\
{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi | grep -q PK
```

On Windows, use `browser\firefox.exe` and the equivalent `Test-Path`
checks. If the build claims locale verification, compare the final URL
locale and the marker; do not trust the marker alone.

### 5. Runtime smoke test

This requires a running or startable router and a display, and it can
contact the I2P network. Do not run it as a substitute for static
checks, and do not browse clearnet to prove a leak.

```sh
./install.bash status
./install.bash detect
./browser/start-i2pd-browser.bash --help
```

`--help` asks the bundled Firefox for help and prints the launcher
usage; it is a low-impact check that the executable and i18n files are
present. Starting Firefox normally or starting a router is a separate
action; record it only if actually performed. There is no automated
post-build smoke test in this repository.

## Evidence rules

- State the exact commands, host platform, and whether `pwsh` was
  available.
- Do not say "build passes" if only `bash -n`, `shellcheck`, or
  `tests/test-i18n.bash` ran.
- Do not say "privacy verified" without inspecting the generated
  policies and prefs, and without a runtime test if traffic behavior is
  claimed.
- Do not say "PowerShell tested" without a PowerShell parser or run.
- Report failures and unrun checks explicitly.

## Common problems

- **No CI or Makefile.** Validation is manual. The only tracked tests
  are `tests/test-i18n.bash` and `tests/test-i18n.ps1`.
- **Build is network-dependent and destructive to the generated
  bundle.** Staging protects the published tree, and the profile is
  preserved, but a failed build can leave `.browser-build/` or
  `.browser-old/`.
- **Stale source edits.** A bundle is not rebuilt automatically when
  `build/preferences/` changes; the installer checks the binary and
  locale marker and now warns when build inputs are newer. Rebuild
  explicitly after changing build inputs.
- **PowerShell argument trap.** A bare `Main` call drops `$args`; use
  `Main @args`.
- **Marker timing.** The locale marker is written in staging and
  published only after layout and proxy validation. Do not move it
  earlier.
- **NoScript structural check.** ZIP magic proves the download is not
  an HTML error page; it does not prove authenticity or version.
- **Checksum scope.** SHA-512 covers the Mozilla archive/installer.
  It does not authenticate the checksum origin or cover NoScript.
- **No version pin.** Two builds at different times can use different
  Firefox or NoScript versions.

## References

- `build/build.bash`, `build/build.ps1` - build pipelines.
- `build/preferences/**` - prefs, policies, autoconfig.
- `build/scripts/**` - launchers.
- `tests/test-i18n.bash`, `tests/test-i18n.ps1` - only tracked tests.
- `README.md` - user-facing build and troubleshooting notes.
- Related skills: `firefox-esr-bundling`, `privacy-and-leak-audit`,
  `cross-platform-installers`.
