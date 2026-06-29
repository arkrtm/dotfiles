#!/usr/bin/env bash
# tdd-guard.sh — PreToolUse(Edit|Write): TDD anti-cheat. HARD.
#  (A) tests/**: block deleting tests or adding skip/xfail/collect_ignore (silencing).
#  (B) production .py: require a recorded failing test (.workflow/red.json) before editing.
#      Escape a pure green refactor with: touch .workflow/allow-refactor
#      fix/* branches must add a reproduction test under tests/ first (G-REG-1).
# Applies only once design is approved (rank>=3). MUST be PreToolUse (PostToolUse can't block).
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
[ "$(bash "$LIB/wf.sh" rank 2>/dev/null || echo -1)" -ge 3 ] || exit 0
rel="${file#"$proj"/}"; base="$(basename "$file")"
deny(){ jq -n --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'; exit 0; }

is_test=0
case "$rel" in tests/*) is_test=1 ;; esac
case "$base" in test_*.py|*_test.py) is_test=1 ;; esac

if [ "$is_test" = 1 ]; then
  newstr="$(jq -r '[.tool_input.new_string, .tool_input.content, (.tool_input.edits[]?.new_string)] | map(select(. != null)) | join("\n")' <<<"$in")"
  oldstr="$(jq -r '[.tool_input.old_string, (.tool_input.edits[]?.old_string)] | map(select(. != null)) | join("\n")' <<<"$in")"
  if grep -Eq '@pytest\.mark\.(skip|xfail)|pytest\.skip\(|collect_ignore' <<<"$newstr" \
     && ! grep -Eq '@pytest\.mark\.(skip|xfail)|pytest\.skip\(|collect_ignore' <<<"$oldstr"; then
    deny "Adding skip/xfail/collect_ignore to silence a test is blocked. Fix the test or the code instead."
  fi
  if [ -n "$oldstr" ]; then
    o="$(grep -c 'def test' <<<"$oldstr" || true)"; n="$(grep -c 'def test' <<<"$newstr" || true)"
    [ "${n:-0}" -lt "${o:-0}" ] && deny "Deleting tests is blocked. If a test is wrong, fix it explicitly and say why."
  fi
  exit 0                                            # writing/repairing tests is allowed (red-first)
fi

case "$rel" in *.py) ;; *) exit 0 ;; esac          # only production python is TDD-gated
[ -f "$proj/.workflow/allow-refactor" ] && exit 0  # pure green refactor escape
br="$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
if [[ "$br" == fix/* ]]; then
  git -C "$proj" diff --name-only HEAD 2>/dev/null | grep -q '^tests/' \
    || deny "fix/* branch: write the failing reproduction test under tests/ BEFORE editing production code (G-REG-1)."
fi
red="$proj/.workflow/red.json"
if [ ! -s "$red" ] || ! jq -e '(.failing // []) | length > 0' "$red" >/dev/null 2>&1; then
  deny "No failing test recorded. Write a test that fails first (red) and run it, then implement (TDD). For a pure green refactor: touch .workflow/allow-refactor"
fi
exit 0
