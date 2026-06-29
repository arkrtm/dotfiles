#!/usr/bin/env bash
# status.sh — one-line workflow status + what's allowed now. Used by workflow_session_start.sh
# (SessionStart injection) and available on demand. Read-only, advisory, fail-open.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
state="$(bash "$LIB/wf.sh" get 2>/dev/null || echo none)"
[ "$state" = none ] && exit 0   # not engaged in this repo → say nothing
br="$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
plan="$proj/PLAN.md"; done=0; total=0
if [ -f "$plan" ]; then
  total="$(grep -cE '^- \[[ xX]\] *T[0-9]+' "$plan" 2>/dev/null || true)"
  done="$(grep -cE '^- \[[xX]\] *T[0-9]+' "$plan" 2>/dev/null || true)"
fi
nxt="$(bash "$LIB/next-task.sh" 2>/dev/null || true)"
printf 'Workflow: stage=%s branch=%s tasks=%s/%s' "$state" "$br" "$done" "$total"
[ -n "$nxt" ] && printf ' next=%s' "$nxt"
printf '\nAllowed now: '
case "$state" in
  idle)                       printf 'gather requirements (/spec). Code edits are blocked until design is approved.';;
  requirements_approved)      printf 'create a feature branch: git switch -c feat/<slug>.';;
  branched)                   printf 'write DESIGN.md + PLAN.md (/design), then /approve-design.';;
  design_approved|implementing) printf 'implement via TDD. main-branch code edits are blocked; narrowed (-k/--lf) green is NOT authoritative; run /verify for the green gate.';;
  reviewed)                   printf 'run /verify (full pytest+ruff+pyright+diff-cover) to reach verified.';;
  verified)                   printf 'done — commit / open a PR.';;
esac
printf '\n'
