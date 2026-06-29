---
name: verify
description: Prove the change is done with fresh evidence — full tests, lint, types, diff-coverage — then run review. Use when implementation is complete, before declaring done.
allowed-tools: Read, Glob, Grep, Bash(uv run:*), Bash(uvx:*), Bash(git diff:*), Task
---

# /verify — fresh evidence + review

## Evidence (run now; do not trust prior runs)
```!
echo '--- pytest ---'; uv run pytest -q 2>&1 | tail -15; echo '--- ruff ---'; uvx ruff check . 2>&1 | tail -5; uvx ruff format --check . 2>&1 | tail -3; echo '--- pyright ---'; uvx pyright 2>&1 | tail -5; echo '--- diff ---'; git diff --stat
```
Read the output above. If anything is red, fix it and re-run `/verify`. Do not declare done on a red.

## Review
1. Run the built-in reviewer on the diff: **`/code-review`** (pick effort by blast radius — higher for public-API / `__init__.py` / schema changes).
2. Launch **`@adversarial-reviewer`** to check the diff against REQUIREMENTS.md and PLAN.md (correctness & requirement gaps only). Its verdict is captured to `.workflow/review.json`; a `pass` is required to advance to `reviewed`.
3. Resolve CRITICAL/HIGH findings. Re-review at most once; if new criticals appear, return to implementation.

The Stop gate re-runs the full suite + ruff + pyright + diff-cover ≥90% independently and won't let the turn end red — that green is the only authoritative "done".
