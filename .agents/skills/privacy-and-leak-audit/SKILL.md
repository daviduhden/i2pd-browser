---
name: privacy-and-leak-audit
description: Audit browser and router changes for clearnet leaks and weakened Firefox controls. Use when editing preferences, policies, proxy settings, DNS, WebRTC, telemetry, updates, search, extensions, router endpoints, or launchers.
---

# Privacy and leak audit

## When to use

Use this skill before merging any change that can affect where browser
or router traffic goes, which remote services Firefox contacts, whether
an update or telemetry path is enabled, or whether a user can override a
privacy control. This is a review skill; it does not replace a runtime
test.

## Non-negotiable invariants

- Firefox uses a locked manual proxy. The HTTP and SSL proxy are
  `127.0.0.1:4444`, DNS goes through the proxy, and the passthrough
  list is empty.
- `network.proxy.type` is `1`, and
  `network.proxy.failover_direct` is locked to `false`. A proxy failure
  must stop navigation, not fall back to direct access.
- DoH is disabled and locked. Captive-portal and connectivity probes
  are locked off. The expected HTTPS-only mode is intentionally
  disabled so `.i2p` HTTP sites work; do not "fix" that by enabling
  clearnet HTTPS upgrades.
- All router listeners are loopback-only: HTTP 4444, SOCKS 4447,
  i2pd console 7070, I2P (Java) console 7657, SAM 7656 (i2pd only).
- Telemetry, Normandy/Shield, Firefox Accounts/Sync, studies, sponsored
  content, search suggestions, and automatic Firefox updates stay
  disabled. I2P (Java) update checks are notify-only and routed through
  the local HTTP proxy.
- NoScript remains installed at application level. It is not enforced
  by an enterprise policy; do not describe it as locked.
- The launchers must keep the portable profile (`-profile data`),
  avoid root, and avoid inheriting a hostile `LD_PRELOAD`. The Linux
  launcher uses `HOME` inside the bundle and `GSETTINGS_BACKEND=memory`
  for isolation.
- The only normal build/install download origins are Mozilla, AMO, the
  i2pd GitHub release API/assets, and i2p.net/files.i2p.net. Do not add
  another origin or a runtime call home.

## Procedure

1. List every changed pref, policy, router option, URL, and launcher
   environment change. For each, name the traffic path it creates or
   removes.
2. Confirm that the proxy endpoint still exists in the generated policy,
   not only as a manual proxy mode pref. The endpoint is set in
   `build/preferences/distribution/policies.json`.
3. Check whether a changed pref is `lockPref`, `defaultPref`, or
   `pref`. `defaultPref` is user-overridable; do not claim it is locked.
4. Check both router backends. A change that only fixes i2pd still needs
   an I2P (Java) answer, and vice versa.
5. Check the launchers and installers for new environment variables,
   command execution, URL fetches, or profile paths.
6. If a new URL is unavoidable, require HTTPS, explain why it is
   necessary, and use an existing integrity mechanism. Never add
   telemetry, analytics, or a background poller.
7. Run the static checks below and record exactly what was reviewed.
   Do not claim a runtime leak test unless Firefox and a router were
   actually run with traffic capture.

## Validation

Parse the policy and assert the proxy controls:

```sh
jq -e '
  .policies.Proxy.Mode == "manual" and
  .policies.Proxy.Locked == true and
  .policies.Proxy.HTTPProxy == "127.0.0.1:4444" and
  .policies.Proxy.SSLProxy == "127.0.0.1:4444" and
  .policies.Proxy.UseProxyForDNS == true and
  .policies.Proxy.Passthrough == "" and
  .policies.DNSOverHTTPS.Enabled == false and
  .policies.DNSOverHTTPS.Locked == true and
  .policies.DisableTelemetry == true and
  .policies.DisableAppUpdate == true
' build/preferences/distribution/policies.json
```

Check the Firefox prefs:

```sh
grep -nE 'network\.proxy\.(type|failover_direct)|network\.trr|telemetry|app\.update' \
  build/preferences/i2pd-browser.cfg
grep -n 'network.proxy.failover_direct' build/preferences/i2pd-browser.cfg
```

Check router binds and ports:

```sh
grep -nE '^(address|port|interface|listenPort|proxy_host|proxy_port)[[:space:]]*=' \
  i2pd/i2pd.conf i2p-java/config/*.config \
  i2p-java/config/addressbook/config.txt
```

Check external URLs and launcher environment changes:

```sh
grep -RInE 'https?://' -- build install.bash install.ps1 lib i2pd i2p-java \
  | grep -v '^Binary'
git diff -- build/scripts lib install.bash install.ps1
```

Inspect the built bundle when one exists:

```sh
jq -e '.policies.Proxy.HTTPProxy == "127.0.0.1:4444"' \
  browser/distribution/policies.json
grep -n 'intl.locale.requested' browser/data/user.js
```

Do not send traffic to a clearnet test site. Use the existing
`./install.bash status` and a local proxy reachability check only.

## Common problems

- **Proxy mode without endpoint.** If `policies.json` is missing or
  malformed, manual mode may have no usable proxy. Build validation now
  rejects that, but review it separately.
- **Locked versus default.** Many privacy prefs are `defaultPref` and
  can be changed by the user. Do not overstate the hardening.
- **HTTPS-only mode.** It is disallowed on purpose for `.i2p`; enabling
  it can break ordinary I2P browsing.
- **Certificate-error page.** `browser.xul.error_pages.expert_bad_cert`
  is a user-overridable escape hatch. Do not describe certificate
  errors as impossible to bypass.
- **NoScript.** Sideloading is not enforcement. Updates and removal are
  not policy-locked.
- **Outproxy distinction.** Clearnet access through an I2P outproxy is
  an intentional I2P feature; direct clearnet access is the leak to
  prevent. Do not conflate them.
- **Version-dependent policies.** `AIControls`, `LocalNetworkAccess`,
  `BrowserDataBackup`, `IPProtectionAvailable`, `VisualSearchEnabled`,
  and `XSLTEnabled` may be ignored by older ESR builds. A newer ESR
  target may therefore be less restrictive than the source suggests.
- **Launcher profile.** A relative `-profile data` can create a new
  profile in the caller's directory. The Windows launcher now uses an
  absolute path; keep it absolute.

## References

- `build/preferences/i2pd-browser.cfg` - Firefox prefs.
- `build/preferences/distribution/policies.json` - locked policies.
- `i2pd/i2pd.conf`, `i2p-java/config/i2ptunnel.config` - proxy and
  listener configuration.
- `build/scripts/start-i2pd-browser.bash` - Linux launcher isolation.
- `build/scripts/start-i2pd-browser.ps1` - Windows launcher.
- `README.md` - documented ports, proxies, and update behavior.
- Related skills: `firefox-esr-bundling`, `i2p-router-integration`,
  `browser-build-validation`.

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
