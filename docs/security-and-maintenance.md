# Security, maintenance, and validation

## Trust boundaries

I2Pd Browser builds a portable Firefox ESR bundle and manages a local I2P
router. It is not a separate browser engine or a substitute for upstream security
maintenance. The browser proxy and local administrative services must stay on
loopback. Router transport traffic, reseeding, and UPnP are separate from those
local listeners. Access through an I2P outproxy is distinct from a direct browser
connection.

The locked manual proxy, empty bypass list, disabled direct failover, DoH,
connectivity probes, and telemetry are mandatory controls. WebRTC is disabled
with a locked preference because a preserved profile may override a default.
Other `defaultPref` values remain user-overridable. A syntactically valid policy
file does not prove that the running Firefox applied every policy.

## Download verification

Firefox and vendored i2pd are checked against their upstream SHA-512 manifests.
Those checks detect corruption and mismatched artifacts; they do not provide an
independent signature trust root. For a fixed NoScript artifact, supply
`NOSCRIPT_XPI_URL` using the official AMO HTTPS `/firefox/downloads/file/` URL and
`NOSCRIPT_SHA512` containing its trusted 128-character SHA-512 digest. Custom
URLs outside that official artifact path are rejected. Obtain the digest through
a trusted release process; the check does not establish a PGP signing identity.
The default still follows AMO latest. NoScript must have a valid ZIP and the expected
extension identity and compatibility metadata. These structural checks are not
signature authentication.

