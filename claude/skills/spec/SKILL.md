---
name: spec
description: Start a feature by gathering requirements (GATE 1 prep). Interview the user, then write REQUIREMENTS.md in EARS format. Use when beginning any non-trivial change, before writing code.
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion, Bash(bash:*), Bash(git:*)
argument-hint: <short feature description>
---

# /spec — requirements (GATE 1 prep)

Engage the workflow and gather requirements. Do NOT write production code here.

```!
bash "$HOME/.claude/hooks/lib/wf.sh" init >/dev/null 2>&1; bash "$HOME/.claude/hooks/lib/wf.sh" get
```

## Steps
1. **Understand the goal.** Read any code the user references — never guess, read it. Identify purpose, non-goals, constraints, success criteria.
2. **Interview with `AskUserQuestion`.** Ask only about genuinely open decisions. Batch independent axes into one call; one decision per question. Resolve ambiguities now.
3. **Write `REQUIREMENTS.md`** in EARS (WHAT/WHY, never HOW):
   ```
   # Requirements: <feature>
   ### R1: <user story>
   - R1.1 WHEN <trigger> THEN the system SHALL <observable behavior>
   - R1.2 IF <error condition> THEN the system SHALL <handling>
   ### R2: ...
   ```
   Use WHEN (event) / IF…THEN (error) / WHILE (state) / WHERE (feature) + SHALL. Every requirement gets ≥1 numbered, measurable criterion. List out-of-scope explicitly. Mark unresolved points `[NEEDS CLARIFICATION: …]`.
4. When REQUIREMENTS.md is complete with no `[NEEDS CLARIFICATION]`, ask the user to review it and run **`/approve-requirements`** (only they can pass the gate). If ambiguities remain, suggest **`/clarify`**.
