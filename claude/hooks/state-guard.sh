#!/usr/bin/env bash
# state-guard.sh — PreToolUse(Bash): stop the Bash tool from (a) forging workflow state and
# (b) writing production code in a way that dodges the Edit/Write gates. HARD (HIGH-1/HIGH 1).
# NOTE: without an OS sandbox a determined obfuscation (base64|sh, eval) can still evade a
# string guard — this raises the bar against accidental/helpful bypasses, not a hostile actor.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command -v jq >/dev/null 2>&1 || { echo "workflow enforcement requires jq, which is not on PATH" >&2; exit 2; }  # fail-CLOSED
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LIB="$DIR/lib"
in="$(cat)"; cmd="$(jq -r '.tool_input.command // ""' <<<"$in")"
deny(){ jq -n --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'; exit 0; }

# CRITICAL 2(a): block wf.sh mutators called via Bash — tolerate a quote right after wf.sh.
if grep -Eq "wf\.sh['\"]?[[:space:]]+(set|init|approve-requirements|approve-design|implementing|reviewed|to_reviewed|verified)\b" <<<"$cmd"; then
  deny "Workflow transitions are gated. Use the /approve-* skills or the TDD/verify/review flow; do not call wf.sh mutators directly."
fi
# CRITICAL 2(b): block writes into .workflow/ via any common write verb (not just >>/tee).
if grep -Eq "(>>?|tee|cp[[:space:]]|mv[[:space:]]|install[[:space:]]|dd[[:space:]]|ln[[:space:]]|sed[[:space:]]+-i|python[0-9.]*|jq[[:space:]]|printf|echo)[^|]*\.workflow/" <<<"$cmd"; then
  deny "Do not write .workflow/ from Bash; workflow state is machine-managed."
fi

# HIGH 1: when engaged, block writing CODE via Bash (which would dodge gate/branch/tdd guards).
if [ "$(bash "$LIB/wf.sh" get 2>/dev/null || echo none)" != none ]; then
  case "$cmd" in
    *.workflow/*|*/tmp/*|*scratchpad*) : ;;   # state writes handled above; tmp/scratch are fine
    *)
      if grep -Eq "(>>?|tee[[:space:]]+(-a[[:space:]]+)?|dd[[:space:]]+[^|]*of=|sed[[:space:]]+-i)[^|]*\.(py|pyi|toml|cfg|ini)\b" <<<"$cmd" \
         || grep -Eq "open\([^)]*['\"][wa]\+?['\"]|\.write_text\(|os\.replace\(|shutil\.(move|copy)" <<<"$cmd"; then
        deny "Write code via the Edit/Write tools (so the workflow gates apply), not via Bash file writes."
      fi
      ;;
  esac
fi
exit 0
