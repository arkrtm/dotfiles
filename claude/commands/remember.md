---
description: Save a durable memory to cc-memory for this project (explicit capture)
argument-hint: <the fact / how-to / event to remember>
allowed-tools: Bash($HOME/.claude/hooks/lib/ccmem.sh:*)
---
Persist what the user asked to remember into **cc-memory** (the per-project searchable store),
NOT Claude Code's built-in file memory. The user's text is:

$ARGUMENTS

Steps:
1. Decide `--type`:
   - `semantic` — a durable fact / preference / decision ("X is true", "I prefer Y").
   - `procedural` — a reusable how-to / recipe / workflow ("to do X, run Y").
   - `episodic` — a one-off event tied to now ("today we fixed X"). Default to `semantic` for
     standing knowledge; use `episodic` only for time-bound events.
2. Distill the text to ONE crisp memory (strip filler; keep it self-contained — no "this"/"it"
   that depends on the current chat). Pick 2–5 lowercase `--concepts` (comma-separated keywords)
   and, if specific files are central, pass `--files`.
3. Run. Keep the path UNQUOTED so the permission rule matches, but SINGLE-QUOTE the memory and
   concepts so any `$`, backtick, or `$(...)` is stored literally (escape an embedded single quote
   as `'\''`). Scope auto-resolves from cwd:
   ```bash
   $HOME/.claude/hooks/lib/ccmem.sh remember '<distilled memory>' \
     --type <semantic|procedural|episodic> --concepts 'a,b,c' --importance 0.6
   ```
   Bump `--importance` toward 0.8 for load-bearing facts; the CLI refuses likely secrets — if it
   refuses, tell the user and do NOT retry with the secret inlined.
4. Report the returned `id` and `scope` in one line. Do not also write to any other memory store.
