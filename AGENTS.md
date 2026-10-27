# I2Pd Browser Agent Instructions

This repository builds a preconfigured Firefox ESR for I2P on Linux and
Windows. It also prepares and manages one of two I2P routers, either from
a system installation or from a project-managed copy under `vendor/`.

## Architecture

- `install.bash` / `install.ps1` are both installer and router manager.
  The selected backend, source, and language are stored in
  `i2pd-browser.conf` at the repository root.
- `lib/router.bash` / `lib/router.ps1` define the shared router
  abstraction. `lib/backends/i2pd.*` and `lib/backends/i2p-java.*`
  implement it.
- `i2pd/` holds the vendored i2pd configuration, certificates, address
  book, and launcher. i2pd runs with `--datadir=.`, so configuration and
  runtime state stay together; runtime state is ignored by Git.
- `i2p-java/config/` is vendored configuration. `i2p-java/data/` is the
  effective configuration plus runtime state, seeded from `config/`
  without overwriting existing files. The launcher passes an absolute
  `-Di2p.dir.config`, so the user's `~/.i2p` is never used.
- `build/` contains the Firefox ESR builders, Firefox preferences,
  enterprise policies, autoconfig, launcher scripts, and the portable
  profile seed. `browser/` is generated and ignored; `browser/data/` is
  the portable Firefox profile.
- Builds are staged in `.browser-build/` and published only after the
  layout and proxy policy validate. A rebuild preserves `browser/data/`
  (bookmarks, history, cookies, logins, extensions) instead of deleting
  the user profile.
- `vendor/` contains managed router releases and is ignored. `locales/`
  contains data-only message catalogs. `tests/` contains the i18n tests.

## Supported targets

- Linux build: `x86_64`, `aarch64`, and `i686`. Mozilla no longer
  publishes current-branch 32-bit Linux ESR, so use
  `ESR_PRODUCT=firefox-esr-latest` for `i686`.
- Windows build: `x86_64`, `i386`, and `aarch64`. The vendored i2pd
  option currently provides Windows `x86_64` and `i386` only.
- Routers: i2pd (C++) and I2P (Java). Both expose the Firefox HTTP proxy
  on `127.0.0.1:4444`; consoles are `127.0.0.1:7070` and
  `127.0.0.1:7657` respectively. i2pd also enables SAM on `7656`; I2P
  (Java) does not start SAM.

## Commands that exist

```sh
./install.bash --help
./install.bash --i2p-router=i2pd
./install.bash --i2p-router=i2p-java --router-source=vendored
./install.bash status
./install.bash detect
./install.bash configure --language=es-ES
./install.bash start|stop|restart|console

(cd build && ./build.bash --language=en-US)
build\build.cmd --language=en-US          # Windows
```

`--install-deps` is opt-in and may use `sudo` or `winget`; never run it
as part of a documentation or review task. There is no Makefile and no
CI workflow. These manual checks are the available validation:

```sh
bash tests/test-i18n.bash
pwsh -NoProfile -File tests/test-i18n.ps1   # when pwsh is available
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
python3 scripts/validate-agent-maintenance.py
git diff --check
```

A build downloads Firefox ESR and NoScript and writes `browser/`. Run it
only when the task needs a bundle and the environment allows network
access. `browser/`, `vendor/`, and `i2p-java/data/` are generated or
user state, not source.

## Security and privacy policy

- Never weaken or remove the proxy, update, telemetry, search, or
  extension restrictions. A change that can make Firefox fall back to a
  direct connection is a security regression.
- Preserve manual proxy mode, the loopback HTTP/SSL proxy endpoint,
  DNS-through-proxy, the empty passthrough list, and
  `network.proxy.failover_direct=false`. Keep DoH, captive-portal, and
  connectivity probes disabled.
- Keep every router listener on loopback. Do not expose a proxy,
  console, SAM bridge, or administrative interface to the LAN.
- Do not add external network connections, telemetry, analytics, or new
  download origins. Existing build/install downloads must stay HTTPS
  and integrity-checked where the code supports it. Firefox and i2pd
  use SHA-512 checks; NoScript is structurally checked but not
  signature-verified; vendored I2P (Java) has no checksum verification.
  Do not describe any of these as stronger than they are.
- Never stop a router that was not started by I2Pd Browser. Use the
  system service or the router's own tooling instead.
- Never commit keys, `netDb/`, peer profiles, logs, `i2p-java/data/`,
  `vendor/`, `browser/`, or `i2pd-browser.conf`.
- Preserve copyrights and licenses. The project is BSD-3-Clause; the
  routers, Firefox ESR, and NoScript keep their own terms.

## Testing and evidence

- Distinguish static analysis, syntax checks, unit tests, a real build,
  and a runtime smoke test. Do not claim one as another.
- Run the i18n test for any catalog, locale-selection, installer, or
  build-message change. Run the PowerShell test when `pwsh` exists.
- Run `bash -n`, `shellcheck`, and `shfmt -d` after shell changes. Do
  not add a lint dependency the repository does not already assume.
- Validate JSON with `jq`, and inspect the final diff with
  `git diff --check` and `git status`.
- A successful syntax check is not proof that Firefox starts, that
  policies apply, or that the router reaches the I2P network. State
  what was not run.

