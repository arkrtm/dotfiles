#!/usr/bin/env bash
# gate-prereq.sh — PreToolUse(Edit|Write): enforce stage order + protect .workflow/. HARD.
# Not engaged (state=none) => pass through (trivial-change escape hatch).
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command -v jq >/dev/null 2>&1 || { echo "workflow enforcement requires jq, which is not on PATH" >&2; exit 2; }  # fail-CLOSED
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LIB="$DIR/lib"
in="$(cat)"
file="$(jq -r '.tool_input.file_path // empty' <<<"$in")"
[ -n "$file" ] || exit 0
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
state="$(bash "$LIB/wf.sh" get 2>/dev/null || echo none)"
[ "$state" = none ] && exit 0
bash "$LIB/wf.sh" normalize >/dev/null 2>&1   # CRITICAL 3: promote requirements_approved -> branched on a feature branch
deny(){ jq -n --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'; exit 0; }
# MEDIUM 9: canonical (physical) path check so ./ , ../ , and symlink prefixes can't dodge it.
wf="$(cd "$proj" 2>/dev/null && pwd -P)/.workflow"
fdir="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)" || fdir=""
case "$fdir/" in "$wf"/*|"$wf"/) deny "Workflow state is machine-managed. Use /approve-requirements, /approve-design, or the TDD/verify flow — do not edit .workflow/ directly." ;; esac
rel="${file#"$proj"/}"
min=3
case "$rel" in REQUIREMENTS.md|NOTES.md|README.md|docs/*.md|*.md) min=0 ;; esac   # LOW 1: only *.md docs are exempt
case "$rel" in *.py) min=3 ;; esac                                                # LOW 1: code under docs/ stays gated
case "$(basename "$file")" in DESIGN.md|PLAN.md) min=2 ;; esac
rank="$(bash "$LIB/wf.sh" rank 2>/dev/null || echo -1)"
if [ "$rank" -lt "$min" ]; then
  case "$min" in
    2) deny "Create a feature branch first (git switch -c feat/<slug>) before writing DESIGN.md/PLAN.md." ;;
    3) deny "Production code is blocked until design is approved. Flow: /spec → /approve-requirements → branch → /design → /approve-design." ;;
    *) deny "Blocked by workflow stage (need rank >= $min, current $rank)." ;;
  esac
fi
exit 0
