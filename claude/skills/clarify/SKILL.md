---
name: clarify
description: Find ambiguities and gaps in REQUIREMENTS.md before approval. Spawns a fresh-context requirements analyst, then resolves each gap with the user. Use when requirements feel underspecified.
allowed-tools: Read, Edit, Glob, Grep, AskUserQuestion, Task
---

# /clarify — adversarial ambiguity sweep

1. Launch a fresh-context reviewer (avoids your own assumptions): `@requirements-analyst` — have it read `REQUIREMENTS.md` and return concrete gaps, ambiguities, and missing error-cases as a list. It is read-only and returns findings; it does not edit.
2. For each finding, insert a `[NEEDS CLARIFICATION: <question>]` marker at the relevant requirement.
3. Resolve them with the user via `AskUserQuestion` (batch independent ones), then replace each marker with the agreed EARS criterion (`R<n>.<m> WHEN/IF… SHALL`).
4. When no `[NEEDS CLARIFICATION]` remain, hand back to **`/approve-requirements`**.
