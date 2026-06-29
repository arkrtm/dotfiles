#!/usr/bin/env bash
# autofix.sh — PostToolUse(Edit|Write): ruff check --fix + format on .py edits.
# Runs from the project root so project-pinned ruff config applies (matches pre-commit).
# Reports via additionalContext (PostToolUse cannot revert; verify-gate is the hard floor).
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LIB="$DIR/lib"
in="$(cat)"
f="$(jq -r '.tool_input.file_path // empty' <<<"$in")"
{ [ -n "$f" ] && [[ "$f" == *.py ]] && [ -f "$f" ]; } || exit 0
command -v uv >/dev/null 2>&1 || exit 0
( cd "${CLAUDE_PROJECT_DIR:-$(dirname "$f")}" 2>/dev/null || exit 0
  read -r -a RUFF <<<"$(bash "$LIB/pyrun.sh" ruff)"
  "${RUFF[@]}" check --fix "$f" >/dev/null 2>&1 || true
  "${RUFF[@]}" format "$f"      >/dev/null 2>&1 || true )
jq -n --arg f "$f" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("ruff auto-fixed and formatted \($f). Re-read it before editing again.")}}'
exit 0
