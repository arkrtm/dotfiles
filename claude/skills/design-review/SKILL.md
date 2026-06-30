---
name: design-review
description: Adversarially review DESIGN.md + PLAN.md before GATE 2. Spawns a fresh-context design reviewer, then revises the design with the user. Advisory — informs /approve-design and changes no workflow state. Use after /design, before /approve-design, for non-trivial designs.
allowed-tools: Read, Edit, Glob, Grep, AskUserQuestion, Task
---

# /design-review — adversarial design sweep (GATE 2 prep, advisory)

Precondition: `/design` done — `DESIGN.md` + `PLAN.md` exist on a feature branch. This mirrors `/clarify`, but for the design: it does **not** advance state. It sharpens the design while fixes are still cheap (prose, not code + tests), before the human runs **`/approve-design`**.

1. Launch a fresh-context reviewer (avoids your own design assumptions): `@design-reviewer` — have it read `REQUIREMENTS.md`, `DESIGN.md`, `PLAN.md` and the code they touch, and return concrete design flaws across architectural soundness, over-engineering, design-level failure modes (concurrency / idempotency / rollback / migration), task decomposition & dependency order, and TDD-readiness. It is read-only and returns findings plus a `<DESIGN_VERDICT>` line.
2. Triage the findings. For each CRITICAL/HIGH, resolve genuine trade-offs with the user via `AskUserQuestion` (simpler-vs-flexible, what failure modes are in scope, cut scope). Don't bikeshed LOW ones.
3. Apply the agreed changes to `DESIGN.md` / `PLAN.md` (editing design docs is allowed on a feature branch; production code stays locked until GATE 2). Keep every requirement→task mapping intact so `/approve-design` still passes.
4. When the design holds up (verdict `pass`, or all blocking findings resolved), hand back to **`/approve-design`** — the authoritative human gate.

Scope: skip this for trivial changes (the workflow's escape hatch). It is advisory only — `/approve-design` remains the real GATE 2, and this step stamps no state.
