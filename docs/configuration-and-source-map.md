# Configuration and source map

This guide maps maintained configuration and source files to the programs that
consume them. It complements inline comments where a format cannot safely hold
comments, especially JSON. The repository's tracked files are the inputs; output
under `browser/`, managed downloads under `vendor/`, and runtime state are not
source files and are excluded here.

## Runtime architecture

```text
install.bash / install.ps1
  ├─ lib/router.bash / lib/router.ps1
  │    ├─ lib/backends/i2pd.* ── i2pd/i2pd.conf + i2pd/tunnels.conf
  │    └─ lib/backends/i2p-java.* ── i2p-java/config/* -> i2p-java/data/*
  └─ build/build.bash / build/build.ps1
       ├─ build/preferences/* -> browser/distribution, browser/defaults, browser root
       ├─ build/profile/* -> browser/profile seed
       └─ build/scripts/* -> browser launchers

browser/start-i2pd-browser.* -> browser/firefox[.exe] -profile browser/data
Firefox enterprise policy (generated endpoint; default 127.0.0.1:4444) and AutoConfig -> selected local HTTP proxy
```

The installer is also the router manager. The shared router libraries load one
backend and protect the distinction between a router started by this project
and a system-managed router. The browser's proxy address is normalized across
backends; the router console ports differ. On Linux the backend lifecycle uses
`screen`; Windows uses hidden processes and PID files. The i2p-java configuration
is copied from `config/` to `data/` only when each destination file is missing,
so later edits to the seed do not overwrite existing effective configuration.
i2pd instead keeps configuration and runtime state in `i2pd/` and is launched
with that directory as its data directory.

The installer creates the ignored root file `i2pd-browser.conf` with managed
keys `I2P_ROUTER`, `I2P_ROUTER_SOURCE`, and `I2PD_BROWSER_LANGUAGE`. It preserves
unrecognized lines when rewriting the file. Relevant environment and discovery
inputs found in the scripts are:

| Variable | Consumer and consequence |
| --- | --- |
| `I2PD_BROWSER_CONF` | Selects an alternate selection/config path; tests use it to isolate state. |
| `I2PD_BROWSER_LANGUAGE` | Preferred locale input; legacy lowercase `language` is also accepted by the localization loader/build compatibility path. |
| `I2P_ROUTER_DEFAULT`, `I2P_ROUTER_SOURCE_DEFAULT` | Override shared-library fallback choices when no stored or explicit selection exists. |
| `ROUTER_HTTP_PROXY_HOST/PORT`, `ROUTER_SOCKS_PROXY_HOST/PORT` | Override the proxy endpoints. The builder writes the HTTP endpoint to generated HTTP/SSL policy fields; i2pd receives bind overrides on its command line; Java I2P applies them to its effective `data/` listener, address-book proxy, and update proxy settings. The bind host must remain `127.0.0.1`, and ports must be 1-65535. |
| `I2PD_BROWSER_VENDOR_DIR`, `I2PD_BROWSER_BACKENDS_DIR` | Redirect managed router downloads or backend implementation lookup; internal deployment/test hooks. |
| `PROXY_TIMEOUT` | Sets the installer wait period for a local HTTP proxy TCP listener (default 90 seconds in installers). This check does not issue a web request. |
| `ESR_PRODUCT` | Selects Mozilla's redirector product for Firefox; defaults to `firefox-esr-next-latest` and is syntax-filtered before URL use. `firefox-esr-latest` is documented for 32-bit Linux. |
| `I2P_HOME`, `I2P_BASE`, `JAVA_HOME` | Help locate the Java router/JRE. Bash checks `I2P_HOME` and `I2P_BASE`; PowerShell checks `I2P_HOME`; both use Java from `JAVA_HOME` or `PATH`. |
| `NO_COLOR` | The Bash builder suppresses colored log output when set to `1`; it does not alter build behavior. |

Overrides are read from the environment each time the installer/build or
router is started. A custom endpoint is not persisted as an installer selection:
provide the same overrides on later router start/restart commands. The Java
backend patches only its effective `data/` files and only while the associated
override is supplied; tracked `config/` templates and existing files are left
untouched when the environment has no override.

## Browser configuration

