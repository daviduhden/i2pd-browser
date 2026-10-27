---
name: firefox-esr-bundling
description: Build or modify the preconfigured Firefox ESR bundle. Use when changing build/build.bash or build/build.ps1, Firefox preferences, policies, autoconfig, the portable profile, NoScript handling, or bundle layout.
---

# Firefox ESR bundling

## When to use

Use this skill when a change affects how Firefox ESR is resolved,
downloaded, verified, extracted, configured, packaged, or launched. It
does not cover router selection or installer lifecycle; use
`i2p-router-integration` and `cross-platform-installers` for those.

## Project facts

- `build/build.bash` is the Linux builder. It resolves
  `ESR_PRODUCT` (default `firefox-esr-next-latest`) through
  `https://download.mozilla.org/`, follows the redirect, and accepts a
  final name matching `firefox-<version>esr.tar.{xz,bz2}`.
- `build/build.ps1` is the Windows builder. It resolves the same
  redirector product, downloads Mozilla's installer, and runs it with
  `/S /D=<staging dir>`.
- Both builders verify SHA-512 from Mozilla's `SHA512SUMS` before
  publishing a bundle. The Bash builder requires the exact
  `<platform>/<locale>/<file>` entry; the Windows builder derives the
  same relative path from the final URL.
- `ESR_PRODUCT` is restricted to `[A-Za-z0-9._-]+` before being placed
  in a URL. The final URL must contain the requested locale, so a
  Mozilla locale fallback fails the build instead of producing a
  mislabeled bundle.
- Builds are staged in `.browser-build/`. The previous `browser/` is
  moved to `.browser-old/` only at publish time. On success the new
  tree replaces it; on failure the old tree remains. `browser/data/`
  is copied into the staging tree first, then `user.js` is regenerated.
- The tracked sources are `build/preferences/**` and
  `build/profile/**`. The builder copies them into the generated
  `browser/` tree; never edit generated `browser/` files as the source.
- `build/preferences/defaults/pref/autoconfig.js` enables
  `i2pd-browser.cfg`. That file contains the `lockPref`,
  `defaultPref`, and `pref` hardening rules. The enterprise policy file
  is `build/preferences/distribution/policies.json`.
- NoScript is downloaded from AMO's `latest.xpi` URL, written to
  `browser/browser/extensions/{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi`,
  and checked for the ZIP magic bytes. Its version and signature are
  not verified.
- The locale marker is `browser/.i2pd-browser-locale`. It is created in
  the staging tree and published only after the bundle passes layout
  and proxy-policy validation. `browser/data/user.js` sets
  `intl.locale.requested`.

## Procedure

1. Read `build/build.bash`, `build/build.ps1`, the affected files under
   `build/preferences/`, and `build/profile/`. Check `git diff` for
   pre-existing work.
2. Change the tracked source, not `browser/`. If behavior is shared,
   implement it in both builders and keep their output layouts equal.
3. Keep the downloaded Firefox identity checks intact: the redirector
   URL, final filename/version parse, locale check, SHA-512 download,
   exact checksum entry, and refusal to publish on mismatch.
4. Keep the staging/publish flow. Do not reintroduce deletion of the
   live `browser/` before the new tree is verified.
5. If you touch the profile seed, remember that `browser/data/` is user
   data and must be preserved. The build overwrites only generated
   `user.js` and the locale marker.
6. If you add a required bundle file, add it to `validate_bundle`
   (Bash) and `Test-BundleLayout` (PowerShell), and verify both
   builders still copy it.
7. Do not add new download hosts, extension stores, update servers, or
   telemetry. The only existing download origins are Mozilla
   (`download.mozilla.org`, `ftp.mozilla.org`) and AMO for NoScript.
8. Update `README.md` when user-visible behavior changes, for example
   profile preservation or a new validation requirement.

## Validation

Run static and unit checks first:

```sh
bash -n build/build.bash
shellcheck build/build.bash
shfmt -d build/build.bash
jq -e . build/preferences/distribution/policies.json
bash tests/test-i18n.bash
git diff --check
```