The managed I2P Java installer requires `I2P_INSTALLER_SHA512`: a 128-character
hexadecimal SHA-512 digest for the exact installer being downloaded. Obtain it
through an independently trusted channel before invoking the installer. Do not
copy a hash from an unverified download merely to satisfy the check. The
[official I2P download page](https://i2p.net/en/downloads/) links installer
signatures and its PGP verification instructions; authenticate the signing key
fingerprint independently before relying on those signatures. Automatic PGP
verification is not implemented. Never interpret the ZIP `PK` prefix as proof of
authenticity.

Java's console installer is interactive. `--non-interactive` must fail before
trying to run it. Install Java I2P manually first when unattended operation is
required. Existing managed installations can be reused without rerunning the
installer. No new download origin is required by these controls.

Windows configuration does not automatically exclude executables or directories
from Defender. Investigate detections using Microsoft's submission and review
process. Any administrator-managed exclusion is an external, explicit decision;
exclude the smallest possible scope and remove it when no longer needed.

## Safe configuration and process ownership

Validate environment overrides before writing any effective router file. Then
validate effective configuration before starting a router: a safe environment
does not repair an unsafe previously saved file. Reject unsafe or ambiguous
listeners rather than silently replacing user configuration. Java configuration
validation intentionally accepts a narrow Properties subset: canonical unique
ASCII keys followed by `=`, without whitespace aliases, escaped keys, or continued
lines. Unsupported syntax requires deliberate review; the manager does not
silently normalize it. Java endpoint
changes span several files and must either complete together or restore the
previous values when an operation fails.

A saved PID alone does not establish ownership: operating systems reuse PIDs.
Stopping a router requires matching the saved process identity to this
installation. Linux screen sessions must also be unique to the installation.
Old or incomplete ownership records must be treated conservatively; use the
router's own tools to stop an instance that cannot be authenticated. Never
terminate a process solely because its executable name resembles a router.

Prepare dependencies and the browser before stopping a previously managed
backend. A failed switch must report whether the previous selection and running
state were restored. Do not stop an unmanaged router to resolve a port conflict.
The installer holds `.browser-switch.lock` while changing selection. It requests
`I2PD_BROWSER_KEEP_BACKUP=1` during preflight so `.browser-old` remains available
until commit. Only the installer's paired internal flags
`I2PD_BROWSER_CONFIGURE_BUILD=1` and `I2PD_BROWSER_KEEP_BACKUP=1` allow a builder
to run while that switch lock exists. Standalone builds and switches reject
each other after acquiring their own locks. On failure the new bundle is preserved in `.browser-switch-failed`
before restoring the old one. Existing recovery directories must be investigated
before another switch. These paths contain user data and must not be committed.

Configuration preparation and publication are not a distributed transaction and
cannot guarantee recovery from every power failure; preserve recovery evidence
and report incomplete rollback explicitly.

## Browser maintenance procedure

Automatic Firefox updates remain disabled. The operator is responsible for
refreshing Firefox, NoScript, routers, and their security configuration.

1. Review upstream security advisories at least monthly and promptly after a
   relevant advisory. An age warning is a reminder, not proof that a version is
   secure or vulnerable.
2. Close Firefox before rebuilding. Do not delete a profile lock merely to make
   a build proceed. Investigate a stale lock and confirm that no instance uses
   the profile. Do not launch Firefox during a rebuild.
3. Build only one bundle at a time. Inspect an interrupted build and its backup
   before removing a stale build lock. Do not delete user data to recover space.
4. Rebuild explicitly using the documented platform command. Record the bundle
   manifest, versions, hashes, locale, architecture, and selected proxy endpoint.
   Floating `latest` selectors do not provide reproducible builds.
5. Inspect the resulting policy and metadata. Perform a runtime smoke test in a
   disposable installation before replacing an important working installation.
6. Keep a separate profile backup appropriate to the user's recovery needs.
   Staging and rename rollback are not a backup policy.

The maintenance mechanism must use local metadata for age warnings. It must not
introduce a background version query, telemetry, or an updater connection.
Version selectors and pinned artifacts still require regular review; pinning an
obsolete artifact indefinitely is unsafe.

## Compatibility matrix and support limits

| Target | Source support | Evidence required before claiming runtime support |
| --- | --- | --- |
| Linux x86_64 and aarch64 | Firefox builders and router backends | Current Mozilla artifact, host libraries, local policies, router readiness |
| Linux i686 | Legacy Mozilla ESR availability only | Upstream security support must be checked before use; no current support guarantee |
| Windows x86_64 and i386 | Firefox and vendored i2pd mappings | Windows execution, argument forwarding, process identity, policies |
| Windows aarch64 | Firefox mapping, Java option | No vendored i2pd artifact currently supplied; verify native dependencies |
| PowerShell 5.1 and 7 | Compatibility intended | Parser checks plus Windows lifecycle and quoting tests on both |
| Non-Debian Linux with vendored i2pd | Debian binary extraction | ABI and shared-library compatibility must be established on the target |

Mozilla states that 32-bit Linux will not receive updates beyond ESR 140 in its
[32-bit Linux support notice](https://support.mozilla.org/en-US/kb/firefox-has-ended-support-32-bit-linux).
A redirector product that stops resolving must fail clearly; choosing an older
branch does not establish ongoing security support.

Maintain a policy matrix for each selected ESR branch. Check the upstream
[policy reference](https://firefox-admin-docs.mozilla.org/reference/policies/)
and Firefox's `about:policies` errors. For example, `AIControls` and
`LocalNetworkAccess` are version-dependent; their presence in JSON does not
establish enforcement on an older branch. Mandatory proxy, update and telemetry
controls must be verified separately from supplemental feature restrictions.

## Static and behavioral validation

Static validation includes Bash syntax, ShellCheck, shfmt, JSON parsing,
PowerShell parsing when available, workflow lint, and agent-knowledge validation.
It cannot establish browser startup, extension activation, network isolation,
correct locks across real processes, Windows process termination, or recovery
under filesystem and power failures.

The behavioral suites use temporary state and should run only when authorized.
The manual owner-only test workflow runs the Bash/Perl suites on Ubuntu and the
native PowerShell suites on Windows under 5.1 and 7. Both original and re-run
actors must match the repository owner; unauthorized jobs are skipped before
checkout. This CI uses fixtures, not real routers or browser builds. See
[contributing](../CONTRIBUTING.md) for manual invocation and matrix coverage:


```sh
bash tests/test-i18n.bash
bash tests/test-proxy-policy.bash
bash tests/test-router-safety.bash
bash tests/test-router-java-config.bash
bash tests/test-build-safety.bash
bash tests/test-noscript.bash  # Python 3 supplies offline ZIP fixtures
prove tests/agent_knowledge_validator/test_validator.pl
```

Run `tests/test-i18n.ps1`, `tests/test-proxy-policy.ps1`,
`tests/test-router-safety.ps1`, and `tests/test-router-ownership.ps1` with
PowerShell when available and execution is authorized. Tests must invoke
production generation/validation helpers rather than reproduce their algorithm.
Use fixtures and fault injection for malformed policies, invalid endpoints,
profile locks, stale process records, and publication failures. Never use the
user's live router or only browser profile as a test fixture.

## Accessibility and resource evaluation

The hardening profile disables accessibility integration. This can prevent
assistive technologies from working and must not be presented as accessible by
default. Before offering an accessible mode, test screen readers on Linux and
Windows and review the security implications of changing the restriction. Keep
the proxy and network controls unchanged during that evaluation.

Both router seeds use a 2048 KB/s sustained bandwidth profile and enable UPnP.
These are configuration choices, not measured optimal values for every host.
Before adding resource profiles, measure idle and active CPU, resident memory,
bandwidth, bootstrap time, and proxy readiness on representative hardware. Record
router/browser versions, sample duration, workloads, and network conditions.
Do not claim a performance improvement without comparable measurements.