Firefox configuration is layered. `build/preferences/defaults/pref/autoconfig.js`
selects `i2pd-browser.cfg`; the latter sets preferences using Firefox's
AutoConfig functions. `build/preferences/distribution/policies.json` supplies
enterprise policy values. The builder copies these inputs into the generated
bundle and validates selected proxy invariants before publishing it.

| File | Consumer and meaning | Modification cautions |
| --- | --- | --- |
| `build/preferences/browser/override.ini` | Firefox runtime reads `[XRE]` setting `EnableProfileMigrator=0`; profile migration UI is disabled for this portable-profile bundle. | Preserve the INI section and key spelling. |
| `build/preferences/defaults/pref/autoconfig.js` | Firefox preference startup loads the named AutoConfig file and uses unobscured text (`general.config.obscure_value=0`). | Keep the filename in sync with the copied `i2pd-browser.cfg`. |
| `build/preferences/i2pd-browser.cfg` | AutoConfig sets browser preferences. `lockPref` locks a value, `defaultPref` supplies a user-overridable default, and `pref` sets an ordinary preference. | A `defaultPref` is not an enforced restriction. Preserve proxy mode, no direct fallback, and the policy endpoint together. |
| `build/preferences/distribution/policies.json` | Firefox enterprise policy is strict JSON. It is generated into `browser/distribution/policies.json`; comments and explanatory pseudo-properties are invalid for this consumer. | Validate with `jq`; do not weaken the locked manual loopback proxy or set a passthrough exception. |
| `build/profile/certificates/purplei2p_ca.pem` | PEM certificate copied into the Firefox profile seed for the PurpleI2P certificate authority. | This is cryptographic trust material, not ordinary text. Do not edit or regenerate it as documentation. |

### Enterprise policy reference

