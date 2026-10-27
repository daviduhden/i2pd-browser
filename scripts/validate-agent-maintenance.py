#!/usr/bin/env python3
"""Enforce structural agent/skill synchronization for a Git change set."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAINTENANCE_RE = re.compile(
    r"^(?:AGENTS\.md|(?:.*/)?AGENTS\.md|\.agents/skills/.+/SKILL\.md|"
    r"\.github/skills/.+/SKILL\.md|\.claude/skills/.+/SKILL\.md|"
    r"\.(?:github|claude)/agents/.+\.agent\.md|\.github/copilot-instructions\.md|"
    r"\.github/instructions/.+\.instructions\.md|\.claude/CLAUDE\.md|"
    r"\.cursor/rules/.+|\.cursorrules)$"
)
DOC_RE = re.compile(
    r"(?:^|/)(?:AGENTS\.md|SKILL\.md|[^/]+\.agent\.md)$|"
    r"^(?:\.cursor/rules/|\.github/instructions/|\.github/copilot-instructions\.md$|"
    r"\.claude/CLAUDE\.md$|\.cursorrules$)"
)
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout


def changed_paths(base: str | None) -> set[str]:
    paths: set[str] = set()
    if base:
        paths.update(line for line in git("diff", "--name-only", f"{base}...HEAD").splitlines() if line)
    # Include staged and unstaged tracked changes for local use.
    paths.update(line for line in git("diff", "--name-only", "HEAD").splitlines() if line)
    # Include untracked files, but not ignored build/user state.
    for line in git("status", "--porcelain", "--untracked-files=all").splitlines():
        if line and line[:2] == "??":
            paths.add(line[3:])
    return paths


def substantive_addition(path: str, base: str | None) -> bool:
    """Require actual added prose/content, not a touched file or blank lines."""
    chunks: list[str] = []
    if base:
        chunks.append(git("diff", "--no-ext-diff", "--unified=0", f"{base}...HEAD", "--", path))
    chunks.append(git("diff", "--no-ext-diff", "--unified=0", "HEAD", "--", path))
    for chunk in chunks:
        for line in chunk.splitlines():
            if not line.startswith("+") or line.startswith("+++"):
                continue
            content = line[1:].strip()
            if content and not re.fullmatch(r"(?:[-*_`~#> ]+|\|+|\d+\.)", content):
                return True
    # New untracked maintenance files must contain meaningful content.
    file_path = ROOT / path
    return file_path.is_file() and "?? " + path in git("status", "--porcelain", "--untracked-files=all") and bool(file_path.read_text(encoding="utf-8").strip())


def validate_file(path: str) -> list[str]:
    errors: list[str] = []
    file_path = ROOT / path
    try:
        content = file_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        return [f"{path}: cannot read UTF-8 instruction file: {exc}"]
    if not content.strip():
        return [f"{path}: instruction file is empty"]
    if path.endswith("SKILL.md"):
        if not content.startswith("---\n") or "\n---\n" not in content[4:]:
            errors.append(f"{path}: missing Agent Skills YAML frontmatter")
        else:
            frontmatter = content.split("\n---\n", 1)[0]
            for key in ("name:", "description:"):
                if not re.search(rf"(?m)^{re.escape(key)}\s*\S", frontmatter):
                    errors.append(f"{path}: frontmatter missing {key[:-1]}")
        if not re.search(r"(?m)^# .+", content):
            errors.append(f"{path}: missing level-one title")
    for target in LINK_RE.findall(content):
        target = target.strip().split()[0].split("#", 1)[0]
        if not target or re.match(r"(?:https?://|mailto:|#|[a-z]+:)", target, re.I):
            continue
        candidate = (file_path.parent / target).resolve() if not target.startswith("/") else (ROOT / target.lstrip("/")).resolve()
        try:
            candidate.relative_to(ROOT)
        except ValueError:
            errors.append(f"{path}: link escapes repository: {target}")
            continue
        if not candidate.exists():
            errors.append(f"{path}: broken repository-relative link: {target}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="base commit/ref for a PR comparison (uses base...HEAD)")
    args = parser.parse_args()
    try:
        root_instructions = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        if "## Continuous Agent & Skills Maintenance" not in root_instructions:
            print("FAIL: AGENTS.md is missing the continuous maintenance policy.", file=sys.stderr)
            return 1
        all_skills = sorted(
            path for pattern in (".agents/skills/**/SKILL.md", ".github/skills/**/SKILL.md", ".claude/skills/**/SKILL.md")
            for path in ROOT.glob(pattern)
        )
        for skill in all_skills:
            if "## Maintenance & Continuous Learning" not in skill.read_text(encoding="utf-8"):
                print(f"FAIL: {skill.relative_to(ROOT)} is missing Maintenance & Continuous Learning.", file=sys.stderr)
                return 1
        all_agent_files = [
            *ROOT.glob(".github/agents/**/*.agent.md"),
            *ROOT.glob(".claude/agents/**/*.agent.md"),
            *ROOT.glob(".github/instructions/**/*.instructions.md"),
            ROOT / ".github/copilot-instructions.md",
            ROOT / ".claude/CLAUDE.md",
            ROOT / ".cursorrules",
            *ROOT.glob(".cursor/rules/*"),
        ]
        for agent in all_agent_files:
            if not agent.is_file():
                continue
            if "Post-Change Knowledge Synchronization" not in agent.read_text(encoding="utf-8"):
                print(f"FAIL: {agent.relative_to(ROOT)} is missing Post-Change Knowledge Synchronization.", file=sys.stderr)
                return 1
        paths = changed_paths(args.base)
        project_paths = {p for p in paths if not p.startswith(("browser/", "vendor/", "i2p-java/data/", ".browser-build/"))}
        if not project_paths:
            print("Agent maintenance check: no project changes detected.")
            return 0
        docs = {p for p in project_paths if DOC_RE.search(p)}
        if not docs:
            print("FAIL: repository changes require an AGENTS.md, agent, or SKILL.md update.", file=sys.stderr)
            return 1
        updates = {p for p in docs if MAINTENANCE_RE.fullmatch(p) and substantive_addition(p, args.base)}
        if not updates:
            print("FAIL: no non-empty AGENTS.md, specialized agent, or SKILL.md content addition detected.", file=sys.stderr)
            print("Update the relevant operational instructions; whitespace-only or removal-only edits do not satisfy synchronization.", file=sys.stderr)
            return 1
        errors = [error for p in docs if (ROOT / p).exists() for error in validate_file(p)]
        if errors:
            print("FAIL: instruction structure/reference validation:", file=sys.stderr)
            for error in errors:
                print(f"  - {error}", file=sys.stderr)
            return 1
        print("Agent maintenance check: PASS")
        print(f"  Project paths changed: {len(project_paths)}")
        print(f"  Instruction files changed: {', '.join(sorted(docs))}")
        print(f"  Substantive maintenance additions: {', '.join(sorted(updates))}")
        print("  Note: semantic relevance still requires human review.")
        return 0
    except (RuntimeError, OSError, UnicodeError) as exc:
        print(f"Agent maintenance check: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