## Pre-existing changes and delivery

Inspect `git status`, `git diff`, and ignored generated files before
editing. Preserve unrelated work and user data. Do not run
`git clean`, delete `browser/`, `vendor/`, or `i2p-java/data/`, or reset
files without explicit authorization. Do not commit or push unless
asked. If an existing instruction or skill is useful, improve it in
place rather than replacing it.

## Localization conventions

- User-visible script text belongs in `locales/*.properties`; use a
  stable dotted key and keep the four catalogs key-for-key identical.
- Catalogs are UTF-8 data files. Do not source, dot-source or evaluate
  them; use `i18n_message` in Bash and `Get-I18nMessage` in
  PowerShell.
- Preserve technical identifiers, commands, paths, protocols and
  configuration values. Use `{0}`, `{1}`, and so on for interpolated
  values.
- Update both `lib/i18n.bash` and `lib/i18n.ps1`, documentation, and
  the i18n tests when adding a locale or changing locale selection.
- Do not loosen Firefox preferences, policies, proxy controls, update
  restrictions or telemetry restrictions for localization.

See `localization-maintenance` for the full procedure.

## Continuous Agent & Skills Maintenance

This requirement applies to every agent and tool that changes this repository.

> Agent instructions and skills are living repository artifacts.
>
> Every repository modification MUST include an agent/skills synchronization step.
>
> Before completing any task, inspect the applicable AGENTS.md and SKILL.md files, update the affected instructions, and validate their consistency with the implementation.
>
> A code change without the corresponding agent knowledge maintenance is considered incomplete.
>
> Never claim completion when the synchronization step has been skipped or has failed.

After any repository modification (including code, configuration, dependencies,
tests, workflows, or documentation), make one complete synchronization review:

1. Inspect all applicable `AGENTS.md` files, tool-specific agent instructions,
   and `.agents/skills/**/SKILL.md`, `.github/skills/**/SKILL.md`, and
   `.claude/skills/**/SKILL.md` files. Also check repository instructions for
   other agent tools, such as `.github/agents/*.agent.md` and Cursor rules.
2. Map changed paths and behavior to the existing agents and skills by their
   scope, triggers, procedures, validation commands, and references. Update
   every affected instruction and any reusable finding that improves future
   work; remove stale or contradictory details.
3. Update an existing skill when its scope matches and its procedure, facts,
   assumptions, examples, commands, or validation changed. Create a skill only
   when recurring work has a distinct reusable workflow not covered by an
   existing skill. Keep agent roles and skill scopes linked and non-duplicative.
4. Keep each specialized agent's triggers, workflow, delegation/validation
   expectations, and final report aligned with its related skills. Preserve
   skill frontmatter and Agent Skills compatibility.
5. Validate changed instruction files for readable Markdown, required
   headings/frontmatter, and working repository-relative links. Run
   `python3 scripts/validate-agent-maintenance.py` after synchronization.
   The validator checks Git change coverage and structural consistency; human
   review must still confirm that the update is semantically relevant.
6. If synchronization or validation cannot be completed, fix it or report the
   exact limitation and mark the task incomplete. Do not silently omit it.

Avoid maintenance loops: perform one full review at the end of a task, and
repeat only if that review finds an error that is corrected. Changes to this
policy, an agent, or a skill require checking the complete instruction/skill
system for consistency.

### Mandatory Definition of Done

- [ ] Repository changes implemented.
- [ ] Relevant agent instructions reviewed.
- [ ] Relevant skills reviewed.
- [ ] Affected AGENTS.md / SKILL.md files updated.
- [ ] Obsolete knowledge removed.
- [ ] New reusable knowledge incorporated.
- [ ] Agent and skill references validated.
- [ ] Automated maintenance checks passed.
- [ ] Final synchronization status reported.

Every final report must contain **Agent & Skills Synchronization** and state
agents reviewed, skills reviewed, instruction files updated, reusable knowledge
added/corrected, validations actually run, and a final `PASS` or `FAIL` status.
An unavailable check must be reported as not run, never as passed.

## Specialized skills

Use these instead of re-deriving project details:

| Skill | Use when |
| --- | --- |
| [agent-maintenance](.agents/skills/agent-maintenance/SKILL.md) | Changing repository agent instructions, skills, or maintenance enforcement. |
| [firefox-esr-bundling](.agents/skills/firefox-esr-bundling/SKILL.md) | Changing the Firefox ESR download, extraction, profile, or bundle layout. |
| [i2p-router-integration](.agents/skills/i2p-router-integration/SKILL.md) | Changing router detection, lifecycle, backend config, or vendored routers. |
| [privacy-and-leak-audit](.agents/skills/privacy-and-leak-audit/SKILL.md) | Reviewing Firefox or router changes for clearnet leaks and weakened controls. |
| [cross-platform-installers](.agents/skills/cross-platform-installers/SKILL.md) | Editing installers, `.cmd` shims, PowerShell ports, or CLI behavior. |
| [browser-build-validation](.agents/skills/browser-build-validation/SKILL.md) | Validating a build change or deciding what evidence is required. |
| [localization-maintenance](.agents/skills/localization-maintenance/SKILL.md) | Adding or changing user-visible text, catalogs, or locale selection. |
