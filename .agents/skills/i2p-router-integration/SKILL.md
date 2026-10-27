---
name: i2p-router-integration
description: Change or audit the I2P router abstraction. Use when editing lib/router.*, lib/backends/*, i2pd/ or i2p-java/ configuration, router detection, lifecycle commands, or vendored router handling.
---

# I2P router integration

## When to use

Use this skill for backend interface changes, detection order, start and
stop behavior, configuration seeding, port normalization, vendored
router downloads, and the `install.bash` / `install.ps1` management
commands. Use `firefox-esr-bundling` for Firefox-specific work.

## Project facts

- Supported backends are `i2pd` (C++, default) and `i2p-java` (I2P).
  The valid sources are `system` and `vendored`.
- `lib/router.bash` and `lib/router.ps1` share the interface. Each
  backend implements the same operations under its own naming
  convention. A new backend must provide the installed, running,
  managed, misconfigured, prepare-config, console, start, stop,
  dependency, and vendor-install operations used by the dispatcher.
- Both backends default the HTTP proxy to `127.0.0.1:4444` and SOCKS
  to `127.0.0.1:4447`. `ROUTER_HTTP_PROXY_HOST` / `PORT` and
  `ROUTER_SOCKS_PROXY_HOST` / `PORT` can override these loopback endpoints;
  builders consume the HTTP override for both Firefox HTTP and SSL policy
  fields. i2pd uses console `127.0.0.1:7070` and SAM
  `7656`; I2P (Java) uses console `127.0.0.1:7657` and starts no SAM.
- i2pd runs from `i2pd/` with `--datadir=.`. Its config, certificates,
  address book, and runtime state share that directory. Runtime state
  (`netDb/`, keys, logs, `*.dat`, address-book text files) is ignored.
- I2P (Java) keeps vendored files in `i2p-java/config/` and effective
  configuration plus runtime state in `i2p-java/data/`. Seeding copies
  only missing files, so an existing `data/` keeps user changes and
  does not automatically receive later vendored edits. The launcher
  passes absolute `-Di2p.dir.base` and `-Di2p.dir.config`; the global
  `~/.i2p` must remain untouched.
- Linux start uses detached `screen` sessions named `i2pd` and
  `i2p-java`. Managed detection is the matching screen session.
  Windows uses hidden processes and `<backend>/.router.pid`.
- `stop` and `restart` refuse to stop a running router unless it is
  detected as managed. This is a safety invariant, not an obstacle to
  work around.
- Vendored i2pd downloads the latest GitHub release and verifies the
  release asset against the release `SHA512SUMS` before extraction.
  Vendored I2P (Java) downloads the official installer over HTTPS,
  runs its interactive console installer, and has no checksum or
  signature verification. Do not claim otherwise.

## Procedure

1. Read both language versions of the abstraction and the affected
   backend before editing. Check `git diff` for unrelated changes.
2. Change the shared behavior in `lib/router.bash` and
   `lib/router.ps1`, then update both backend implementations. Do not
   create a Bash-only feature unless the Windows path explicitly
   rejects or documents it.
3. Keep all listeners loopback-only. Do not add LAN exposure, UPnP
   changes, port-forwarding rules, or a second proxy endpoint.
4. Preserve the managed-versus-unmanaged distinction. Never replace it
   with a broad process-name check that could stop a system service.
5. Keep the effective configuration isolated per backend. Do not point
   either router at a user's global configuration directory.
6. For vendored i2pd, keep the SHA-512 fetch, exact asset-name match,
   failure cleanup, and `VERSION` write. For vendored I2P (Java), keep
   HTTPS and state the missing integrity check in review notes.
7. Keep endpoint overrides loopback-only (`127.0.0.1`) and validate ports
   in the 1-65535 range. The installers pass the selected HTTP endpoint to
   the builders, which rewrite generated HTTP and SSL policy values; preserve
   the manual mode, lock, DNS-through-proxy, and empty passthrough controls.
8. Update `README.md`, `i2p-java/README.md`, and the relevant skill
   when observable behavior changes.

## Validation

Safe static checks:

```sh
bash -n install.bash lib/router.bash lib/backends/*.bash \
  i2pd/*.bash i2p-java/*.bash
shellcheck install.bash lib/router.bash lib/backends/*.bash \
  i2pd/*.bash i2p-java/*.bash
shfmt -d install.bash lib/router.bash lib/backends/*.bash \
  i2pd/*.bash i2p-java/*.bash
```

Read-only or low-impact checks:

```sh
./install.bash status
./install.bash detect
bash tests/test-proxy-policy.bash
jq -e '.policies.Proxy.HTTPProxy == "127.0.0.1:4444"' \
  build/preferences/distribution/policies.json
```

`detect` loads each backend and may query `systemctl` or `pgrep`; it
does not start or stop a router. Do not run `start`, `stop`, `restart`,
`configure`, or `--install-deps` on a real host just to test a change.

If a router is already running, treat it as user state. Do not kill it,
delete its PID file, or remove its data directory.

## Common problems

- **Stale I2P (Java) config.** `i2p-java/data/` is seeded once. Editing
  `i2p-java/config/` does not update an existing effective file. Test a
  config change with a disposable `data/` directory.
- **Wrong managed detection.** A same-name screen session or a reused
  PID can look managed. Do not widen the check; narrow changes only
  with evidence.
- **Windows force stop.** The PowerShell backend uses
  `Stop-Process -Force`; preserve the managed check before it.
- **i2pd misconfigured state.** On Windows it is always reported as not
  misconfigured, even if optional steps fail. Do not assume that state
  proves a healthy router.
- **Missing `screen` on Linux.** Start fails without it. Keep the
  dependency hint accurate.
- **Vendored I2P (Java) installer.** It is interactive and unverified.
  Automation must not pretend it is unattended.
- **Port drift.** The router configs, shared defaults, Firefox policy,
  and documentation are separate sources of truth. Update all of them.
- **Configuration write failures.** Bash writes the config through a
  temporary file and rename; PowerShell now writes a temporary file and
  replaces it. Preserve that behavior.

## References

- `lib/router.bash`, `lib/router.ps1` - shared abstraction.
- `lib/backends/i2pd.bash`, `lib/backends/i2pd.ps1` - i2pd backend.
- `lib/backends/i2p-java.bash`, `lib/backends/i2p-java.ps1` - I2P
  (Java) backend.
- `i2pd/i2pd.conf`, `i2pd/tunnels.conf` - vendored i2pd config.
- `i2p-java/config/*` - vendored I2P (Java) config.
- `i2p-java/README.md` - backend-specific layout.
- `README.md` - supported routers, ports, and lifecycle.
- `docs/configuration-and-source-map.md` - router config files and cross-backend invariants.
- Related skills: `privacy-and-leak-audit`,
  `cross-platform-installers`, `browser-build-validation`.

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
