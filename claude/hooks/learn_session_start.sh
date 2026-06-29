#!/usr/bin/env bash
# learn_session_start.sh — SessionStart: a gentle nudge when many sessions / repeated
# corrections have accumulated since the last /learn. Advisory, fail-open. Never auto-edits.
set -uo pipefail
A="$HOME/dotfiles/claude/skills/learn/session_analyzer.py"
{ [ -f "$A" ] && command -v jq >/dev/null 2>&1; } || exit 0
msg="$(python3 "$A" nudge 2>/dev/null || true)"
[ -n "$msg" ] || exit 0
jq -n --arg c "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
