---
name: approve-design
description: Approve the design and unlock implementation (GATE 2). Run this yourself after reviewing DESIGN.md and PLAN.md — it validates no placeholders, full requirement→task traceability, and (test)/(verify) sub-steps. Not for the model to invoke.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bash:*)
---

# /approve-design — GATE 2 (human only)

```!
bash "$HOME/.claude/hooks/lib/wf.sh" approve-design 2>&1
```

The command validated `PLAN.md` (no placeholders; every requirement covered by a task; each task has `(test)` and `(verify)`) and, if it passed, advanced the workflow to `design_approved` — production code is now unblocked.

- Printed `design_approved` → GATE 2 passed. Begin **`/tdd-implement`**.
- Printed `wf: …` error → fix PLAN.md/DESIGN.md (cover the listed requirements, remove placeholders) and re-run.
