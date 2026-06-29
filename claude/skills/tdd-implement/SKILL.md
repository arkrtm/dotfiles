---
name: tdd-implement
description: Implement the approved plan task-by-task with strict TDD (red → green → refactor). Use after /approve-design to write production code.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(uv run pytest:*), Bash(uv run ruff:*), Bash(git:*), Bash(bash:*)
---

# /tdd-implement — TDD loop

```!
bash "$HOME/.claude/hooks/lib/wf.sh" implementing >/dev/null 2>&1; echo "next task: $(bash "$HOME/.claude/hooks/lib/next-task.sh")"
```
Work ONE task at a time, in dependency order (the next actionable id is above).

For each task:
1. **RED** — write the failing test first (from the task's `(test)` sub-step). Run it and SEE it fail: `uv run pytest -k <name>` (narrowed/`--testmon` runs are fine for the inner loop). Production edits stay blocked until a real test is red.
2. **GREEN** — write the minimal production code to pass. For a pure refactor with no behavior change: `touch .workflow/allow-refactor` first.
3. **REFACTOR** — clean up; ruff auto-formats on save.
4. Check the task's box in PLAN.md, move to the next.

Bug fixes: on a `fix/*` branch the failing reproduction test MUST come first (enforced). Never delete/skip/xfail a test to go green.

When all tasks are done, run **`/verify`** — the inner-loop narrowed greens are NOT authoritative.
