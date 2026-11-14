# Contributing

All contributions are welcome, including those created or assisted by artificial intelligence (AI).

**The use of AI is explicitly permitted**, without any requirement to disclose its use.

All changes must be appropriately tested and verified before submission, regardless of whether they were produced manually or with AI assistance.

Contributors are responsible for ensuring that their changes work as intended and do not introduce regressions.

## Agent and skill synchronization

Every repository change must include a relevant, substantive update to the
operational knowledge used by agents. Review root and nested `AGENTS.md` files,
tool-specific agent instructions, and the skills that cover the changed paths.
Update affected procedures, assumptions, examples, references, and validation
commands; create a skill only for a recurring workflow not covered by an existing
one. If maintenance cannot be completed, the task is incomplete and the
limitation must be reported.

Run `perl scripts/validate-agent-knowledge.pl --scope worktree` before proposing a
change. The GitHub Actions workflow is manual-only; it is not an automatic pull
request check. A clean worktree check validates structure but does not inspect
knowledge coverage of committed changes. To inspect a committed proposal, supply
both revisions with `--scope range --base BASE_REF --head HEAD_REF`; the validator
compares from their merge base. The workflow provides the same explicit range
selection without changing branch protection or the canonical validator.

Structural validation cannot decide whether a knowledge update is semantically
relevant. Review that relevance manually. There is no local hook. The workflow
has read-only repository permissions and does not edit source files.

## Validation and development environment

Use Bash, ShellCheck, shfmt, jq, Git, and Perl 5.14+ for the documented Linux
checks. Browser builds additionally need curl, tar and its compression support,
SHA-512 tools, and unzip; router operation requires screen and the selected
router/runtime. `tests/test-noscript.bash` additionally uses Python 3
standard-library ZIP fixtures; Python is not a browser build/runtime dependency. On Windows check both PowerShell 5.1 and 7 when available.
Do not install packages or build a browser merely to review documentation.

Follow [AGENTS.md](AGENTS.md) for the commands applicable to each changed path.
The i18n, proxy, and validator contract suites create temporary files; they are
behavioral tests, not static analysis. If a request permits only static checks,
do not execute them and report that limitation explicitly. A parsed script or
valid JSON is not evidence of a successful build or runtime privacy test.

See [security and maintenance](docs/security-and-maintenance.md) for download
trust boundaries, compatibility, recovery, accessibility, and performance
validation requirements.

## Manual Linux and Windows CI

The repository owner can open **Actions → Tests (Linux and Windows) → Run
workflow**, or run `gh workflow run tests.yml`. The workflow must be present on
the default branch to appear as a manual action. It has no push, pull request,
scheduled, or reusable-workflow triggers. Both the original actor and the actor
requesting a re-run must match the repository owner. Other actors' jobs are
skipped before a runner is allocated; this is an execution gate, not a change
to GitHub's visibility of the dispatch button.

The matrix runs these suites with temporary, offline fixtures:

| Runner | Tests |
| --- | --- |
| Ubuntu 24.04 | All six `tests/test-*.bash` suites and the Perl validator contract |
| Windows Server 2022 / PowerShell 5.1 | i18n, proxy policy, router safety, process ownership |
| Windows Server 2022 / PowerShell 7 | The same four native PowerShell suites |

Windows parses all PowerShell source before executing the suites. Linux checks
Bash syntax, policy JSON, and required tools first. Every suite has a separate
step, and failures in one matrix entry do not cancel the others. The jobs have
read-only repository permissions, no persisted checkout credentials, no secrets,
and a 15-minute limit. They do not download a browser or start a real router.
The runners must provide the listed tools; CI does not run the project installer
or install router packages.

The **Agent Knowledge Validation** workflow has the same owner-only/manual gate
and retains its separate range/worktree inputs. A successful CI test run is not
a browser build, a real process-lifecycle test, or a runtime leak audit.

Validate workflow changes locally with all three linters:

```sh
actionlint .github/workflows/*.yml
yamllint --strict .github/workflows/*.yml
zizmor --offline --no-progress .github/workflows/*.yml
```

The default yamllint rules apply, including document start markers, quoted `on`,
and the 80-character line limit. Zizmor offline mode omits online audits and does
not verify remote action metadata. These checks do not execute GitHub Actions.
