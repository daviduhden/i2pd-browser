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

Run `python3 scripts/validate-agent-maintenance.py` before proposing a change.
The GitHub Actions pull request check runs the same validator against the PR
base. It detects changed project paths, requires a non-empty content addition
to an agent instruction or skill, validates skill frontmatter and local Markdown
links, and reports its limits: structural checks cannot decide whether a
knowledge update is semantically relevant. Review that relevance manually.
There is no local hook; contributors can run the script directly, and CI is the
automated enforcement point. Agent/skill changes require one complete review of
the instruction system; repeat it only when the review finds a defect to fix.
