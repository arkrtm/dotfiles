#!/usr/bin/env bash
# review-capture.sh — SubagentStop: the ONLY writer of .workflow/review.json, and the only
# path that advances implementing(4) -> reviewed(5). Runs outside the permission system, so
# the main agent / Bash / Edit cannot forge it. Only the verified adversarial-reviewer counts.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command -v jq >/dev/null 2>&1 || exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LIB="$DIR/lib"
in="$(cat)"
agent="$(jq -r '.subagent_type // .agent_name // empty' <<<"$in")"
tx="$(jq -r '.transcript_path // empty' <<<"$in")"
proj="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$in")}"
[ -n "$proj" ] || exit 0
# HIGH 3: fail-CLOSED on identity. No transcript-grep fallback (any subagent could print the marker).
[ "$agent" = "adversarial-reviewer" ] || exit 0
[ -n "$tx" ] && [ -f "$tx" ] || exit 0
# HIGH 4: decode the assistant text out of the JSONL (the marker lives inside a JSON string value,
# so its quotes are backslash-escaped) BEFORE grepping — otherwise jq parse fails and nothing is written.
txt="$(jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text' "$tx" 2>/dev/null)"
[ -n "$txt" ] || txt="$(jq -r '..|.text? // empty' "$tx" 2>/dev/null)"   # defensive fallback for unknown shapes
verdict_json="$(grep -ao '<REVIEW_VERDICT>.*</REVIEW_VERDICT>' <<<"$txt" | tail -1 | sed 's/<[^>]*>//g')"
[ -n "$verdict_json" ] || exit 0
mkdir -p "$proj/.workflow"
printf '%s' "$verdict_json" | jq '.' >"$proj/.workflow/review.json" 2>/dev/null || exit 0
# CRITICAL 1: advance to reviewed when the captured verdict passes (to_reviewed re-validates it).
if [ "$(jq -r '.verdict // empty' "$proj/.workflow/review.json" 2>/dev/null)" = pass ]; then
  CLAUDE_PROJECT_DIR="$proj" bash "$LIB/wf.sh" to_reviewed >/dev/null 2>&1 || true
fi
exit 0
