#!/usr/bin/env bash
# discipline_subagent.sh — SubagentStart: inject the engineering discipline into spawned
# subagents, which do NOT inherit the parent's CLAUDE.md or model-invoked skills.
# (Claude Code docs: SubagentStart is context-only -> hookSpecificOutput.additionalContext.)
# Kept short — it loads once per subagent. Fail-open.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command -v jq >/dev/null 2>&1 || exit 0
ctx='Engineering discipline (applies to your work too):
- Never guess — read the actual code (cite file:line) before acting or answering.
- The ladder (stop at the first rung that holds): (1) needed at all? YAGNI (2) already in this repo? reuse it — grep first (3) stdlib? (4) native/framework feature or DB/ORM constraint? (5) an already-installed dependency? (6) one line? (7) only then the minimum that works. Lazy about the solution, never about reading.
- Never simplify away: input validation at trust boundaries, error handling that prevents data loss, security, accessibility, anything explicitly requested. Leave one runnable check for non-trivial logic.
- Surgical: change only what the task needs (ruff formats). Bug fix = root cause in the shared function, not a per-caller symptom patch.
- Done = fresh evidence: run the tests/types/lint and see green before claiming done; never trust an unverified "should pass".'
jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$c}}'
exit 0
