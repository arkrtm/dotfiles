---
name: design
description: Produce the technical design and a junior-proof task plan (GATE 2 prep) after requirements are approved. Writes DESIGN.md and PLAN.md. Use after /approve-requirements and creating a feature branch.
allowed-tools: Read, Write, Glob, Grep, Bash(bash:*), Bash(git:*)
---

# /design — design + plan (GATE 2 prep)

Precondition: requirements approved + on a feature branch. Tip: plan mode (Shift+Tab) adds an extra approval surface; the real GATE 2 is **`/approve-design`**.

## DESIGN.md
Architecture, data flow, error handling, testing strategy. Ground every decision in the actual code (read it). Keep it minimal — no speculative abstractions.

## PLAN.md — junior-proof, TDD-ready
Tasks a context-free junior could execute. Each is a checkbox:
```
- [ ] T1 — <title> · Requirements: R1.1, R1.2 · deps: -
  - (test) <test name> — asserts <observable behavior from the requirement>
  - (verify) <exact command> — expected: <output>
- [ ] T2 — <title> · Requirements: R2.1 · deps: T1
  - (test) …
  - (verify) …
```
Rules: every `R<n>.<m>` in REQUIREMENTS.md must appear in some task's `Requirements:` line (uncovered requirements block the gate). 2–5 min tasks, exact file paths, no placeholders (TBD/TODO/FIXME/implement later), each task carries a `(test)` and a `(verify)` sub-step.

When complete, ask the user to run **`/design-review`** (a fresh-context adversarial design sweep — optional for trivial designs), then **`/approve-design`**.
