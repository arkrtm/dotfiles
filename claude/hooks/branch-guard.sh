#!/usr/bin/env bash
# branch-guard.sh — PreToolUse(Edit|Write): block CODE edits on main/master when engaged.
# Planning docs (*.md, docs/, .workflow/) are allowed on the default branch. HARD.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command -v jq >/dev/null 2>&1 || { echo "workflow enforcement requires jq, which is not on PATH" >&2; exit 2; }  # fail-CLOSED
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LIB="$DIR/lib"
in="$(cat)"
file="$(jq -r '.tool_input.file_path // empty' <<<"$in")"
[ -n "$file" ] || exit 0
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
state="$(bash "$LIB/wf.sh" get 2>/dev/null || echo none)"
[ "$state" = none ] && exit 0                      # engaged-only (decision #8)
br="$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
{ [ "$br" = main ] || [ "$br" = master ]; } || exit 0
rel="${file#"$proj"/}"
case "$rel" in *.md|docs/*|.workflow/*) exit 0 ;; esac
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Editing code on the default branch is blocked. Create a feature branch: git switch -c feat/<slug>."}}'
exit 0
