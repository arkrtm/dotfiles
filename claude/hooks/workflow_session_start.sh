#!/usr/bin/env bash
# workflow_session_start.sh — SessionStart(startup|resume): inject current workflow stage,
# next task, and what's allowed now (zero LLM cost). Prevents re-start drift and denied
# round-trips. Advisory, fail-open. Says nothing when not engaged in this repo.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LIB="$DIR/lib"
status="$(bash "$LIB/status.sh" 2>/dev/null || true)"
[ -n "$status" ] || exit 0
jq -n --arg c "$status" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
