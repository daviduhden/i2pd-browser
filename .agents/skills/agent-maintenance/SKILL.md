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
4. Keep `scripts/validate-agent-knowledge.pl` dependency-free. It compares
   the Git base against `HEAD` and includes local staged, unstaged, and
   untracked changes. Range comparisons supply an explicit base commit. Generated and
   user-state directories are excluded from project-change enforcement.
5. The validator requires a non-empty content addition to an agent/skill
   instruction, checks skill frontmatter and local Markdown links, and checks
   required maintenance sections. Run it locally:

   ```sh
   perl scripts/validate-agent-knowledge.pl --scope worktree
   ```

   For committed comparisons, pass `--base <base-sha>` locally.
6. Validate the workflow syntax and inspect its event, permissions, checkout
   depth, base selection, and command. Run the validator and `git diff --check`.
   Do not claim CI ran locally or that structural checks establish semantic
   relevance. A reviewer must assess whether the edited knowledge matches the
   implementation.
7. Review the entire instruction system once after changes to this policy,
   agents, skills, or enforcement. Repeat only if the review finds a defect.
8. For source-documentation work, keep `docs/configuration-and-source-map.md`
   synchronized with maintained configuration families, producer/consumer
   relationships, exclusions, and cross-file invariants. Add reusable findings
   to the skill that owns the affected workflow; do not use a cosmetic skills
   edit merely to satisfy the automatic change-coverage check.

## Enforcement limits

- GitHub Actions runs the validator only on manual dispatch. There is no local
  hook; contributors run the same command directly.
- The validator cannot prove that prose is a meaningful improvement for the
  changed behavior. A human review remains required.
- The manual check validates the checked-out worktree; range mode is available
  for explicit committed comparisons. It does not alter branch protection settings.

## GitHub Actions pin maintenance

The manual-only workflow pins each external action to an immutable
40-character commit SHA; tags and branches are not acceptable because they can
be moved. When changing a pin, verify the release SHA first and update the
`uses:` line and its trailing `# vX.Y.Z` comment in the same edit. Keep the
workflow's triggers, permissions, concurrency, job names, and commands
unchanged.

| Action | Version | Commit SHA |
| --- | --- | --- |
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/upload-artifact` | `v7.0.2` | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` |
| `actions/cache` | `v6.1.0` | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `actions/setup-java` | `v6.2.0` | `77dd5b2ce225ea11469928ac317850245a74ae78` |
| `actions/setup-node` | `v7.1.0` | `949feb2413d6458794dcd2491c4babbbce0c15c1` |

Validate a workflow edit with `actionlint .github/workflows/*.yml` and, when a
`yamllint` configuration exists, `yamllint -c <config> .github/workflows`.

## Maintenance & Continuous Learning

After using this skill to modify the repository, review this skill and the
applicable `AGENTS.md` and agent instructions once at task end. Update this skill
when its procedures, tools, configuration, project facts, assumptions, examples,
or validation steps have changed or when implementation work produced reusable
knowledge. Correct instructions that proved wrong, remove obsolete details,
and keep references and repository-relative paths valid. Avoid notes tied only
to one execution. If another agent or skill owns the affected procedure, update
or link that source rather than duplicating it. Run `perl scripts/validate-agent-knowledge.pl --scope worktree` after synchronizing. Its structural checks
do not judge semantic relevance; review that manually. Report the
synchronization result and checks actually run in the final response. If
synchronization cannot be completed, state why and mark the task incomplete.