For the PowerShell builder, run the parser and tests on a host with
`pwsh` (this repository's Linux CI environment may not provide it):

```powershell
$t = $null; $e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path 'build/build.ps1'), [ref]$t, [ref]$e)
if ($e) { $e | ForEach-Object Message; exit 1 }
pwsh -NoProfile -File tests/test-i18n.ps1
```

A real build is a separate step and needs network access. Run it from
the repository root so the paths below are unambiguous:

```sh
(cd build && ./build.bash --language=en-US)
```

After a real build, confirm all of the following rather than assuming
they worked:

- `browser/firefox` exists and `browser/data/user.js` contains the
  requested locale.
- `browser/.i2pd-browser-locale` contains that locale.
- `browser/distribution/policies.json` parses and keeps the locked
  manual proxy at `127.0.0.1:4444`.
- `browser/defaults/pref/autoconfig.js`, `browser/i2pd-browser.cfg`,
  and `browser/browser/override.ini` exist.
- `browser/browser/extensions/{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi`
  starts with `PK`.
- A pre-existing profile's bookmarks or history are still present when
  testing profile preservation.

Never run a real build on a user's only browser tree just to test a
change. Use a disposable clone or a backed-up profile.

## Common problems

- **No version pin.** Both builders follow the current ESR release.
  Do not claim reproducible builds.
- **Checksum, not signature.** SHA-512 detects corruption or a mirror
  mismatch; it does not authenticate Mozilla. NoScript has only a
  structural ZIP check.
- **PowerShell argument handling.** `Main` must be called as
  `Main @args`; calling it with no arguments silently drops
  `--language` and `--help`.
- **Generated tree confusion.** `browser/` is ignored. Editing it will
  be lost on the next build.
- **Profile loss.** If you remove the data-copy block, a rebuild deletes
  bookmarks, history, cookies, logins, and extensions. Profile
  preservation intentionally keeps them.
- **Preserved overrides.** A preserved profile can retain user values
  for `defaultPref` settings. Locked proxy, telemetry, update, and
  extension policies still apply, but a rebuild does not reset every
  privacy default. Do not claim that it does.
- **Locale fallback.** Reject a final URL that does not contain the
  requested locale; otherwise the marker and `user.js` can disagree
  with the payload.
- **Policy drift.** A valid JSON file can still have a missing or
  changed proxy endpoint. The publish validation exists because the
  proxy endpoint lives only in `policies.json`.
- **Plugin/extension assumptions.** NoScript is sideloaded at
  application level, not enforced by an `ExtensionSettings` policy.

## References

- `build/build.bash` - Linux pipeline, staging, checksum, validation.
- `build/build.ps1` - Windows pipeline, staging, checksum, validation.
- `build/preferences/i2pd-browser.cfg` - Firefox preferences.
- `build/preferences/distribution/policies.json` - enterprise policies.
- `build/preferences/defaults/pref/autoconfig.js` - AutoConfig switch.
- `build/profile/certificates/purplei2p_ca.pem` - profile certificate.
- `build/scripts/start-i2pd-browser.bash` - Linux launcher.
- `build/scripts/start-i2pd-browser.ps1` - Windows launcher.
- `README.md` - supported targets and user-facing build behavior.
- Related skills: `privacy-and-leak-audit`, `browser-build-validation`,
  `localization-maintenance`.

## Maintenance & Continuous Learning

After using this skill to modify the repository, review this skill and the
applicable `AGENTS.md` and agent instructions once at task end. Update this skill
when its procedures, tools, configuration, project facts, assumptions, examples,
or validation steps have changed or when implementation work produced reusable
knowledge. Correct instructions that proved wrong, remove obsolete details, and
keep references and repository-relative paths valid. Avoid notes tied only to one
execution. If another agent or skill owns the affected procedure, update or link
that source rather than duplicating it. Run `python3
scripts/validate-agent-maintenance.py` after synchronizing. Its structural checks
do not judge semantic relevance; review that manually. Report the synchronization
result and checks actually run in the final response. If synchronization cannot
be completed, state why and mark the task incomplete.