The current policy file contains the following settings. Firefox version support
can differ across the ESR branch; a key being valid JSON does not prove that a
given ESR build recognizes it. Consult Mozilla's [Firefox administrator policy
reference](https://firefox-admin-docs.mozilla.org/reference/policies/) and the
specific linked policy page when changing one.

| Policy | Current value and purpose in this bundle |
| --- | --- |
| `DisableAppUpdate`, `DisableSystemAddonUpdate` | Disable Firefox application and system add-on updates. Updates must therefore be managed by rebuilding/replacing the bundle. |
| `DisableTelemetry`, `DisableFirefoxStudies`, `DisableRemoteImprovements` | Disable telemetry uploads, studies, and remote improvement changes. |
| `DisableFirefoxAccounts` | Disable Firefox Accounts/Sync integration. |
| `DisableFeedbackCommands` | Remove site feedback/reporting menu actions. |
| `BrowserDataBackup.AllowBackup`, `AllowRestore` | Disable browser profile backup and restore features. |
| `AIControls.Default` | Block and lock the default AI controls policy value. Actual support depends on Firefox version. |
| `DefaultSerialGuardSetting` | Set the Web Serial API's default guard to `2` (blocked in current policy documentation); this policy is version-dependent and may be ignored by an older ESR. |
| `IPProtectionAvailable` | Hide/disable availability of the built-in IP Protection feature where supported. |
| `LocalNetworkAccess` | Enable, lock, and prompt for local network access checks while blocking trackers from such access. This is a browser control on web page requests; it does not replace the router listener bind settings. |
| `VisualSearchEnabled`, `XSLTEnabled` | Disable visual search and XSLT features where the running Firefox supports these policies. |
| `HttpsOnlyMode` | `disallowed` means HTTPS-Only Mode is off and cannot be enabled by the user. This preserves HTTP `.i2p` destinations. |
| `DNSOverHTTPS.Enabled`, `Locked` | Disable DoH and lock that setting so DNS behavior is not changed to a browser DoH endpoint. |
| `CaptivePortal`, `NetworkPrediction` | Disable captive-portal detection and network prediction. |
| `DontCheckDefaultBrowser` | Skip the default-browser check at startup. |
| `OverrideFirstRunPage`, `OverridePostUpdatePage` | Set the first-run page to the local I2P homepage and suppress the post-update page. |
| `Proxy` | Lock manual mode to the selected router HTTP endpoint for both HTTP and SSL (default `127.0.0.1:4444`), send DNS through the proxy where the policy applies, and set an empty bypass list. Builders rewrite the policy template using validated loopback overrides. The router must be running for browsing. |
| `SearchEngines` | Set YaCy at `http://legwork.i2p/` as the default, prevent web-installed search engines, and remove named built-in engines. This is an I2P URL, not a guarantee that every search path stays within the I2P network. |
| `SearchSuggestEnabled` | Disable search suggestions. |
| `FirefoxHome` | Keep the search field, while disabling weather, top sites, highlights, Pocket, snippets, and sponsored top sites. |
| `SupportMenu` | Add the configured ILITA IRC support destination to the browser menu. |
| `Permissions` | Block new camera, microphone, and location permission requests through enterprise policy. |

Mozilla documents the proxy semantics at [Proxy](https://firefox-admin-docs.mozilla.org/reference/policies/proxy/),
including that `Passthrough` names destinations excluded from proxying. The
empty value here is intentional. `LocalNetworkAccess` behavior is described in
[its policy reference](https://firefox-admin-docs.mozilla.org/reference/policies/localnetworkaccess/).
The Firefox preferences file also contains controls beyond enterprise policy;
its section headings group settings for updates, first-run UI, search, HTTPS-only
mode, speculative networking, device APIs, proxy/DNS, TLS, telemetry, WebGL,
containers, shutdown sanitization, and AI features. Check each preference's
`lockPref`/`defaultPref`/`pref` form before describing it as enforced.

Additional configuration files are generated during the build: `browser/data/user.js`
contains the selected `intl.locale.requested` value; `browser/.i2pd-browser-locale`
records the bundle locale; and `browser/i2pd-browser.cfg` plus
`browser/distribution/policies.json` are copied from their tracked build inputs.
The profile remains user state and is preserved when rebuilding.

## Router configuration

### i2pd

`i2pd/i2pd.conf` uses i2pd's INI-like configuration syntax; its parser accepts
`#` comments (not `;`). See the [official i2pd configuration guide](https://docs.i2pd.website/en/latest/user-guide/configuration/).
The backend launches i2pd with `--datadir=.` from `i2pd/`, so relative state
paths remain inside that directory. Important current values:

| Section/key | Purpose and relationship |
| --- | --- |
| `log`, `logfile`, `loglevel` | Write error-level logs to `i2pd.log` in the data directory. Runtime logs are ignored by Git. |
| `ipv4`, `ipv6` | Enable router transports over these IP families. They do not change the local application listener addresses below. |
| `bandwidth=P` | Select i2pd's documented P bandwidth profile (2048 KB/s); the Java router config uses corresponding 2048 KB/s values. |
| `[precomputation] elgamal=false` | Disable this optional precomputation setting. Confirm upstream support and tradeoffs before changing it. |
| `[upnp] enabled=true` | Allows UPnP mapping requests to the local gateway. This is separate from the app-facing loopback listeners and has network exposure implications. |
| `[reseed] verify=true` | Keep reseed verification enabled during initial router network bootstrapping. |
| `[http]` | Console enabled at loopback `127.0.0.1:7070`; the console port is backend-specific. |
| `[httpproxy]` | HTTP proxy enabled at loopback `127.0.0.1:4444` by default; an explicit validated override replaces the endpoint at runtime/config preparation and the generated Firefox policy. The `outproxy` is an I2P destination for external destinations; it does not mean Firefox connects directly to the clearnet. |
| `[socksproxy]` | Optional SOCKS endpoint at loopback `127.0.0.1:4447`; Firefox currently uses the HTTP proxy instead. |
| `[sam]` | SAM client interface at loopback `127.0.0.1:7656`; Firefox does not use it. |
| `[addressbook]` | I2P address-book hosts and subscription URLs; these are router network data sources. |

`i2pd/tunnels.conf` currently contains only disabled, commented client tunnel
examples. `i2pd/tunnels.d/README` describes the optional directory for separate
tunnel configurations. `i2pd/addressbook/addresses.csv` is imported address
book data rather than explanatory configuration; do not add comments to its CSV
records.

### I2P (Java)

The Java router reads the configuration directory supplied by the backend's
`-Di2p.dir.config` argument. The project points this to `i2p-java/data/`, not a
user's global `~/.i2p`; the installer seeds missing files from `i2p-java/config/`
without replacing existing effective files.

| File | Settings and relationships |
| --- | --- |
| `i2p-java/config/router.config` | Sets inbound/outbound rates and burst capacities, enables UPnP, and keeps router update checks notify-only through the local HTTP proxy at `127.0.0.1:4444`. The sustained inbound/outbound rate values are 2048 KB/s; burst byte values are separately set to 22520 KB. |
| `i2p-java/config/clients.config` | Starts the router console on loopback IPv4/IPv6 at port 7657 and starts the application tunnel controller with `i2ptunnel.config`; the systray/URL browser client is omitted. `startOnLoad` enables these listed clients during router startup, and `delay=-1` starts tunnels before the console. |
| `i2p-java/config/i2ptunnel.config` | `tunnel.N.name`, `description`, and `type` identify each HTTP/SOCKS client tunnel; `interface`/`listenPort` set its local listener; `sharedClient` selects shared-client behavior; `i2cpHost`/`i2cpPort` connect it to the local router. `proxyList` and `SSLOutproxies` select the HTTP outproxy. `startOnLoad` controls automatic tunnel startup. `option.inbound/outbound.nickname` label tunnel directions. Inbound/outbound length and variance specify tunnel hops; `leaseSetEncType` carries upstream numeric encryption-type identifiers; `connectDelay` is a streaming-protocol delay in milliseconds. Do not change these values without checking the [I2P I2PTunnel/I2CP documentation](https://geti2p.net/en/docs/protocol/i2cp) and [streaming option reference](https://geti2p.net/en/docs/api/streaming). |
| `i2p-java/config/addressbook/config.txt` | `should_publish=false` disables publishing this address book. `proxy_host`/`proxy_port` point address-book updates at the local HTTP proxy; `update_delay` controls the refresh interval. The log, last-modified, ETag, and subscription filenames track HTTP update state; the remaining paths identify local, router, and published host files under the isolated data tree. |
| `i2p-java/config/logger.config` | Sets timestamped router log formatting, file rotation, and log levels; log files live under the isolated data directory. |
| `i2p-java/README.md` | Documents the `config/` seed versus ignored `data/` runtime/effective state and the backend differences. |

The `.config` files use Java I2P's key/value property format. Their `#` comments
are already consumed as configuration comments. Names such as `tunnel.0.*`,
`clientApp.0.*`, and `i2np.bandwidth.*` are upstream keys; preserve their exact
spelling and indexes. Do not copy a changed seed over a user's existing `data/`
file implicitly.

## Localization, packaging, and repository metadata

| File group | Interpretation |
| --- | --- |
| `locales/*.properties` | UTF-8 data-only message catalogs. `lib/i18n.bash` and `lib/i18n.ps1` parse `key=value`, skip `#` lines, load English first and overlay the selected locale. Keep four catalogs key-for-key identical; values may contain escaped `\n` and `{n}` placeholders. Never source or evaluate them. |
| `build/profile/certificates/*.pem` (currently one PEM file) | Certificate bytes copied into the browser profile seed. These are security-sensitive trust inputs and must not be reformatted or annotated. |
| `i2pd/certificates/**/*.crt` | Router reseed/family certificate data consumed by i2pd. Excluded from comments because these are cryptographic records, not project-authored explanatory text. |
| `i2pd/addressbook/addresses.csv` | Currently an empty newline-only placeholder. Treat it as address-book data, not a commentable configuration file. |
| `.gitattributes` | Pins line endings by extension, notably CRLF for `.cmd` and LF for Bash, PowerShell, Markdown, JSON, INI-like files, properties, and certificates. |
| `.gitignore` | Excludes generated browser output, downloaded archives, router runtime state, user configuration, and managed router downloads. Do not commit these excluded files. |
| `build/scripts/start-i2pd-browser.desktop` | Linux desktop entry plus shell-executable self-modifying launcher. Its existing header explains relocation and registration; preserve desktop-entry field syntax and its executable shebang. |

The `.properties` catalogs already carry a data-only header in English and
language-name headers in translated catalogs. They are message data rather than
source comments; keep those catalog translations unchanged when documenting
implementation details. Script and configuration comments added in this change
use American English.

`i2pd-browser.conf` is a runtime file, not a tracked template, so its schema is
documented above and in the router libraries rather than by adding a sample file
that could be mistaken for active configuration.

## Source and launch flow

| Component | Responsibility and important dependencies |
| --- | --- |
| `install.bash`, `install.ps1` | Parse commands/options, select language/backend/source, prepare configuration, optionally build Firefox, and dispatch router lifecycle commands. The Bash and PowerShell paths should remain behaviorally aligned. |
| `install.cmd` | Windows shim. Prefers `pwsh.exe`, falls back to `powershell.exe`, passes `%*`, and returns the PowerShell exit code. |
| `lib/router.bash`, `lib/router.ps1` | Shared backend selection, config persistence, managed download/checksum helpers, proxy defaults, state and lifecycle abstraction. |
| `lib/backends/i2pd.bash`, `lib/backends/i2pd.ps1` | Discover/system-install i2pd or use `vendor/i2pd`, configure Defender exclusion best-effort on Windows, and start/stop the C++ router. |
| `lib/backends/i2p-java.bash`, `lib/backends/i2p-java.ps1` | Discover Java and a system I2P installation or use `vendor/i2p-java`; seed isolated config; invoke the Java router. The Java vendor installer path lacks checksum verification, unlike vendored i2pd. |
| `i2pd/i2pd.bash`, `i2pd/i2pd.ps1` | Thin backend-specific launchers that load the shared library, prepare config, then start the selected i2pd backend. |
| `i2p-java/i2p-java.bash`, `i2p-java/i2p-java.ps1` | Equivalent launchers for I2P (Java), which uses the isolated `data/` configuration. |
| `*.cmd` shims | Launch sibling PowerShell files with a per-invocation execution policy bypass. They are CRLF-sensitive and must preserve quoting, argument forwarding, and exit status. |
| `build/build.bash`, `build/build.ps1` | Resolve the Mozilla ESR download, validate platform/locale/checksum, stage and validate the bundle, copy tracked preferences/profile/scripts, and publish while preserving browser user data. |
| `build/build.cmd` | Windows shim for the PowerShell builder. |
| `build/scripts/start-i2pd-browser.bash`, `build/scripts/start-i2pd-browser.ps1` | Load bundled localization, parse launcher flags, use the bundled Firefox and portable `data` profile, and forward remaining browser arguments. Linux additionally handles desktop registration, environment setup, logging, and optional detach behavior. |
| `build/scripts/execdesktop.bash` | Reads the custom `X-I2PdBrowser-ExecShell` field from the desktop entry and executes the stored launcher with forwarded arguments. |
| `tests/test-i18n.bash`, `tests/test-i18n.ps1` | Exercise catalog parity, locale normalization/selection, configuration preservation, and builder locale preference wiring. The PowerShell test should be parsed/run only when `pwsh` is available. |
| `tests/test-proxy-policy.bash` | Verifies that a non-default loopback HTTP endpoint replaces both generated Firefox HTTP and SSL policy endpoints while preserving the locked proxy controls. |
| `scripts/validate-agent-maintenance.py` | Checks Git change coverage and structural synchronization of agent instructions/skills. It does not judge whether documentation changes are semantically sufficient. |

### Cross-file invariants

- The default Firefox enterprise proxy and both router backends use HTTP `127.0.0.1:4444`. Validated `ROUTER_HTTP_PROXY_*` overrides are written to generated HTTP/SSL policy fields; keep the selected endpoint, manual mode, lock, DNS handling, and empty passthrough aligned.
- The browser profile uses `browser/data`; build staging preserves this state while regenerating selected build-owned files such as `user.js` and the locale marker.
- i2pd console is `127.0.0.1:7070`; Java I2P console is `127.0.0.1:7657`. Only i2pd exposes SAM, at `127.0.0.1:7656`.
- Local proxy/console/SAM binds are distinct from router transport networking and UPnP. Do not infer that all router traffic stays on loopback.
- Router stop operations must not terminate a system-managed instance that this project did not start.
- Linux and Windows use separate source implementations. A change to behavior should be reviewed in Bash, PowerShell, and the relevant CMD shim rather than inferred from one platform.

## Exclusions and limits

Generated `browser/`, `.browser-build/`, `.browser-old/`, managed `vendor/`
releases, and `i2p-java/data/` are ignored output or runtime/user state and were
not edited. Binary executables, archives, Java libraries, and cryptographic
certificate/address-book records are not suitable targets for inline comments.
The exact semantics of every Firefox preference and every third-party router
property vary by upstream version; consult the relevant upstream documentation
before changing one, and do not infer runtime enforcement from a valid file.
