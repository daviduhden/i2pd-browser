---
name: agent-maintenance
description: Maintain repository agent instructions, skills, and automated synchronization enforcement. Use when changing AGENTS.md, agent-specific instructions, skills, the maintenance validator, or its CI integration.
---

# Agent and skill maintenance

## When to use

Use this skill for changes to `AGENTS.md`, tool-specific agent rules,
`.agents/skills/**/SKILL.md`, other supported skill directories, or the
validator and workflow that enforce synchronization. The repository has a root
`AGENTS.md` and project skills under `.agents/skills/`; it currently has no
specialized agent definition files.

## Procedure

1. Inventory all root and nested `AGENTS.md` files, supported tool-specific
   instruction files, and skills under `.agents/skills/`, `.github/skills/`,
   and `.claude/skills/`. Check existing GitHub workflows and hooks before
   changing enforcement.
2. Map each instruction or skill to its scope. Prefer updating an existing
   applicable skill. Add a new skill only for a distinct, recurring workflow;
   link it from the root instructions and avoid overlapping scopes.
3. Keep the root rule authoritative. Specialized agents must include
   `Post-Change Knowledge Synchronization`; skills must include
   `Maintenance & Continuous Learning`. Preserve Agent Skills YAML frontmatter.
4. Keep `scripts/validate-agent-maintenance.py` dependency-free. It compares
   the Git base against `HEAD` and includes local staged, unstaged, and
   untracked changes. The PR workflow supplies the base commit. Generated and
   user-state directories are excluded from project-change enforcement.
5. The validator requires a non-empty content addition to an agent/skill
   instruction, checks skill frontmatter and local Markdown links, and checks
   required maintenance sections. Run it locally:

   ```sh
   python3 scripts/validate-agent-maintenance.py
   ```

   In CI, pass `--base <pull-request-base-sha>` as the workflow does.
6. Validate the workflow syntax and inspect its event, permissions, checkout
   depth, base selection, and command. Run the validator and `git diff --check`.
   Do not claim CI ran locally or that structural checks establish semantic
   relevance. A reviewer must assess whether the edited knowledge matches the
   implementation.
7. Review the entire instruction system once after changes to this policy,
   agents, skills, or enforcement. Repeat only if the review finds a defect.

## Enforcement limits

- GitHub Actions runs the validator on pull requests. There is no local hook;
  contributors run the same command directly.
- The validator cannot prove that prose is a meaningful improvement for the
  changed behavior. A human review remains required.
- The pull request check validates the submitted change against its base; it
  does not alter branch protection settings.

## Maintenance & Continuous Learning

After using this skill to modify the repository, review this skill and the
applicable `AGENTS.md` and agent instructions once at task end. Update this skill
when its procedures, tools, configuration, project facts, assumptions, examples,
or validation steps have changed or when implementation work produced reusable
knowledge. Correct instructions that proved wrong, remove obsolete details,
and keep references and repository-relative paths valid. Avoid notes tied only
to one execution. If another agent or skill owns the affected procedure, update
or link that source rather than duplicating it. Run `python3
scripts/validate-agent-maintenance.py` after synchronizing. Its structural checks
do not judge semantic relevance; review that manually. Report the
synchronization result and checks actually run in the final response. If
synchronization cannot be completed, state why and mark the task incomplete.
