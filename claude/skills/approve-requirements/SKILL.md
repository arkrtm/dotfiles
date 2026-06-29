---
name: approve-requirements
description: Approve the requirements and unlock branch creation (GATE 1). Run this yourself after reviewing REQUIREMENTS.md — it validates EARS structure and stamps the workflow state. Not for the model to invoke.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(bash:*)
---

# /approve-requirements — GATE 1 (human only)

```!
bash "$HOME/.claude/hooks/lib/wf.sh" approve-requirements 2>&1
```

The command validated `REQUIREMENTS.md` (no `[NEEDS CLARIFICATION]`; EARS headings `### R<n>:`; each with ≥1 `R<n>.<m> WHEN/IF/WHILE/WHERE … SHALL`) and, if it passed, advanced the workflow to `requirements_approved`.

- Printed `requirements_approved` → GATE 1 passed. Next: create a feature branch (`git switch -c feat/<slug>`), then **`/design`**.
- Printed `wf: …` error → requirements aren't ready. Fix REQUIREMENTS.md (use **`/clarify`** for ambiguities) and re-run.
